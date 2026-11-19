# Asequibilidad de una dieta saludable en Chile con la distribucion de ingresos de Casen
# FAO compara el costo de la dieta mas un costo de necesidades basicas no alimentarias con la
# distribucion de ingresos del Banco Mundial. Aqui se usa Casen y se mide cuanto pesa ese supuesto
# entrada: data/official/CoAHD_FAOSTAT.csv (FAOSTAT), data/fies_households.rds
# salida:  output/healthy_diet_affordability.csv, docs/img/healthy_diet_affordability.png

library(dplyr)
library(tidyr)
library(ggplot2)

fao <- read.csv("data/official/CoAHD_FAOSTAT.csv", fileEncoding = "latin1", check.names = FALSE)
chile <- fao %>% filter(Area == "Chile") %>%
  select(Item, Unit, starts_with("Y")) %>%
  pivot_longer(starts_with("Y"), names_to = "year", values_to = "value") %>%
  mutate(year = as.integer(sub("Y", "", year)))
cost <- chile %>% filter(grepl("^Cost of a healthy diet", Item), Unit == "LCU/cap/d") %>% select(year, cost_day = value)
pua  <- chile %>% filter(grepl("^Prevalence of unaffordability", Item)) %>% select(year, fao_pua = value)
reference <- inner_join(cost, pua, by = "year")
reference

hh <- readRDS("data/fies_households.rds") %>% filter(!is.na(income_pc), !is.na(w_persons))
days <- 365 / 12

# porcentaje de personas bajo un umbral diario, con el ingreso total per capita del hogar
share_below <- function(d, threshold) 100 * sum(d$w_persons[d$income_pc / days < threshold]) / sum(d$w_persons)

results <- bind_rows(lapply(intersect(unique(hh$year), reference$year), function(y) {
  d <- hh %>% filter(year == y)
  ref <- reference %>% filter(year == y)
  # asignacion no alimentaria diaria que, sumada al costo de la dieta, reproduce la cifra de FAO en Casen
  implied <- uniroot(function(x) share_below(d, ref$cost_day + x) - ref$fao_pua, c(0, 50000))$root
  data.frame(year = y, cost_day = ref$cost_day, fao_pua = ref$fao_pua,
             income_below_cost = share_below(d, ref$cost_day),
             food_budget_52pct_below_cost = share_below(d, ref$cost_day / 0.52),
             implied_nonfood_allowance_day = implied,
             implied_threshold_month = (ref$cost_day + implied) * days,
             median_income_month = with(d[order(d$income_pc), ], income_pc[which(cumsum(w_persons) >= sum(w_persons) / 2)[1]]))
}))
results %>% mutate(across(where(is.numeric), ~ round(.x, 1)))
# el umbral implicito como proporcion del ingreso mediano
round(results$implied_threshold_month / results$median_income_month, 2)

write.csv(results, "output/healthy_diet_affordability.csv", row.names = FALSE)

# curva: porcentaje que no alcanza segun la asignacion no alimentaria, ultimo ano
last <- max(results$year)
d <- hh %>% filter(year == last)
ref <- reference %>% filter(year == last)
curve <- data.frame(allowance = seq(0, 12000, by = 250))
curve$share <- sapply(curve$allowance, function(x) share_below(d, ref$cost_day + x))
g <- ggplot(curve, aes(allowance, share)) + geom_line(colour = "#1f4e79", linewidth = 0.9) +
  geom_hline(yintercept = ref$fao_pua, linetype = "dashed", colour = "grey40") +
  annotate("text", x = 200, y = ref$fao_pua + 2.5, hjust = 0, size = 3.4, label = paste0("FAO: ", ref$fao_pua, "%")) +
  labs(x = "Non-food allowance added to the cost of the diet (pesos per person per day)",
       y = "People below the threshold, %",
       title = paste0("Unaffordability of a healthy diet in Chile, ", last),
       subtitle = "Casen income distribution. The dashed line is FAO's published prevalence.") +
  theme_minimal(base_size = 11)
ggsave("docs/img/healthy_diet_affordability.png", g, width = 7.5, height = 4.2, dpi = 150, bg = "white")
