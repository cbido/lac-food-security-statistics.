# Paquetes de R que usan los scripts
# versiones con las que se corrio: R 4.3.3, RM.weights 2.0, survey 4.2.1, sae 1.4, dplyr 1.1.4, ggplot2 3.4.4, sf 1.0.15, chilemapas 0.4.1

packages <- c("haven", "dplyr", "tidyr", "readxl", "RM.weights", "survey", "sae", "ggplot2", "sf", "chilemapas")
missing  <- setdiff(packages, rownames(installed.packages()))
missing
if (length(missing) > 0) install.packages(missing, repos = "https://cloud.r-project.org")
