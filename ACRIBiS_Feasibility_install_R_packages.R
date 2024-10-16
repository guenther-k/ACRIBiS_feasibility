required_packages <- c("fhircrackr", "dplyr", "sqldf", "anytime", "ICD10gm", "knitr", "xml2", "lubridate")

for(package in required_packages){
  
  available <- suppressWarnings(require(package, character.only = T))
  
  if(!available){
    install.packages(package, repos="https://ftp.fau.de/cran/", quiet = TRUE)
  }
}

library(fhircrackr)
library(dplyr)
library(tidyr)
library(sqldf)
library(anytime)
library(ICD10gm)
library(knitr)
library(xml2)
library(lubridate)


