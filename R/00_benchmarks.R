# Cifras oficiales de inseguridad alimentaria para comparar
# entrada: data/official/Estimaciones_Inseguridad_Alimentaria_Casen_2024.xlsx (Ministerio de Desarrollo Social y Familia)
# salida:  benchmarks/official_national.csv, benchmarks/official_region.csv

library(readxl)
library(dplyr)
library(tidyr)

path <- "data/official/Estimaciones_Inseguridad_Alimentaria_Casen_2024.xlsx"
years <- c(2017, 2020, 2022, 2024)

# el primer bloque de cada hoja trae la estimación: fila de encabezado con los años y luego las categorías
read_block <- function(sheet) {
  x <- suppressMessages(read_excel(path, sheet = sheet, col_names = FALSE))
  header <- which(x[[2]] == years[1])[1]
  total  <- which(grepl("^Total", x[[1]]))[1]
  block <- x[(header + 1):total, 1:5]
  names(block) <- c("category", years)
  block %>% mutate(across(-category, as.numeric))
}

modsev <- read_block("1")
sev    <- read_block("22")
national <- data.frame(year = years, unit = "households",
                       official_modsev = as.numeric(modsev[1, -1]), official_sev = as.numeric(sev[1, -1]))
# a nivel de personas el ministerio publica solo moderada-severa, en el informe de resultados Casen 2022
persons <- data.frame(year = c(2017, 2020, 2022), unit = "persons",
                      official_modsev = c(13.6, 19.6, 19.5), official_sev = NA)
national <- bind_rows(national, persons)
national

# las hojas regionales listan las 16 regiones siempre en este orden (norte a sur, con la Metropolitana
# tras Valparaiso y las regiones nuevas en su ubicacion geografica); codigo de region de Casen
region_order <- data.frame(
  region = c(15, 1, 2, 3, 4, 5, 13, 6, 7, 16, 8, 9, 14, 10, 11, 12),
  region_name = c("Arica y Parinacota", "Tarapaca", "Antofagasta", "Atacama", "Coquimbo", "Valparaiso",
                  "Metropolitana", "O'Higgins", "Maule", "Nuble", "Biobio", "La Araucania", "Los Rios",
                  "Los Lagos", "Aysen", "Magallanes"))
long <- function(block, name) {
  block <- block[-nrow(block), ]                    # sin la fila del total
  stopifnot(nrow(block) == 16)
  cbind(region_order, block[, -1]) %>%
    pivot_longer(-c(region, region_name), names_to = "year", values_to = name) %>%
    mutate(year = as.integer(year))
}
region <- long(read_block("3"), "official_modsev") %>%
  left_join(long(read_block("24"), "official_sev"), by = c("region", "region_name", "year")) %>%
  select(year, region, region_name, official_modsev, official_sev)
nrow(region)
sum(is.na(region$region))

write.csv(national, "benchmarks/official_national.csv", row.names = FALSE)
write.csv(region, "benchmarks/official_region.csv", row.names = FALSE)
