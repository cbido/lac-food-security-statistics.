# Inseguridad alimentaria moderada o severa por comuna, Casen 2022: directa y Fay-Herriot
# se compara con las estimaciones comunales que publica el ministerio
# entrada: data/fies_probabilities.rds, tablas oficiales en data/official
# salida:  output/comuna_estimates_2022.csv, output/comuna_comparison_2022.csv,
#          docs/img/comuna_vs_official.png, docs/img/comuna_map.png

library(dplyr)
library(readxl)
library(survey)
library(sae)
library(ggplot2)
library(sf)
library(chilemapas)

options(survey.lonely.psu = "adjust")
hh <- readRDS("data/fies_probabilities.rds") %>% filter(year == 2022, !is.na(comuna), !is.na(w_hh_comuna))
nrow(hh)
length(unique(hh$comuna))

# 1. estimacion directa con el factor de expansion comunal
des <- svydesign(ids = ~varunit, strata = ~varstrat, weights = ~w_hh_comuna, data = hh, nest = TRUE)
direct <- as.data.frame(svyby(~p_modsev, ~comuna, des, svymean, deff = TRUE))
names(direct) <- c("comuna", "p_direct", "se_direct", "deff")
size <- hh %>% group_by(comuna) %>% summarise(n = n(), n_psu = n_distinct(varunit))
direct <- left_join(direct, size, by = "comuna")
summary(direct$n)
summary(direct$se_direct / direct$p_direct)

# 2. varianza suavizada en escala arcoseno, con la mediana del efecto de diseno
deff_med <- median(direct$deff[direct$n >= 100 & is.finite(direct$deff)])
deff_med
direct <- direct %>% mutate(z = asin(sqrt(p_direct)), var_z = deff_med / (4 * n))

# 3. variables auxiliares publicas: pobreza comunal oficial 2022, poblacion y region
# ojo: la pobreza comunal oficial es a su vez una estimacion de areas pequenas del ministerio
official_table <- function(file, cols, names) {
  x <- suppressMessages(read_excel(file, col_names = FALSE, skip = 3))
  x <- x[!is.na(suppressWarnings(as.numeric(x[[1]]))), cols]
  setNames(as.data.frame(lapply(x, function(v) suppressWarnings(as.numeric(v)))), names)
}
poverty <- official_table("data/official/Estimaciones_Tasa_Pobreza_Ingresos_Comunas_2022.xlsx",
                          c(1, 4, 6), c("comuna", "population", "poverty_official"))
official <- official_table("data/official/Estimacion_Inseguridad_Alimentaria_Comunal_2022.xlsx",
                           c(1, 4, 5, 6), c("comuna", "p_official", "lower_official", "upper_official"))
nrow(poverty)
sum(!is.na(official$p_official))

all_comunas <- poverty %>%
  mutate(region = factor(comuna %/% 1000), z_poverty = asin(sqrt(poverty_official)), log_pop = log(population)) %>%
  left_join(direct, by = "comuna") %>%
  left_join(official, by = "comuna")
fit_set <- all_comunas %>% filter(!is.na(p_direct), n >= 50, n_psu >= 2, !is.na(z_poverty))
nrow(fit_set)

# 4. modelo de area
fit <- mseFH(z ~ z_poverty + log_pop + region, vardir = var_z, data = fit_set, method = "REML")
fit$est$fit$estcoef[1:3, ]
fit_set$z_fh  <- as.numeric(fit$est$eblup)
fit_set$mse_z <- fit$mse
fit_set$gamma <- fit$est$fit$refvar / (fit$est$fit$refvar + fit_set$var_z)
summary(fit_set$gamma)

X <- model.matrix(~ z_poverty + log_pop + region, data = all_comunas)
all_comunas$z_syn <- NA
all_comunas$z_syn[as.integer(rownames(X))] <- as.numeric(X %*% fit$est$fit$estcoef$beta)
est <- all_comunas %>%
  left_join(fit_set %>% dplyr::select(comuna, z_fh, mse_z, gamma), by = "comuna") %>%
  mutate(type = ifelse(is.na(z_fh), "synthetic", "fay-herriot"),
         p_fh = sin(ifelse(is.na(z_fh), z_syn, z_fh))^2)
table(est$type)

# 5. contraste con las cifras comunales oficiales
compare <- function(label, estimate, rows) {
  ok <- rows & !is.na(estimate) & !is.na(est$p_official)
  data.frame(estimate = label, comunas = sum(ok),
             correlation = cor(estimate[ok], est$p_official[ok]),
             mean_abs_diff_points = 100 * mean(abs(estimate[ok] - est$p_official[ok])),
             share_inside_official_interval = mean((estimate >= est$lower_official & estimate <= est$upper_official)[ok]))
}
in_fit <- est$type == "fay-herriot"
comparison <- bind_rows(
  compare("direct, comunas in the model", est$p_direct, in_fit),
  compare("fay-herriot, comunas in the model", est$p_fh, in_fit),
  compare("synthetic, comunas outside the model", est$p_fh, !in_fit),
  compare("fay-herriot or synthetic, all comunas", est$p_fh, rep(TRUE, nrow(est))))
comparison
# precision: error estandar directo contra raiz del ECM del modelo, escala arcoseno
mean(sqrt(fit_set$mse_z) < sqrt(fit_set$var_z))
summary(sqrt(fit_set$mse_z) / sqrt(fit_set$var_z))

write.csv(est %>% dplyr::select(comuna, region, population, n, n_psu, p_direct, se_direct, gamma, type, p_fh,
                                p_official, lower_official, upper_official),
          "output/comuna_estimates_2022.csv", row.names = FALSE)
write.csv(comparison, "output/comuna_comparison_2022.csv", row.names = FALSE)

# figuras
plot_data <- bind_rows(
  est %>% filter(in_fit) %>% transmute(official = p_official, own = p_direct, kind = "Direct estimate"),
  est %>% transmute(official = p_official, own = p_fh, kind = "Fay-Herriot (this repository)"))
g1 <- ggplot(plot_data, aes(official, own)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey50") +
  geom_point(alpha = 0.5, size = 1.2, colour = "#1f4e79") +
  facet_wrap(~kind) +
  scale_x_continuous(labels = function(x) paste0(round(100 * x), "%")) +
  scale_y_continuous(labels = function(x) paste0(round(100 * x), "%")) +
  labs(x = "Official small-area estimate (ministry)", y = "This repository",
       title = "Moderate or severe food insecurity by comuna, households, 2022") +
  theme_minimal(base_size = 11)
ggsave("docs/img/comuna_vs_official.png", g1, width = 8, height = 4.2, dpi = 150, bg = "white")

# mapa, sin Isla de Pascua ni Juan Fernandez, que distorsionan la escala
map <- chilemapas::mapa_comunas %>%
  mutate(comuna = as.integer(codigo_comuna)) %>%
  filter(!comuna %in% c(5201, 5104)) %>%
  left_join(est %>% dplyr::select(comuna, p_fh), by = "comuna") %>%
  st_as_sf()
table(is.na(map$p_fh))
g2 <- ggplot(map) + geom_sf(aes(fill = p_fh), colour = NA) +
  scale_fill_viridis_c(option = "magma", direction = -1, labels = function(x) paste0(round(100 * x), "%"),
                       name = "Households") +
  labs(title = "Food insecurity by comuna, 2022", subtitle = "Fay-Herriot estimates") +
  theme_void(base_size = 10)
ggsave("docs/img/comuna_map.png", g2, width = 3.6, height = 9, dpi = 150, bg = "white")
