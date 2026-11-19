# Base a nivel de hogar con los ocho ítems de la escala FIES, Casen 2017, 2020, 2022 y 2024
# entrada: archivos oficiales en data/raw (ver R/00_download.R)
# salida:  data/fies_households.rds

library(haven)
library(dplyr)

raw <- "data/raw"
files <- c(`2017` = "Casen 2017\\.dta$",
           `2020` = "Casen_en_Pandemia_2020.*\\.dta$",
           `2022` = "Casen 2022.*\\.dta$",
           `2024` = "casen_2024\\.RData$")
comuna_files <- c(`2022` = "casen_2022_provincia_comuna\\.dta$",
                  `2024` = "casen_2024_provincia_comuna\\.dta$")
items <- paste0("r8", letters[1:8])
fies_names <- c("WORRIED", "HEALTHY", "FEWFOOD", "SKIPPED", "ATELESS", "RUNOUT", "HUNGRY", "WHLDAY")

read_casen <- function(year) {
  path <- list.files(raw, pattern = files[[year]], full.names = TRUE)
  stopifnot(length(path) == 1)
  keep <- c("folio", "region", "comuna", "varstrat", "varunit", "expr", "expc", "pco1",
            "numper", "ytotcorh", "pobreza", items)
  if (grepl("RData$", path)) {
    e <- new.env()
    d <- get(load(path, envir = e)[1], envir = e)
    d <- d[, intersect(keep, names(d))]
  } else {
    d <- read_dta(path, col_select = any_of(keep))
  }
  d <- zap_labels(d)
  # comuna y factor comunal vienen en un archivo aparte desde 2022
  if (year %in% names(comuna_files)) {
    cpath <- list.files(raw, pattern = comuna_files[[year]], full.names = TRUE)
    cm <- zap_labels(read_dta(cpath, col_select = any_of(c("folio", "id_persona", "comuna", "expc"))))
    cm <- cm %>% group_by(folio) %>% summarise(comuna = first(comuna), expc = first(expc))
    d <- d %>% select(-any_of(c("comuna", "expc"))) %>% left_join(cm, by = "folio")
  }
  d$year <- as.integer(year)
  d
}

household_level <- function(d) {
  # una fila por hogar: respuestas del módulo, factor del hogar y suma de factores de sus integrantes
  persons <- d %>% group_by(folio) %>% summarise(w_persons = sum(expr), n_persons = n())
  hh <- d %>% filter(pco1 == 1) %>% left_join(persons, by = "folio")
  for (i in seq_along(items)) {
    x <- hh[[items[i]]]
    hh[[fies_names[i]]] <- ifelse(x == 1, 1L, ifelse(x == 2, 0L, NA_integer_))   # 9 = no sabe/no responde
  }
  hh %>% transmute(year, folio, region, comuna, varstrat, varunit,
                   w_hh = expr, w_hh_comuna = expc, w_persons, n_persons,
                   income_pc = ytotcorh / numper, poverty = pobreza,
                   across(all_of(fies_names)))
}

fies <- bind_rows(lapply(names(files), function(y) household_level(read_casen(y))))

# en 2020 y 2022 las cuatro últimas preguntas no se hicieron a los hogares que respondieron "No"
# a las cuatro primeras: esas respuestas se registran como "No"
first4 <- fies_names[1:4]
last4  <- fies_names[5:8]
fies <- as.data.frame(fies)
skipped <- rowSums(fies[, first4] == 0, na.rm = TRUE) == 4 & rowSums(is.na(fies[, last4])) == 4
table(fies$year, skipped)
fies[skipped, last4] <- 0L

nrow(fies)
table(fies$year)
# hogares con algún ítem sin respuesta, por año
tapply(rowSums(is.na(fies[, fies_names])) > 0, fies$year, sum)
# respuestas afirmativas por ítem y año (%, sin ponderar)
round(100 * sapply(fies_names, function(v) tapply(fies[[v]], fies$year, mean, na.rm = TRUE)), 1)

saveRDS(fies, "data/fies_households.rds")
