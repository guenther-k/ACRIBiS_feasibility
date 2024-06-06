# install.packages("fhircrackr")
# install.packages("dplyr")
# install.packages("sqldf")
# install.packages("anytime")
# install.packages("ICD10gm")
# install.packages("knitr")
# install.packages("xml2")


required_packages <- c("fhircrackr", "dplyr", "sqldf", "anytime", "ICD10gm", "knitr", "xml2")

for(package in required_packages){
  
  available <- suppressWarnings(require(package, character.only = T))
  
  if(!available){
    install.packages(package, repos="https://ftp.fau.de/cran/", quiet = TRUE)
  }
}

library(fhircrackr)
library(dplyr)
library(sqldf)
library(anytime)
library(ICD10gm)
library(knitr)
library(xml2)