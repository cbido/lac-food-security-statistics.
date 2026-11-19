# Prevalencia de inseguridad alimentaria (ODS 2.1.2) con el modelo de Rasch y la escala global de FAO
# entrada: data/fies_households.rds
# salida:  output/item_severity.csv, output/prevalence_national.csv, output/prevalence_region.csv,
#          data/fies_probabilities.rds, docs/img/item_severity.png, docs/img/prevalence_trend.png

library(RM.weights)
library(dplyr)
library(tidyr)
library(survey)
library(ggplot2)

options(survey.lonely.psu = "adjust")
fies <- readRDS("data/fies_households.rds")
fies_names <- c("WORRIED", "HEALTHY", "FEWFOOD", "SKIPPED", "ATELESS", "RUNOUT", "HUNGRY", "WHLDAY")

# dos especificaciones:
#  fao_default: supuestos por defecto del paquete de FAO (puntaje extremo 7.5, tolerancia 0.35)
#  replication: la que reproduce las cifras oficiales del ministerio. Puntaje extremo 7.6 y, en 2017 y 2020,
#               los items que mas se alejan del estandar global se tratan como propios del pais
specs <- list(
  fao_default = list(d = c(0.5, 7.5), unique = list(`2017` = integer(0), `2020` = integer(0), `2022` = integer(0), `2024` = integer(0))),
  replication = list(d = c(0.5, 7.6), unique = list(`2017` = 1, `2020` = c(1, 4), `2022` = integer(0), `2024` = integer(0))))

fit_year <- function(y, spec) {
  d <- fies %>% filter(year == y)
  complete <- rowSums(is.na(d[, fies_names])) == 0
  d <- d[complete, ]
  XX <- as.data.frame(d[, fies_names])            # equating.fun espera un data.frame
  rr <- RM.w(XX, d$w_hh, .d = spec$d)
  # equiparacion con el estandar global 2014-2016 de FAO (por defecto en equating.fun)
  common <- setdiff(1:8, spec$unique[[as.character(y)]])
  ee <- equating.fun(rr, tol = 0.35, spec.com1 = common, spec.com2 = common)
  # probabilidad de estar sobre cada umbral segun puntaje bruto (0 a 8)
  probs <- ee$probs.rs
  d$raw_score <- rowSums(XX)
  d$p_modsev <- probs[d$raw_score + 1, 1]
  d$p_sev    <- probs[d$raw_score + 1, 2]
  list(data = d, rr = rr, ee = ee, dropped = sum(!complete))
}

years <- sort(unique(fies$year))
fits_default <- lapply(years, fit_year, spec = specs$fao_default)
fits <- lapply(years, fit_year, spec = specs$replication)
names(fits) <- names(fits_default) <- years

# ---- calidad de la escala --------------------------------------------------------------------
item_table <- bind_rows(lapply(years, function(y) {
  f <- fits[[as.character(y)]]
  common <- f$ee$common == "Common"
  data.frame(year = y, item = fies_names,
             severity = as.numeric(f$rr$b), se = as.numeric(f$rr$se.b),
             severity_global_metric = as.numeric(f$rr$b) * f$ee$scale + f$ee$shift,
             infit = as.numeric(f$rr$infit), outfit = as.numeric(f$rr$outfit),
             common_with_global = common)
}))
scale_table <- bind_rows(lapply(years, function(y) {
  f <- fits[[as.character(y)]]
  data.frame(year = y, households = nrow(f$data), dropped_incomplete = f$dropped,
             reliability = f$rr$reliab.fl,
             common_items = sum(f$ee$common == "Common"),
             correlation_with_global = f$ee$cor.comm.items)
}))
item_table %>% mutate(across(where(is.numeric), ~ round(.x, 2))) %>% select(year, item, severity_global_metric, infit, common_with_global)
scale_table

# ---- prevalencias con diseño muestral ----------------------------------------------------------
hh <- bind_rows(lapply(fits, function(f) f$data))
saveRDS(hh, "data/fies_probabilities.rds")

estimate <- function(d, weight, by = NULL) {
  des <- svydesign(ids = ~varunit, strata = ~varstrat, weights = as.formula(paste0("~", weight)), data = d, nest = TRUE)
  if (is.null(by)) {
    m <- svymean(~p_modsev + p_sev, des)
    data.frame(modsev = coef(m)[1], modsev_se = SE(m)[1], sev = coef(m)[2], sev_se = SE(m)[2])
  } else {
    m <- svyby(~p_modsev + p_sev, as.formula(paste0("~", by)), des, svymean)
    out <- data.frame(m[[by]], m$p_modsev, m$se.p_modsev, m$p_sev, m$se.p_sev)
    names(out) <- c(by, "modsev", "modsev_se", "sev", "sev_se")
    out
  }
}

national_of <- function(fit_list, spec_name) {
  bind_rows(lapply(years, function(y) {
    d <- fit_list[[as.character(y)]]$data
    bind_rows(cbind(year = y, unit = "households", spec = spec_name, estimate(d, "w_hh")),
              cbind(year = y, unit = "persons", spec = spec_name, estimate(d, "w_persons")))
  }))
}
national <- bind_rows(national_of(fits_default, "fao_default"), national_of(fits, "replication"))
rownames(national) <- NULL

# cifras oficiales del Ministerio de Desarrollo Social y Familia (R/00_benchmarks.R)
official <- read.csv("benchmarks/official_national.csv")
national <- national %>% left_join(official, by = c("year", "unit")) %>%
  mutate(diff_modsev = 100 * modsev - official_modsev, diff_sev = 100 * sev - official_sev)
national %>% filter(unit == "households") %>%
  mutate(across(c(modsev, modsev_se, sev, sev_se), ~ round(100 * .x, 2)), across(starts_with("diff"), ~ round(.x, 2))) %>%
  select(year, spec, modsev, official_modsev, diff_modsev, sev, official_sev, diff_sev)
national %>% filter(unit == "persons", spec == "replication") %>%
  transmute(year, modsev = round(100 * modsev, 2), official_modsev, sev = round(100 * sev, 2))

region <- bind_rows(lapply(years, function(y) cbind(year = y, estimate(hh %>% filter(year == y), "w_hh", by = "region"))))
official_region <- read.csv("benchmarks/official_region.csv")
region <- region %>% left_join(official_region, by = c("year", "region")) %>%
  mutate(diff_modsev = 100 * modsev - official_modsev)
# diferencia absoluta media con las cifras regionales oficiales, en puntos
round(tapply(abs(region$diff_modsev), region$year, mean, na.rm = TRUE), 2)
round(tapply(abs(region$diff_modsev), region$year, max, na.rm = TRUE), 2)

write.csv(item_table, "output/item_severity.csv", row.names = FALSE)
write.csv(scale_table, "output/scale_quality.csv", row.names = FALSE)
write.csv(national, "output/prevalence_national.csv", row.names = FALSE)
write.csv(region, "output/prevalence_region.csv", row.names = FALSE)

# ---- figuras ------------------------------------------------------------------------------------
p1 <- ggplot(item_table, aes(x = severity_global_metric, y = reorder(item, severity_global_metric), colour = factor(year))) +
  geom_point(size = 2.6, alpha = 0.85) +
  labs(x = "Item severity on the global FIES metric", y = NULL, colour = "Casen round",
       title = "Item severities, Chile 2017 to 2024") +
  theme_minimal(base_size = 12) + theme(legend.position = "bottom")
ggsave("docs/img/item_severity.png", p1, width = 7.5, height = 4.2, dpi = 160, bg = "white")

trend <- national %>% filter(unit == "households", spec == "replication") %>%
  transmute(year, `This repository` = 100 * modsev, `Ministry (official)` = official_modsev) %>%
  pivot_longer(-year, names_to = "source", values_to = "value")
p2 <- ggplot(trend, aes(year, value, colour = source)) + geom_line() + geom_point(size = 2.4) +
  scale_x_continuous(breaks = years) + expand_limits(y = 0) +
  labs(x = NULL, y = "Households, %", colour = NULL,
       title = "Moderate or severe food insecurity, Chile") +
  theme_minimal(base_size = 12) + theme(legend.position = "bottom")
ggsave("docs/img/prevalence_trend.png", p2, width = 7.5, height = 4.2, dpi = 160, bg = "white")
