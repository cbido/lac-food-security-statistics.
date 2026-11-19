# Descarga de los archivos publicos: Casen (Ministerio de Desarrollo Social y Familia) y FAOSTAT
# deja todo en data/raw y data/official. Los archivos que ya existen no se vuelven a bajar

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("data/official", recursive = TRUE, showWarnings = FALSE)
options(timeout = 3600)

casen <- "https://observatorio.ministeriodesarrollosocial.gob.cl/storage/docs/casen"
# el servidor rechaza %20: los espacios de los nombres van como "+"
microdata <- data.frame(
  url = c(paste0(casen, "/2017/casen_2017_stata.rar"),
          paste0(casen, "/2020/Casen_en_Pandemia_2020_STATA_revisada2022_09.dta.zip"),
          paste0(casen, "/2022/Base+de+datos+Casen+2022+STATA_18+marzo+2024.dta.zip"),
          paste0(casen, "/2022/casen_2022_provincia_comuna.dta"),
          paste0(casen, "/2024/casen_2024.RData"),
          paste0(casen, "/2024/casen_2024_provincia_comuna.dta")),
  file = c("casen_2017_stata.rar", "casen_2020.dta.zip", "casen_2022.dta.zip",
           "casen_2022_provincia_comuna.dta", "casen_2024.RData", "casen_2024_provincia_comuna.dta"),
  # patron del archivo ya descomprimido, para no repetir la descarga
  ready = c("Casen 2017\\.dta$", "Casen_en_Pandemia_2020.*\\.dta$", "Casen 2022.*\\.dta$",
            "casen_2022_provincia_comuna\\.dta$", "casen_2024\\.RData$", "casen_2024_provincia_comuna\\.dta$"))

for (i in seq_len(nrow(microdata))) {
  if (length(list.files("data/raw", pattern = microdata$ready[i])) > 0) next
  dest <- file.path("data/raw", microdata$file[i])
  download.file(microdata$url[i], dest, mode = "wb")
  if (grepl("\\.zip$", dest)) unzip(dest, exdir = "data/raw")
}
# Casen 2017 viene en .rar: hay que descomprimirlo a mano (por ejemplo con The Unarchiver o 7-Zip)
# y dejar "Casen 2017.dta" en data/raw
sapply(microdata$ready, function(p) length(list.files("data/raw", pattern = p)))

official <- c(
  "Estimaciones_Inseguridad_Alimentaria_Casen_2024.xlsx" = paste0(casen, "/2024/Estimaciones_Inseguridad_Alimentaria_Casen_2024.xlsx"),
  "Estimacion_Inseguridad_Alimentaria_Comunal_2022.xlsx" = "https://observatorio.ministeriodesarrollosocial.gob.cl/storage/docs/inseguridad-alimentaria/2022/Estimacion_Inseguridad_Alimentaria_Comunal_2022.xlsx",
  "Estimaciones_Tasa_Pobreza_Ingresos_Comunas_2022.xlsx" = "https://observatorio.ministeriodesarrollosocial.gob.cl/storage/docs/pobreza-comunal/2022/Estimaciones_Tasa_Pobreza_Ingresos_Comunas_2022.xlsx")
for (f in names(official)) {
  dest <- file.path("data/official", f)
  if (!file.exists(dest)) download.file(official[[f]], dest, mode = "wb")
}

# costo y asequibilidad de una dieta saludable, descarga masiva de FAOSTAT
if (!file.exists("data/official/CoAHD_FAOSTAT.csv")) {
  zip <- file.path("data/official", "CoAHD.zip")
  download.file("https://bulks-faostat.fao.org/production/Cost_Affordability_Healthy_Diet_(CoAHD)_E_All_Data.zip", zip, mode = "wb")
  inside <- unzip(zip, list = TRUE)$Name
  csv <- inside[grepl("All_Data_NOFLAG\\.csv$", inside)]
  unzip(zip, files = csv, exdir = "data/official")
  file.rename(file.path("data/official", csv), "data/official/CoAHD_FAOSTAT.csv")
}
list.files("data/official")
