source("ACRIBiS_Feasibility_install_R_packages.R")
source("ACRIBiS_Feasibility_support_functions.R")
source("ACRIBiS_Feasibility_config.R")

#source config
# if(file.exists("ACRIBiS_Feasibility_config.R")&&!dir.exists("ACRIBiS_Feasibility_config.R")){
#   source("ACRIBiS_Feasibility_config.R")
# }else{
#   source("config.R.default")  
# }


#create log file, named for date and time of creation
if(!dir.exists("Logs")){dir.create("Logs")}
log <- paste0("logs/", format(Sys.time(), "%Y%m%d_%H%M%S"),".txt", collapse = "")
write(paste("Starting Script ACRIBiS_Feasibility_Script.R at", Sys.time()), file = log, append = T)


# Setup -------------------------------------------------------------------
#create output directory
if(!dir.exists("Output")){dir.create("Output")}
if(!dir.exists("errors")){dir.create("errors")}
if(!dir.exists("XML_Bundles")){dir.create("XML_Bundles")}

#If needed disable peer verification
if(!ssl_verify_peer){httr::set_config(httr::config(ssl_verifypeer = 0L))}

#remove trailing slashes from endpoint
diz_url <- if(grepl("/$", diz_url)){strtrim(diz_url, width = nchar(diz_url)-1)}else{diz_url}



# Table Descriptions and Codes --------------------------------------------
## Patient
tabledescription_patient <- fhir_table_description(
  resource = "Patient",
  cols = c(patient_identifier  = "id",
           #only gender (administrative), not sex available
           patient_gender      = "gender",
           patient_birthdate   = "birthDate"
  )
)
## Observation
tabledescription_observation <- fhir_table_description(
  resource = "Observation",
  cols = c(observation_identifier  = "id",
           observation_subject     = "subject/reference",
           observation_code        = "code/coding/code",
           observation_value       = "valueQuantity/value",
           observation_unit        = "valueQuantity/unit",
           observation_datetime    = "effectiveDateTime"
  )
)
## medicationAdministration
tabledescription_medicationAdministration <- fhir_table_description(
  resource = "MedicationAdministration",
  cols = c(medicationAdministration_identifier            = "id",
           medicationAdministration_subject               = "subject/reference", 
           medicationAdministration_status                = "status",
           medicationAdministration_medication_reference  = "medicationReference/reference",
           medicationAdministration_effective_dateTime    = "effectivedateTime",
           medicationAdministration_effective_period      = "effectivePeriod"
  )
)
## Medication
tabledescription_medication <- fhir_table_description(
  resource = "Medication",
  cols = c(medication_identifier      = "id",
           #Codingsystem auf bfarm/atc gesetzt, andere Systeme werden vorraussichtlich nicht erkannt; ggf iterativ einbauen, Frage in Zulip Chat stellen
           medication_system          = "code/coding[system[@value='http://fhir.de/CodeSystem/bfarm/atc']]/system",
           medication_code            = "code/coding[system[@value='http://fhir.de/CodeSystem/bfarm/atc']]/code",
           medication_display         = "code/coding[system[@value='http://fhir.de/CodeSystem/bfarm/atc']]/display",
           medication_text            = "code/text",
           medication_strength        = "ingredient/strength/numerator/value",
           medication_strength_per    = "ingredient/strength/denominator/value",
           medication_unit            = "ingredient/strength/numerator/unit"
  )
)
##Condition (Resource = Diagnosis)
tabledescription_condition <- fhir_table_description(
  resource = "Condition",
  cols = c(condition_identifier     = "id",
           condition_code           = "code/coding/code",
           condition_system         = "code/coding/system",
           condition_recordedDate   = "recordedDate",
           condition_onsetDate      = "onsetDateTime",
           condition_subject        = "subject/reference"
  )
)



## find patient IDs with relevant ICD-10 Codes for Condition 
# Define relevant ICD-codes for CVD Diagnoses                                               
icd10_codes_patient_conditions <- data.frame( icd_code = c("I05", "I06", "I07", "I08", "I09", 
                                                           "I20", "I21", "I22", "I23", "I24", "I25", 
                                                           "I30", "I31", "I32", "I33", "I34", "I35", 
                                                           "I36", "I37", "I38", "I39", "I40", "I41", 
                                                           "I42", "I43", "I44", "I45", "I46", "I47", 
                                                           "I48", "I49", "I50", "I51", "I52"))
icd10_codes_patient_conditions <- icd_expand(icd10_codes_patient_conditions, col_icd = "icd_code", year = 2023)


# Identify Required Patients
#download all conditions with respective ICD10-Codes
#use "code" as FHIR-Search parameter for Condition resource
body_patient_conditions <- fhir_body(content = list("code" = paste(icd10_codes_patient_conditions$icd_normcode, collapse = ",")))
request_patient_conditions <- fhir_url(url = diz_url, resource = "Condition")
bundles_patient_conditions <- fhir_search(request = request_patient_conditions, body = body_patient_conditions, max_bundles = bundle_limit, username = username, password = password)
# no saving necessary
table_patient_conditions <- fhir_crack(bundles = bundles_patient_conditions, design = tabledescription_condition, verbose = 1)

#search for patients who have the specified conditions
#remove "Patient/" prefix from referenced Patient IDs
patient_ids_with_conditions_prefix <- table_patient_conditions$condition_subject
patient_ids_with_conditions <- sub("Patient/", "", table_patient_conditions$condition_subject)


# Lists of relevant LOINC Codes for Observations
LOINC_codes_height <- c("8302-2", "3137-7", "8301-4", "8306-3", "91370-7")
LOINC_codes_weight <- c("29463-7", "3141-9", "3142-7", "8335-2", "75292-3", "79348-9", "8350-1")
LOINC_codes_bp_overall <- c("55284-4", "96607-7", "8478-0")
LOINC_codes_bp_sys <- c("8480-6", "8459-0", "76534-7", "8489-7", "11378-7", "8479-8")
LOINC_codes_bp_dia <- c("8462-4", "8453-3", "76213-8", "76535-4", "8469-9", "8475-6")
LOINC_codes_lvef <- c("10230-1", "18043-0", "8808-8", "8809-6", "18045-5", "8811-2", "8806-2", "79991-6")
LOINC_codes_creatinine <- c("14682-9", "2160-0", "38483-4", "77140-2")
LOINC_codes_egfr <- c("69405-9", "62238-1", "98979-8", "50210-4", "98980-6")
LOINC_codes_cholesterol_overall <- c("14647-2", "2093-3")
LOINC_codes_cholesterol_hdl <- c("14646-4", "2085-9", "49130-8", "18263-4")
LOINC_codes_hscrp <- c("71426-1", "30522-7", "76486-0")
LOINC_codes_crp <- c("1988-5", "76485-2", "48421-2")
LOINC_codes_bmi <- c("39156-5", "89270-3")
LOINC_codes_all <- paste (c(LOINC_codes_height, LOINC_codes_weight, LOINC_codes_bp_overall, LOINC_codes_bp_sys, LOINC_codes_bp_dia, 
                            LOINC_codes_lvef, LOINC_codes_creatinine, LOINC_codes_egfr, LOINC_codes_cholesterol_overall, LOINC_codes_cholesterol_hdl,
                            LOINC_codes_hscrp, LOINC_codes_crp, LOINC_codes_bmi), collapse = ",")


# Required Codes for medicationAdministration / Medication
medications_betablockers <- c(codes <- c("C07AB04", "C07BB04", "C07CB04", "C07FB26", "C07AB03", "C07BB03", "C07CB03", "C07CB23", "C07CB53", "C07FX18", 
                                         "C07AB05", "S01ED02", "S01ED52", "C07AB07", "C07FX04", "C07FB07", "C07BB27", "C07BB07", "C09BX04", "C09BX02", 
                                         "C09BX05", "C07AB08", "C07BC08", "C07AB09", "C07AB02", "C07BB02", "C07BB22", "C07BB52", "C07CB02", "C07CB22", 
                                         "C07FB02", "C07FB13", "C07FB22", "C07FX03", "C07FX05", "C07AB12", "C07BB12", "C07FB12", "C09DX05", "C07AA19", 
                                         "C07EA19", "C07FX17", "C07FX19", "S01ED08", "C07AA15", "S01ED05", "S01ED55", "C07AA12", "C07BA12", "C07AA02", 
                                         "C07FX15", "C07CA02", "C07BA02", "C07AA03", "C07CA03", "C07EA03", "S01ED07", "C07AA05", "C07DA25", "C07CA05", 
                                         "C07FX01", "C07BA05", "C07EA05", "C07AA07", "C07FX02", "C07BA07", "C07AA06", "S01ED01", "C07DA26", "S01ED01", 
                                         "C07DA26", "S01ED51", "C07DA06", "S01ED62", "S01ED67", "S01ED66", "S01ED61", "S01ED68", "S01ED70", "C07BA06", 
                                         "S01ED63", "C07AG01", "C07CG01", "C07BG01", "C07AG02", "C07FX06", "C07BG02"))
#ACEi
medications_acei_arb <- c("C09AA07", "C09BA07", "C09BA27", "C09AA01", "C09BA01", "C09BA21", "C09AA08", "C09BA08", "C09BA82", "C09AA02", "C09BA02", "C09BA22", 
                          "C09BB02", "C09BB06", "C09AA09", "C09BA09", "C09BA29", "C09AA16", "C09AA03", "C09BB03", "C09BA03", "C09BA23", "C09AA13", "C09BA13", 
                          "C09BA33", "C09AA04", "C09BX01", "C09BX04", "C09BB04", "C09BX02", "C09BA04", "C09BA54", "C09AA06", "C09BA06", "C09BA26", "C09AA05", 
                          "C09BX03", "C09BB07", "C09BX05", "C09BA05", "C09BB05", "C09BA25", "C09BA55", "C09AA10", "C09BB10", "C09AA15", "C09BA15", "C09BA35",
                          #ARB
                          "C09CA09", "C09DA09", "C09CA06", "C09DX06", "C09DB07", "C09DA06", "C09DA26", "C10BX19", "C09CA02", "C09DA02", "C09DA22", "C09CA04", 
                          "C09DX07", "C09DB05", "C09DA04", "C09DA24", "C09CA01", "C09DB06", "C09DA01", "C09DA21", "C09CA08", "C09DX03", "C09DB02", "C09DA08", 
                          "C09DA28", "C09CA07", "C09DB04", "C09DA07", "C09DA27", "C09CA03", "C09DX01", "C09DX02", "C09DB01", "C09DA03", "C09DA23", "C09DB08", 
                          "C09DX05", "C09DX04", "C10BX10")

medications_antithrombotic <- c("B01AA01", "B01AA02", "B01AA03", "B01AA04", "B01AA05", "B01AA06", "B01AA07", "B01AA08", "B01AA09", "B01AA10", "B01AA11", "B01AA12", 
                                "B01AB01", "B01AB02", "B01AB03", "B01AB04", "B01AB05", "B01AB06", "B01AB07", "B01AB08", "B01AB09", "B01AB10", "B01AB11", "B01AB12", 
                                "B01AB13", "B01AB51", "B01AB63", "B01AC01", "B01AC02", "B01AC03", "B01AC04", "B01AC05", "B01AC06", "B01AC07", "B01AC08", "B01AC09", 
                                "B01AC10", "B01AC11", "B01AC12", "B01AC13", "B01AC15", "B01AC16", "B01AC17", "B01AC18", "B01AC19", "B01AC21", "B01AC22", "B01AC23", 
                                "B01AC24", "B01AC25", "B01AC26", "B01AC27", "B01AC30", "B01AC34", "B01AC36", "B01AC56", "B01AC86", "B01AD01", "B01AD02", "B01AD03", 
                                "B01AD04", "B01AD05", "B01AD06", "B01AD07", "B01AD08", "B01AD09", "B01AD10", "B01AD11", "B01AD12", "B01AD51", "B01AE01", "B01AE02", 
                                "B01AE03", "B01AE04", "B01AE05", "B01AE06", "B01AE07", "B01AF01", "B01AF02", "B01AF03", "B01AF04", "B01AX01", "B01AX04", "B01AX05", 
                                "B01AX07", "B01AX11", "B01AY01", "B01AY02")
medications_all <- paste(c(medications_betablockers, medications_acei_arb, medications_antithrombotic), collapse = ",")


#give out statements after certain chunks to document progress
write(paste("Finished Setup at", Sys.time(), "\n"), file = log, append = T)


# FHIR Searches -----------------------------------------------------------
# (only for first download, then load saved bundles to save time)

# Patients
#create the search body which lists all the found Patient IDs and restricts on specified parameters (birthdate)
#use "_id" as global FHIR-Search parameter in patient resource
body_patient <- fhir_body(content = list("_id" = paste(patient_ids_with_conditions, collapse = ","), "birthdate" = "lt2006-07-01"))
#create request for specified URL and Resource
request_patients <- fhir_url(url = diz_url, resource = "Patient")
#Execute the fhir search using the above defined request and body
bundles_patient <- fhir_search(request = request_patients, body = body_patient, max_bundles = bundle_limit, username = username, password = password)
#give out statements after certain chunks to document progress
write(paste("Finished Search for Patient-Ressources at", Sys.time(), "\n"), file = log, append = T)
write(paste(length(bundles_patient), " Bundles for the Patient-Ressource were found \n"), file = log, append = T)


#Condition
#now load all CONDITIONS for relevant patient IDs, to obtain other conditions (comorbidities) of relevant patients
#use "patient" as FHIR-search parameter in Condition resource
body_conditions <- fhir_body(content = list("subject" = paste(patient_ids_with_conditions, collapse = ",")))
request_conditions <- fhir_url(url = diz_url, resource = "Condition")
#code or normcode?; normcode appears to work
bundles_condition <- fhir_search(request = request_conditions, body = body_conditions, max_bundles = bundle_limit, username = username, password = password)
#give out statements after certain chunks to document progress
write("Finished Search for Condition-Ressources at", Sys.time(), "\n", file = log, append = T)
write(paste(length(bundles_condition), " Bundles for the Condition-Ressource were found \n"), file = log, append = T)


# Observation
#use "subject" as FHIR search parameter for Observation resource
body_observation <- fhir_body(content = list("subject" = paste(patient_ids_with_conditions, collapse = ","), "code" = LOINC_codes_all))
request_observations <- fhir_url(url = diz_url, resource = "Observation")
bundles_observation <- fhir_search(request = request_observations, body = body_observation, max_bundles = bundle_limit, username = username, password = password)
#give out statements after certain chunks to document progress
write(paste("Finished Search for Observation-Ressources at", Sys.time(), "\n"), file = log, append = T)
write(paste(length(bundles_observation), " Bundles for the Observation-Ressource were found \n"), file = log, append = T)


# medicationAdministration
#use "subject" as FHIR-Search parameter in medicationAdministration resource

#1. search for all medicationAdministrations of the patients
body_medicationAdministration <- fhir_body(content = list("subject" = paste(patient_ids_with_conditions, collapse = ",")))
request_medicationAdministrations <- fhir_url(url = diz_url, resource = "MedicationAdministration")
bundles_medicationAdministration <- fhir_search(request = request_medicationAdministrations, body = body_medicationAdministration, max_bundles = bundle_limit, username = username, password = password)
#give out statements after certain chunks to document progress
write(paste("Finished Search for MedicationAdministration-Ressources at", Sys.time(), "\n"), file = log, append = T)
write(paste(length(bundles_medicationAdministration), " Bundles for the MedicationAdministration-Ressource were found \n"), file = log, append = T)
#save for later loading, and to check for entries
fhir_save(bundles = bundles_medicationAdministration, directory = "XML_Bundles/bundles_medicationAdministration")

#crack immediately to provide ids for medication-search
if(check_fhir_bundles_in_folder("XML_Bundles/bundles_medicationAdministration") == FALSE | is_fhir_bundle_empty("XML_Bundles/bundles_medicationAdministration") == FALSE) {
  message("The bundle you are trying to crack is empty. This will result in an error. Therefore the bundle will not be cracked.")
  #create empty list of medications in the medicationAdministrations of the Patients to fill in next step
  medicationAdministration_ids <- NA
  table_medicationAdministrations <- data.frame(medicationAdministration_identifier            = character(),
                                                medicationAdministration_subject               = character(), 
                                                medicationAdministration_status                = character(),
                                                medicationAdministration_medication_reference  = character(),
                                                medicationAdministration_effective_dateTime    = character(),
                                                medicationAdministration_effective_period      = character(),
                                                stringsAsFactors = FALSE)

} else {
  message("Cracking ", length(bundles_medicationAdministration), " medicationAdministration Bundles.\n")
  table_medicationAdministrations <- fhir_crack(bundles = bundles_medicationAdministration, design = tabledescription_medicationAdministration, verbose = 1)
  #create list of medication_ids that are referenced in the medicationAdministrations of the Patients
  medicationAdministration_ids <- sub("Medication/", "", table_medicationAdministrations$medicationAdministration_medication_reference)
  #give out statements after certain chunks to document progress
  write(paste("Cracked Table for MedicationAdministration-Ressources at", Sys.time(), "\n"), file = log, append = T)
  write(paste(nrow(table_medicationAdministrations), " Elements were created for MedicationAdministration \n"), file = log, append = T)
}


#2. search for all medications from the identified medication administrations
# Medication
body_medication <- fhir_body(content = list("_id" = paste(medicationAdministration_ids, collapse = ",")))
request_medications <- fhir_url(url = diz_url, resource = "Medication")
bundles_medication <- fhir_search(request = request_medications, body = body_medication, max_bundles = bundle_limit, username = username, password = password)
#save bundles to allow check for data
fhir_save(bundles = bundles_medication, directory = "XML_Bundles/bundles_medication")
#check data availability and crack bundles to extract medication_ids
if(check_fhir_bundles_in_folder("XML_Bundles/bundles_medication") == FALSE | is_fhir_bundle_empty("XML_Bundles/bundles_medicationAdministration") == FALSE) {
  message("The bundle you are trying to crack is empty. This will result in an error. Therefore the bundle will not be cracked.")
  table_medications <- data.frame(medication_identifier      = character(),
                                  medication_system          = character(),
                                  medication_code            = character(),
                                  medication_display         = character(),
                                  medication_text            = character(),
                                  medication_strength        = character(),
                                  medication_strength_per    = character(),
                                  medication_unit            = character(),
                                  stringsAsFactors = FALSE)
} else {
  message("Cracking ", length(bundles_medication), " Medication Bundles.\n")
  table_medications <- fhir_crack(bundles = bundles_medication, design = tabledescription_medication, verbose = 1)
  write(paste(nrow(table_medications), " Elements were created for Medications \n"), file = log, append = T)
}

#give out statements after certain chunks to document progress
write(paste("Finished Search for Medication-Ressources at", Sys.time(), "\n"), file = log, append = T)
write(paste(length(bundles_medication), " Bundles for the Medication-Ressource were found \n"), file = log, append = T)


#3. combine tables and retain the medicationAdministrations with the relevant medications
#merge medication information with data in medicationAdministration
#restrict data used by implementing the relevant ATC codes here -> medications_all
if(check_fhir_bundles_in_folder("XML_Bundles/bundles_medicationAdministration") == FALSE) {
  message("One of the tables you are trying to merge does not exist (Possibly due to empty resources). Therefore the merge-statement will not be carried out.")
} else {
  #combine medication statement with the respective medications
  table_meds <- merge(table_medicationAdministrations, table_medications, by.x = "medicationAdministration_medication_reference", by.y = "medication_identifier", all.x = TRUE)
  #remove medicationAdministrations that do not concern relevant medicaitons
  table_meds <- table_meds[table_meds$medication_code %in% medications_all,]
}


#old
# body_medicationAdministration <- fhir_body(content = list("subject" = paste(patient_ids_with_conditions, collapse = ","), "medication" = medications_all))
# 
# request_medicationAdministrations <- fhir_url(url = diz_url, resource = "MedicationAdministration")
# bundles_medicationAdministration <- fhir_search(request = request_medicationAdministrations, body = body_medicationAdministration, max_bundles = bundle_limit, username = username, password = password)
# #give out statements after certain chunks to document progress
# write(paste("Finished Search for MedicationAdministration-Ressources at", Sys.time(), "\n"), file = log, append = T)
# write(paste(length(bundles_medicationAdministration), " Bundles for the MedicationAdministration-Ressource were found \n"), file = log, append = T)
# 
# #save for later loading, and to check for entries
# fhir_save(bundles = bundles_medicationAdministration, directory = "XML_Bundles/bundles_medicationAdministration")
# #crack immediately to provide ids for medication-search
# 
# if(check_fhir_bundles_in_folder("XML_Bundles/bundles_medicationAdministration") == FALSE) {
#   message("The bundle you are trying to crack is empty. This will result in an error. Therefore the bundle will not be cracked.")
#   #create emppty list of medications in the medicationAdministrations of the Patients to fill in next step
#   medicationAdministration_ids <- NA
# } else {
#     message("Cracking ", length(bundles_medicationAdministration), " medicationAdministration Bundles.\n")
#     table_medicationAdministrations <- fhir_crack(bundles = bundles_medicationAdministration, design = tabledescription_medicationAdministration, verbose = 1)
#     #create list of medications in the medicationAdministrations of the Patients
#     medicationAdministration_ids <- sub("Medication/", "", table_medicationAdministrations$medicationAdministration_medication_reference)
#     #give out statements after certain chunks to document progress
#     write(paste("Cracked Table for MedicationAdministration-Ressources at", Sys.time(), "\n"), file = log, append = T)
#     write(paste(nrow(table_medicationAdministrations), " Elements were created for MedicationAdministration \n"), file = log, append = T)
# }
# 



#(Modul Fall für Einrichtungskontakt: nicht möglich, da Abteilungsschlüssel nur in Beschreibung aber nicht in FHIR-Profil hinterlegt ist)


# Save Bundles ------------------------------------------------------------
# (only after first download) move to FHIR Search section (so far only medicationAdministration)
#save and load to circumvent long download times for bundles; comment and uncomment with line above (fhir_search) as necessary
message("Saving  Bundles.\n")
fhir_save(bundles = bundles_patient, directory = "XML_Bundles/bundles_patient")
fhir_save(bundles = bundles_condition, directory = "XML_Bundles/bundles_condition")
fhir_save(bundles = bundles_observation, directory = "XML_Bundles/bundles_observation")

#give out statements after certain chunks to document progress
write(paste("Saved Bundles at ", Sys.time(), "\n"), file = log, append = T)

# Load Bundles ------------------------------------------------------------
# (after bundles are saved)
message("Loading saved Bundles.\n")
bundles_patient <- fhir_load(directory = "XML_Bundles/bundles_patient")
bundles_condition <- fhir_load(directory = "XML_Bundles/bundles_condition")
bundles_observation <- fhir_load(directory = "XML_Bundles/bundles_observation")
bundles_medication <- fhir_load(directory = "XML_Bundles/bundles_medication")
bundles_medicationAdministration <- fhir_load(directory = "XML_Bundles/bundles_medicationAdministration")
#give out statements after certain chunks to document progress
write(paste("Loaded Bundles at", Sys.time(), "\n"), file = log, append = T)

# Crack Into Tables -------------------------------------------------------
#crack bundles into table

if(check_fhir_bundles_in_folder("XML_Bundles/bundles_patient") == FALSE) {
  message("The bundle you are trying to crack is empty. This will result in an error. Therefore the bundle will not be cracked.")
} else {
message("Cracking ", length(bundles_patient), " Patient Bundles.\n")
table_patients <- fhir_crack(bundles = bundles_patient, design = tabledescription_patient, verbose = 1)
write(paste(nrow(table_patients), " Elements were created for Patients \n"), file = log, append = T)
  }

if(check_fhir_bundles_in_folder("XML_Bundles/bundles_condition") == FALSE) {
  message("The bundle you are trying to crack is empty. This will result in an error. Therefore the bundle will not be cracked.")
} else {
message("Cracking ", length(bundles_condition), " Condition Bundles.\n")
table_conditions <- fhir_crack(bundles = bundles_condition, design = tabledescription_condition, verbose = 1)
write(paste(nrow(table_conditions), " Elements were created for Conditions \n"), file = log, append = T)
}

if(check_fhir_bundles_in_folder("XML_Bundles/bundles_observation") == FALSE) {
  message("The bundle you are trying to crack is empty. This will result in an error. Therefore the bundle will not be cracked.")
} else {
message("Cracking ", length(bundles_observation), " Observation Bundles.\n")
table_observations <- fhir_crack(bundles = bundles_observation, design = tabledescription_observation, verbose = 1)
write(paste(nrow(table_observations), " Elements were created for Observations \n"), file = log, append = T)
}


if(length(table_patients$patient_identifier)==0){
  write("Es konnten keine Patienten mit den angegebene ICD-10 Codes auf dem Server gefunden werden. Abfrage abgebrochen.", file ="errors/error_message.txt")
  stop("No Patients found - aborting.")
}

#give out statements after certain chunks to document progress
write(paste("Bundles were cracked into tables at", Sys.time(), "\n"), file = log, append = T)


# Data Cleaning -----------------------------------------------------------
message("Cleaning the Data.\n")

#convert birthday to birthyear and calculate age
#fhircracking-process makes all varibales into character-variables, year should always be given first (according to Implementation Guide/FHIR), first four characters can be extracted for birthyear
if(check_fhir_bundles_in_folder("XML_Bundles/bundles_patient") == FALSE) {
  message("The action you trying to carry out is not possible due to empty resources. Executing the action would result in an error. Therefore the action will not be carried out.")
} else {
#apply function to date coulumn
table_patients$patient_birthdate <- sapply(table_patients$patient_birthdate, convert_date_to_year)
#rename column for clarity
colnames(table_patients)[colnames(table_patients) == "patient_birthdate"] <- "patient_birthyear"
#calculate age
current_year <- as.numeric(format(Sys.Date(), "%Y"))
table_patients$patient_age <- current_year - table_patients$patient_birthyear
  }

if(check_fhir_bundles_in_folder("XML_Bundles/bundles_observation") == FALSE | check_fhir_bundles_in_folder("XML_Bundles/bundles_condition") == FALSE) {
  message("The action you trying to carry out is not possible due to empty resources. Executing the action would result in an error. Therefore the action will not be carried out.")
} else {
#values must be changed to numeric to show distribution
table_observations$observation_value_num <- as.numeric(table_observations$observation_value)

#change character columns for date to datetime
table_conditions$condition_recordedDate <- anytime(table_conditions$condition_recordedDate)
table_conditions$condition_onsetDate <- ymd_hms(table_conditions$condition_onsetDate, tz = "UTC")
table_observations$observation_datetime <- ymd_hms(table_observations$observation_datetime, tz = "UTC")

#calculate time since onset for all conditions 
table_conditions$time_since_first_diagnosis_using_recordeddate <- difftime(Sys.time(), table_conditions$condition_recordedDate, units = "days")
table_conditions$time_since_first_diagnosis_using_onsetdate <- difftime(Sys.time(), table_conditions$condition_onsetDate, units = "days")
#calculate average time since diagnosis for each condition (selecting average time for first HKE diagnosis possible) (I05-I09, I20-I25, I30-I52)
time_since_first_diagnosis_recorded <- table_conditions %>%
  group_by(table_conditions$condition_code) %>%
  summarise(average_time_since_first_diagnosis = mean(time_since_first_diagnosis_using_recordeddate, na.rm = TRUE))
time_since_first_diagnosis_onset <- table_conditions %>%
  group_by(table_conditions$condition_code) %>%
  summarise(average_time_since_first_diagnosis = mean(time_since_first_diagnosis_using_onsetdate, na.rm = TRUE))


#import table with LOINC Code for reference, send CSV with Script, change path to be universally applicable
loinc_codes <- read.csv("Loinc_2.78/LoincTable/Loinc.csv")
#add content of LOINC codes to observation table
table_observations <-  merge(table_observations, loinc_codes[, c("LOINC_NUM", "COMPONENT")], by.x = "observation_code", by.y = "LOINC_NUM", all.x = TRUE)
# Rename column COMPONENT to observation_LOINC_term
colnames(table_observations)[colnames(table_observations) == "COMPONENT"] <- "observation_LOINC_term"
}


#remove "Patient/" prefix from subject-column to allow merging of tables, same for medication if necessary
table_conditions$condition_subject <- sub("Patient/", "", table_conditions$condition_subject) 
table_observations$observation_subject <- sub("Patient/", "", table_observations$observation_subject)
table_medicationAdministrations$medicationAdministration_subject <- sub("Patient/", "", table_medicationAdministrations$medicationAdministration_subject) 
table_medicationAdministrations$medicationAdministration_medication_reference <- sub("Medication/", "", table_medicationAdministrations$medicationAdministration_medication_reference)


#give out statements after certain chunks to document progress
write(paste("Data Cleaning was finished at", Sys.time(), "\n"), file = log, append = T)

# Additional columns for analysis  ----------------------------------------------------------
#column with time since first CVD Diagnosis for each patient per patient
#calculate time since first Cardiovascular Diagnosis (I05-I09, I20-I25, I30-I52)
#for recordedDate (mandatory)
table_conditions %>%
  filter(condition_code %in% icd10_codes_patient_conditions) %>%
  group_by(condition_subject) %>%
  mutate(condition_first_diagnosis_date = min(condition_recordedDate)) %>%
  ungroup() %>%
  mutate(condition_time_since_first_cvd_record = as.numeric(difftime(Sys.Date(), condition_first_diagnosis_date, units = "days")))
#should work if data is available, otherwise warning
#same for onsetDate if available (optional)
table_conditions %>%
  filter(condition_code %in% icd10_codes_patient_conditions) %>%
  group_by(condition_subject) %>%
  mutate(condition_first_diagnosis_date = min(condition_onsetDate)) %>%
  ungroup() %>%
  mutate(condition_time_since_first_cvd_onset = as.numeric(difftime(Sys.Date(), condition_first_diagnosis_date, units = "days")))
#should work if data is available, otherwise warning


#create vectors to check eligibility
### Create Tables for Observation (not Patients) with respective Score criteria 
#shorten ICD-10 code to simplify operations (only first three characters are needed)
table_conditions$condition_code_short <- substr(table_conditions$condition_code,1,3)

## CHA2DS2VASc
# age > 18, Atrial fibrillation (previous 12 months), "non-valvular AF" (ICD-10 Code?)
chadsvasc_inclusion_icd_codes <- data.frame(icd_code = c("I48"))
chadsvasc_inclusion_icd_codes <- icd_expand(chadsvasc_inclusion_icd_codes, col_icd = "icd_code", year = 2023)

## SMART2
# 40 < age < 80, CHD, CeVD, I06-I09, I20-I25, I70, I71, I73-I79
smart_inclusion_icd_codes <- data.frame(icd_code = c("I06", "I07", "I08", "I09", "I20", "I21", "I22", "I23", "I24", "I25", "I70", "I71", "I73", "I74", "I77", "I78", "I79"))
smart_inclusion_icd_codes <- icd_expand(smart_inclusion_icd_codes, col_icd = "icd_code", year = 2023)

## MAGGIC
# age > 18 years, chronic HF (I50)
maggic_inclusion_icd_codes <- data.frame(icd_code = c("I50"))
maggic_inclusion_icd_codes <- icd_expand(maggic_inclusion_icd_codes, col_icd = "icd_code", year = 2023)

## CHARGE-AF
#46 < age < 94, creatinine < 2mg/dl (14682-9, 2160-0 (38483-4, 77140-2)), no I48
# chargeaf_exclusion_icd_codes <- chargeaf_exclusion_icd_codes <- data.frame(icd_code = c("I48"))
# chargeaf_exclusion_icd_codes <- icd_expand(chargeaf_exclusion_icd_codes, col_icd = "icd_code", year = 2023)
# --> not necessary as it is only one code which is checked in ifelse statement below

#define loinc codes for which to check the value (creatinine)
charge_check_loinc_codes <- c("14682-9", "2160-0", "38483-4", "77140-2")


#eligibility column in each resource table for each score per patient

#CHADSVASC
#18years or older
table_patients$eligible_patient_chadsvasc <- ifelse(table_patients$patient_age >= 18, 1, 0)
#specified conditions of atrial fibrillation
table_conditions$eligible_conditions_chadsvasc <- ifelse(table_conditions$condition_code %in% chadsvasc_inclusion_icd_codes$icd_normcode, 1, 0)
#no eligibility criteria regarding observations for chadsvasc
table_observations$eligible_observations_chadsvasc <- 1
#no eligibility criteria regarding observations for chadsvasc
table_meds$eligible_meds_chadsvasc <- if(nrow(table_meds) == 0) {
  table_meds$eligible_meds_chadsvasc <- numeric(0)
} else {
  table_meds$eligible_meds_chadsvasc <- 1
  }

#SMART
#between 40 and 80 xears old (validated population)
table_patients$eligible_patient_smart <- ifelse(table_patients$patient_age >= 40 & table_patients$patient_age <= 80, 1, 0)
#specified conditions of cardiovascular disease
table_conditions$eligible_conditions_smart <- ifelse(table_conditions$condition_code %in% smart_inclusion_icd_codes$icd_normcode, 1, 0)
#no eligibility criteria regarding observations for smart
table_observations$eligible_observations_smart <- 1
#no eligibility criteria regarding observations for smart
if(nrow(table_meds) == 0) {
  table_meds$eligible_meds_smart <- numeric(0)
} else {
    table_meds$eligible_meds_smart <- 1
  }


#MAGGIC
#18years or older
table_patients$eligible_patient_maggic <- ifelse(table_patients$patient_age >= 18, 1, 0)
#specified conditions of heart failure
table_conditions$eligible_conditions_maggic <- ifelse(table_conditions$condition_code %in% maggic_inclusion_icd_codes$icd_normcode, 1, 0)
#no eligibility criteria regarding observations for maggic
table_observations$eligible_observations_maggic <- 1
#no eligibility criteria regarding medications for maggic
if(nrow(table_meds) == 0) {
  table_meds$eligible_meds_maggic <- numeric(0)
} else {
  table_meds$eligible_meds_maggic <- 1
  }

#CHARGE-AF
#between 46 and 94 years
table_patients$eligible_patient_charge <- ifelse(table_patients$patient_age >= 46 & table_patients$patient_age <= 94, 1, 0) 
#specified conditions of no prior atrial fibrillation
table_conditions$eligible_conditions_charge <- ifelse(table_conditions$condition_code_short != "I48", 1, 0)
#creatinine value below 2, valus in ifelse statement reversed as this is an exclusion criterion                                   
#creat case when for combinations of units and values                                        moles per volume, presumably micromole per Litre; converted from mg/dL
table_observations$eligible_observations_charge <- case_when( table_observations$observation_code == "14682-9" & table_observations$observation_value_num > 177 ~ 0,
                                                                                                                              #mass per volume, presumably mg/dL
                                                             table_observations$observation_code == "2160-0" & table_observations$observation_value_num > 2 ~ 0,
                                                                                                                               #mass per volume, presumably mg/dL
                                                             table_observations$observation_code == "38483-4" & table_observations$observation_value_num > 2 ~ 0,
                                                                                           #moles per volume, presumably micromole per Litre; converted from mg/dL
                                                             table_observations$observation_code == "14682-9" & table_observations$observation_value_num > 177 ~ 0,
                                                             
                                                             TRUE ~ 1)
#no eligibility criteria regarding medications for charge
if(nrow(table_meds) == 0) {
  table_meds$eligible_meds_charge <- numeric(0)
} else {
  table_meds$eligible_meds_charge <- 1
  }


#create tables with selected columns for merge
table_conditions_merge <- table_conditions[, c("condition_subject", "eligible_conditions_chadsvasc", "eligible_conditions_smart", "eligible_conditions_maggic", "eligible_conditions_charge")]
table_observations_merge <- table_observations[, c("observation_subject", "eligible_observations_chadsvasc", "eligible_observations_smart", "eligible_observations_maggic", "eligible_observations_charge")]
table_meds_merge <- table_meds[, c("medicationAdministration_subject", "eligible_meds_chadsvasc", "eligible_meds_smart", "eligible_meds_maggic", "eligible_meds_charge")]

#reduce tables to 1 entry per patient, if any of the rows have a 0 (ineligible), the whole patient becomes ineligible (exclusion criterion)
table_conditions_merge <- aggregate(. ~ condition_subject, data = table_conditions_merge, FUN = function(x) ifelse(any(x == 0), 0, 1))
table_observations_merge <- aggregate(. ~ observation_subject, data = table_observations_merge, FUN = function(x) ifelse(any(x == 0), 0, 1))
if (nrow(tables_meds_merge) > 0) {table_meds_merge <- aggregate(. ~ medicationAdministration_subject, data = table_meds_merge, FUN = function(x) ifelse(any(x == 0), 0, 1))}

#test to merge eligibility columns into new table with patients
table_eligibility <- table_patients
table_eligibility <- merge(table_eligibility, table_conditions_merge, by.x = "patient_identifier", by.y = "condition_subject", all.x = TRUE)
table_eligibility <- merge(table_eligibility, table_observations_merge, by.x = "patient_identifier", by.y = "observation_subject", all.x = TRUE)
table_eligibility <- merge(table_eligibility, table_meds_merge, by.x = "patient_identifier", by.y = "medicationAdministration_subject", all.x = TRUE)

#hier alle Einträge die nicht 0 sind auf 1 setzen, da wenn medication nich vorhanden sind, davon ausgegangen werden muss, dass sie nicht verabreicht werden
if (nrow(tables_meds_merge) > 0) {table_eligibility$eligible_meds_chadsvasc <- if(is.na(table_eligibility$eligible_meds_chadsvasc)){table_eligibility$eligible_meds_chadsvasc <- 1}}  
if (nrow(tables_meds_merge) > 0) {table_eligibility$eligible_meds_smart <- if(is.na(table_eligibility$eligible_meds_smart)){table_eligibility$eligible_meds_smart <- 1}}
if (nrow(tables_meds_merge) > 0) {table_eligibility$eligible_meds_maggic <- if(is.na(table_eligibility$eligible_meds_maggic)){table_eligibility$eligible_meds_maggic <- 1}}
if (nrow(tables_meds_merge) > 0) {table_eligibility$eligible_meds_charge <- if(is.na(table_eligibility$eligible_meds_charge)){table_eligibility$eligible_meds_charge <- 1}}


# #take into account the possibility, that certain columns do no exist, if data is unavailable (eg medication)
eligibility_required_columns_chadsvasc <- c("eligible_patient_chadsvasc", "eligible_conditions_chadsvasc", "eligible_observations_chadsvasc", "eligible_meds_chadsvasc")
eligibility_available_columns_chadsvasc <- eligibility_required_columns_chadsvasc[eligibility_required_columns_chadsvasc %in% colnames(table_eligibility)]
eligibility_required_columns_smart <- c("eligible_patient_smart", "eligible_conditions_smart", "eligible_observations_smart", "eligible_meds_smart")
eligibility_available_columns_smart <- eligibility_required_columns_smart[eligibility_required_columns_smart %in% colnames(table_eligibility)]
eligibility_required_columns_maggic <- c("eligible_patient_maggic", "eligible_conditions_maggic", "eligible_observations_maggic", "eligible_meds_maggic")
eligibility_available_columns_maggic <- eligibility_required_columns_maggic[eligibility_required_columns_maggic %in% colnames(table_eligibility)]
eligibility_required_columns_charge <- c("eligible_patient_charge", "eligible_conditions_charge", "eligible_observations_charge", "eligible_meds_charge")
eligibility_available_columns_charge <- eligibility_required_columns_charge[eligibility_required_columns_charge %in% colnames(table_eligibility)]

#create summary column for eligibility (if any 0, then 0; if no 0s but any NAs, then NA, if no 0s or NAs then 1)
#only consider columns for this score, that are available
table_eligibility$eligible_chadsvasc_overall <- apply(table_eligibility[,eligibility_available_columns_chadsvasc], 1, function(x) ifelse(any(x == 0), 0, ifelse(any(is.na(x)), NA, 1)))
table_eligibility$eligible_smart_overall <- apply(table_eligibility[,eligibility_available_columns_smart], 1, function(x) ifelse(any(x == 0), 0, ifelse(any(is.na(x)), NA, 1)))
table_eligibility$eligible_maggic_overall <- apply(table_eligibility[,eligibility_available_columns_maggic], 1, function(x) ifelse(any(x == 0), 0, ifelse(any(is.na(x)), NA, 1)))
table_eligibility$eligible_charge_overall <- apply(table_eligibility[,eligibility_available_columns_charge], 1, function(x) ifelse(any(x == 0), 0, ifelse(any(is.na(x)), NA, 1)))

#sex and age are required from patient table
table_patients$can_calc_patient_chadsvasc <- ifelse(!is.na(table_patients$patient_age) & !is.na(table_patients$patient_gender), 1, 0)
table_patients$can_calc_patient_smart <- ifelse(!is.na(table_patients$patient_age) & !is.na(table_patients$patient_gender), 1, 0)
table_patients$can_calc_patient_maggic <- ifelse(!is.na(table_patients$patient_age) & !is.na(table_patients$patient_gender), 1, 0)
table_patients$can_calc_patient_charge <- ifelse(!is.na(table_patients$patient_age) & !is.na(table_patients$patient_gender), 1, 0)
#can_calc, alle necessary observations are available; if patient does not have conditions/medications they are (correctly) missing

# are required data available from observations table
#group by patient to assess all corresponding observations, if any combination of the observations pertains to required values, the score can be calculated
table_observations <- table_observations %>%
  group_by(observation_subject) %>%
  mutate(can_calc_observations_chadsvasc = 1) %>%
  ungroup()
table_observations <- table_observations %>%
  group_by(observation_subject) %>%
  mutate(can_calc_observations_smart = ifelse((any(observation_code %in% LOINC_codes_cholesterol_hdl | observation_code %in% LOINC_codes_cholesterol_overall)) & any(table_observations$observation_code %in% LOINC_codes_bp_sys), 1, 0)) %>%
  ungroup()
table_observations <- table_observations %>%
  group_by(observation_subject) %>%
  mutate(can_calc_observations_maggic = ifelse((any(observation_code %in% LOINC_codes_bp_sys & observation_code %in% LOINC_codes_lvef & observation_code %in% LOINC_codes_creatinine)), 1, 0)) %>%
  ungroup()
table_observations <- table_observations %>%
  group_by(observation_subject) %>%
  mutate(can_calc_observations_charge = ifelse((any(observation_code %in% LOINC_codes_bmi) | (any(observation_code %in% LOINC_codes_height) & any(observation_code %in% LOINC_codes_weight))), 1, 0)) %>%
  ungroup()

#conditions and medications are presumed to be not present in the patient if not available in data just give value of 1
table_conditions$can_calc_conditions_chadsvasc <- 1
table_conditions$can_calc_conditions_smart <- 1
table_conditions$can_calc_conditions_maggic <- 1
table_conditions$can_calc_conditions_charge <- 1

#accomodaet empty medication tables
if(nrow(table_meds) == 0) {
  table_meds$can_calc_meds_chadsvasc <- numeric(0)
  table_meds$can_calc_meds_smart <- numeric(0)
  table_meds$can_calc_meds_maggic <- numeric(0)
  table_meds$can_calc_meds_charge <- numeric(0)
} else {
  table_meds$can_calc_meds_chadsvasc <- 1
  table_meds$can_calc_meds_smart <- 1
  table_meds$can_calc_meds_maggic <- 1
  table_meds$can_calc_meds_charge <- 1
}


#create tables with selected columns for merge
table_conditions_merge <- table_conditions[, c("condition_subject", "can_calc_conditions_chadsvasc", "can_calc_conditions_smart", "can_calc_conditions_maggic", "can_calc_conditions_charge")]
table_observations_merge <- table_observations[, c("observation_subject", "can_calc_observations_chadsvasc", "can_calc_observations_smart", "can_calc_observations_maggic", "can_calc_observations_charge")]
table_meds_merge <- table_meds[, c("medicationAdministration_subject", "can_calc_meds_chadsvasc", "can_calc_meds_smart", "can_calc_meds_maggic", "can_calc_meds_charge")]

#reduce tables to 1 entry per patient, if any of the rows have a 0 (ineligible), the whole patient becomes ineligible (exclusion cirterion)
table_conditions_merge <- aggregate(. ~ condition_subject, data = table_conditions_merge, FUN = function(x) ifelse(any(x == 0), 0, 1))
table_observations_merge <- aggregate(. ~ observation_subject, data = table_observations_merge, FUN = function(x) ifelse(any(x == 0), 0, 1))
if (nrow(tables_meds_merge) > 0) {table_meds_merge <- aggregate(. ~ medicationAdministration_subject, data = table_meds_merge, FUN = function(x) ifelse(any(x == 0), 0, 1))}

#merge columns to new table can_calc, overall calculable: 0 if any 0s exist, NA if any NAs exist, 1 if all columns are 1
#remove unwanted columns and set up new table
table_can_calc <- subset(table_patients, select = -c(eligible_patient_chadsvasc, eligible_patient_smart, eligible_patient_maggic, eligible_patient_charge))
table_can_calc <- merge(table_can_calc, table_conditions_merge, by.x = "patient_identifier", by.y = "condition_subject", all.x = TRUE)
table_can_calc <- merge(table_can_calc, table_observations_merge, by.x = "patient_identifier", by.y = "observation_subject", all.x = TRUE)
table_can_calc <- merge(table_can_calc, table_meds_merge, by.x = "patient_identifier", by.y = "medicationAdministration_subject", all.x = TRUE)

# ability of calculating scores (all parameters that need to be available, are available), absence of parameters is interpreted as not present in patient
can_calc_required_columns_chadsvasc <- c("can_calc_patient_chadsvasc", "can_calc_conditions_chadsvasc", "can_calc_observations_chadsvasc", "can_calc_meds_chadsvasc")
can_calc_available_columns_chadsvasc <- can_calc_required_columns_chadsvasc[can_calc_required_columns_chadsvasc %in% colnames(table_can_calc)]
can_calc_required_columns_smart <- c("can_calc_patient_smart", "can_calc_conditions_smart", "can_calc_observations_smart", "can_calc_meds_smart")
can_calc_available_columns_smart <- can_calc_required_columns_smart[can_calc_required_columns_smart %in% colnames(table_can_calc)]
can_calc_required_columns_maggic <- c("can_calc_patient_maggic", "can_calc_conditions_maggic", "can_calc_observations_maggic", "can_calc_meds_maggic")
can_calc_available_columns_maggic <- can_calc_required_columns_maggic[can_calc_required_columns_maggic %in% colnames(table_can_calc)]
can_calc_required_columns_charge <- c("can_calc_patient_charge", "can_calc_conditions_charge", "can_calc_observations_charge", "can_calc_meds_charge")
can_calc_available_columns_charge <- can_calc_required_columns_charge[can_calc_required_columns_charge %in% colnames(table_can_calc)]

#create summary column for eligibility (if any 0, then 0; if no 0s but any NAs, then NA, if no 0s or NAs then 1)
table_can_calc$can_calc_chadsvasc_overall <- apply(table_can_calc[,can_calc_available_columns_chadsvasc], 1, function(x) ifelse(any(x == 0), 0, ifelse(any(is.na(x)), NA, 1)))
table_can_calc$can_calc_smart_overall <- apply(table_can_calc[,can_calc_available_columns_smart], 1, function(x) ifelse(any(x == 0), 0, ifelse(any(is.na(x)), NA, 1)))
table_can_calc$can_calc_maggic_overall <- apply(table_can_calc[,can_calc_available_columns_maggic], 1, function(x) ifelse(any(x == 0), 0, ifelse(any(is.na(x)), NA, 1)))
table_can_calc$can_calc_charge_overall <- apply(table_can_calc[,can_calc_available_columns_charge], 1, function(x) ifelse(any(x == 0), 0, ifelse(any(is.na(x)), NA, 1)))



# Feasibility Analysis ----------------------------------------------------
message("Analysing Data.\n")
## check availability of parameters 
#sum up all entries of NA in each of the columns 
navalues_patient_columns <- table_patients %>% summarise(across(everything(), ~ sum(is.na(.))))
navalues_condition_columns <- table_conditions %>% summarise(across(everything(), ~ sum(is.na(.))))
navalues_observation_columns <- table_observations %>% summarise(across(everything(), ~ sum(is.na(.))))
navalues_medication_columns <- table_meds %>% summarise(across(everything(), ~ sum(is.na(.))))

#count number of patients (navalues_all_columns counts data entries not patients) who have NA in condition code, observation code or medication code 
precentage_patients_with_no_code_condition <- table_conditions %>% filter(is.na(condition_code)) %>% summarise(condition_code_na = n_distinct(condition_subject)/length(unique(table_conditions$condition_subject)))
precentage_patients_with_no_code_observation <- table_observations %>% filter(is.na(observation_code)) %>% summarise(observation_code_na = n_distinct(observation_subject)/length(unique(table_observations$observation_subject))) 
precentage_patients_with_no_code_medication <- table_meds %>% filter(is.na(medication_code)) %>% summarise(medication_code_na = n_distinct(medicationAdministration_subject)/length(unique(table_meds$medicationAdministration_subject)))

## Check distribution of parameters ##########################################################################
#gives min, max, mean, median and n where applicable (discrete and continuous data)
desc_patient_age <- table_patients %>% summarise(min_age = min(patient_age), mean_age = mean(patient_age), median_age = median(patient_age), max_age = max(patient_age), n = n())
desc_patient_gender <- as.data.frame(table(table_patients$patient_gender))
#observation
desc_observation <- table_observations %>% filter(!is.na(observation_code)) %>% group_by(observation_code, observation_LOINC_term) %>% summarise(min = min(observation_value_num), mean = mean(observation_value_num), median = median (observation_value_num), max = max(observation_value_num), n=n())
#condition
desc_conditions <- table_conditions %>% filter(!is.na(condition_code)) %>% count(condition_code)
#medications
desc_medication <- table_meds %>% filter(!is.na(medication_code)) %>% count(medication_code)


#eligibility
eligibility_chadsvasc <- table(table_eligibility$eligible_chadsvasc_overall, useNA = "ifany")
eligibility_smart <- table(table_eligibility$eligible_smart_overall, useNA = "ifany")
eligibility_maggic <- table(table_eligibility$eligible_maggic_overall, useNA = "ifany")
eligibility_charge <- table(table_eligibility$eligible_charge_overall, useNA = "ifany")

#calculable
can_calc_chadsvasc <- table(table_can_calc$can_calc_chadsvasc_overall, useNA = "ifany")
can_calc_smart <- table(table_can_calc$can_calc_smart_overall, useNA = "ifany")
can_calc_maggic <- table(table_can_calc$can_calc_maggic_overall, useNA = "ifany")
can_calc_charge <- table(table_can_calc$can_calc_charge_overall, useNA = "ifany")


#cross table for eligibility and variables availability (can_calc) for each Score
#create combined table from eligibility and can_calc
table_eligibility_can_calc <- merge(table_eligibility, table_can_calc, by = "patient_identifier")
#create crosstabulations for combination of eligibility and can_calc for each score
crosstabs_eligibility_availability_chadsvasc <- table(table_eligibility_can_calc$eligible_chadsvasc_overall, table_eligibility_can_calc$can_calc_chadsvasc_overall, dnn = list("Eligible", "Calculable"))
crosstabs_eligibility_availability_smart <- table(table_eligibility_can_calc$eligible_smart_overall, table_eligibility_can_calc$can_calc_smart_overall, dnn = list("Eligible", "Calculable"))
crosstabs_eligibility_availability_maggic <- table(table_eligibility_can_calc$eligible_maggic_overall, table_eligibility_can_calc$can_calc_maggic_overall, dnn = list("Eligible", "Calculable"))
crosstabs_eligibility_availability_charge <- table(table_eligibility_can_calc$eligible_charge_overall, table_eligibility_can_calc$can_calc_charge_overall, dnn = list("Eligible", "Calculable"))

#Assumption: if Medications or Conditions are missing, the patient does not have them (sensitivity?) non-existence cannot be confirmed by routine data, correct?
# table_eligibility$any_score_eligible <- ifelse(table_eligibility$eligible_chadsvasc_overall == 1 | table_eligibility$eligible_smart_overall == 1 | table_eligibility$eligible_maggic_overall == 1 | table_eligibility$eligible_charge_overall == 1, 1, 0)
# table_can_calc$any_score_can_calc <- ifelse(table_can_calc$can_calc_chadsvasc_overall == 1 | table_can_calc$can_calc_smart_overall == 1 | table_can_calc$can_calc_maggic_overall == 1 | table_can_calc$can_calc_charge_overall == 1, 1, 0)
#alternative to prevent error
table_eligibility$any_score_eligible <- rowSums(table_eligibility[, c("eligible_chadsvasc_overall", "eligible_smart_overall", "eligible_maggic_overall", "eligible_charge_overall")], na.rm = TRUE) > 0
table_can_calc$any_score_can_calc <- rowSums(table_can_calc[, c("can_calc_chadsvasc_overall", "can_calc_smart_overall", "can_calc_maggic_overall", "can_calc_charge_overall")], na.rm = TRUE) > 0



#Percentage of patients who are eligible for at least 1 score
prob_eligibility_any_score <- prop.table(table(table_eligibility_can_calc$any_score_eligible))
#Percentage for which at least one score can be calculated
prob_can_calc_any_score <- prop.table(table(table_eligibility_can_calc$any_score_can_calc))

#bei Calc noch die Elig hinzufügen, da ja die Frage ist von wie vielen die infrage kommen, kann  der Score berechnet werden
crosstabs_eligibility_can_calc_any_score <- table(table_eligibility_can_calc$any_score_eligible, table_eligibility_can_calc$any_score_can_calc, dnn = list("Eligible", "Calculable"))


#Calculate percentage with NAs per Variable for eligible patients for each score
navalues_chadsvasc <- filter(table_eligibility, table_eligibility$eligible_chadsvasc_overall == 1) %>%
  group_by(patient_identifier) %>%
  summarise_all(~sum(is.na(.)))
navalues_chadsvasc <- colSums(navalues_chadsvasc[-1])

navalues_smart <- filter(table_eligibility, table_eligibility$eligible_smart_overall == 1) %>%
  group_by(patient_identifier) %>%
  summarise_all(~sum(is.na(.)))
navalues_smart <- colSums(navalues_smart[-1])

navalues_maggic <- filter(table_eligibility, table_eligibility$eligible_maggic_overall == 1) %>%
  group_by(patient_identifier) %>%
  summarise_all(~sum(is.na(.)))
navalues_maggic <- colSums(navalues_maggic[-1])

navalues_charge <- filter(table_eligibility, table_eligibility$eligible_charge_overall == 1) %>%
  group_by(patient_identifier) %>%
  summarise_all(~sum(is.na(.)))
navalues_charge <- colSums(navalues_charge[-1])


#give out statements after certain chunks to document progress
write(paste("Analysis Steps were finished at", Sys.time(), "\n"), file = log, append = T)


# Data Export -------------------------------------------------------------
message("Writing Results into CSV-Files.\n")
#overview over NAs in resource columns
write.csv(navalues_patient_columns, "Output/number_of_missing_values_patient_columns.csv")
write.csv(navalues_condition_columns, "Output/number_of_missing_values_condition_columns.csv")
write.csv(navalues_observation_columns, "Output/number_of_missing_values_observation_columns.csv")
write.csv(navalues_medication_columns, "Output/number_of_missing_medication_patient_columns.csv")
#percentage of patients with missings in crucial columns
write.csv(precentage_patients_with_no_code_condition, "Output/percentage_patients_missing_condition_code.csv")
write.csv(precentage_patients_with_no_code_observation, "Output/percentage_patients_missing_observation_code.csv")
write.csv(precentage_patients_with_no_code_medication, "Output/percentage_patients_missing_medication_code.csv")

#combinations of conditions corresponding observations and medications
#write.csv(patients_with_condition_observation_medication, "Output/number_of_patients_per_combinations_of_condition_observation_medication.csv")
#descriptives (min, max, mean, n) of available Observations, Conditions and Medications
write.csv(desc_patient_age, "Output/Descriptives_of_Patient_Age.csv")
write.csv(desc_patient_gender, "Output/Descriptives_of_Patient_Gender.csv")
write.csv(desc_observation, "Output/Descriptives_of_Observations.csv")
write.csv(desc_conditions, "Output/Descriptives_of_Conditions.csv")
write.csv(desc_medication, "Output/Descriptives_of_Medications.csv")
#number of eligible and calculable observations per Risk Score
write.csv(crosstabs_eligibility_availability_chadsvasc, "Output/crosstabs_eligible_calculable_chadsvasc.csv")
write.csv(crosstabs_eligibility_availability_smart, "Output/crosstabs_eligible_calculable_smart.csv")
write.csv(crosstabs_eligibility_availability_maggic, "Output/crosstabs_eligible_calculable_maggic.csv")
write.csv(crosstabs_eligibility_availability_charge, "Output/crosstabs_eligible_calculable_charge.csv")
#number of eligible and calculable observations for any Score
write.csv(as.data.frame(crosstabs_eligibility_can_calc_any_score, "Output/crosstabs_eligible_calculable_anyscore.csv", row.names = FALSE))
#number patients who have NAs in any of the columns, per Risk Score
write.csv(navalues_chadsvasc, "Output/number_of_patients_with_NAs_per_column_chadsvasc.csv")
write.csv(navalues_smart, "Output/number_of_patients_with_NAs_per_column_smart.csv")
write.csv(navalues_maggic, "Output/number_of_patients_with_NAs_per_column_maggic.csv")
write.csv(navalues_charge, "Output/number_of_patients_with_NAs_per_column_charge.csv")

#percentage of patients for which score is eligible/can be calculated
write.csv(prob_eligibility_any_score,"Output/percentage_patients_eligible_anyscore.csv")
write.csv(prob_can_calc_any_score,"Output/percentage_patients_cancalc_anyscore.csv")

#crosstables for eligibility und availbility 
write.csv(crosstabs_eligibility_availability_chadsvasc, "Output/eligibility_availability_chadsvasc.csv")
write.csv(crosstabs_eligibility_availability_smart, "Output/eligibility_availability_smart.csv")
write.csv(crosstabs_eligibility_availability_maggic, "Output/eligibility_availability_maggic.csv")
write.csv(crosstabs_eligibility_availability_charge, "Output/eligibility_availability_charge.csv")

#give out statements after certain chunks to document progress
write(paste("Data Exports were finished at", Sys.time(), "\n"), file = log, append = T)

#description of populations that eligible for each risk score (age, gender, maybe condition/observation?)?
#additional variables for description of observation, condition, medication?
message("End.\n")




