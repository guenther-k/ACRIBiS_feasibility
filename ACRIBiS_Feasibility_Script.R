source("install_R_packages.R")
source("support_functions.R")

#source config
if(file.exists("config.R")&&!dir.exists("config.R")){
  source("config.R")
}else{
  source("config.R.default")  
}


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
  resource = "medicationAdministration",
  cols = c(medicationAdministration_identifier            = "id",
           medicationAdministration_subject               = "subject/reference", 
           medicationAdministration_status                = "status",
           medicationAdministration_medication_reference  = "medicationReference/reference",
           medicationAdministration_effective_dateTime    = "effective/effectivedateTime",
           medicationAdministration_effective_period      = "effective/effectivePeriod"
  )
)
## Medication
tabledescription_medication <- fhir_table_description(
  resource = "Medication",
  cols = c(medication_identifier      = "id",
           medication_system          = "code/coding[system[@value='http://fhir.de/CodeSystem/bfarm/atc']]/system",
           medication_code            = "code/coding[system[@value='http://fhir.de/CodeSystem/bfarm/atc']]/code",
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
body_conditions <- fhir_body(content = list("code" = paste(icd10_codes_patient_conditions$icd_normcode, collapse = ",")))
request_conditions <- fhir_url(url = diz_url, resource = "Condition")
bundles_condition <- fhir_search(request = request_conditions, body = body_conditions)
# no saving necessary
table_conditions <- fhir_crack(bundles = bundles_condition, design = tabledescription_condition, verbose = 1)

#search for patients who have the specified conditions
#remove "Patient/" prefix from referenced Patient IDs
patient_ids_with_conditions_prefix <- table_conditions$condition_subject
patient_ids_with_conditions <- sub("Patient/", "", table_conditions$condition_subject)


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
bundles_patient <- fhir_search(request = request_patients, body = body_patient)

#give out statements after certain chunks to document progress
write(paste("Finished Search for Patient-Ressources at", Sys.time(), "\n"), file = log, append = T)
write(paste(length(bundles_patient), " Bundles for the Patient-Ressource were found \n"), file = log, append = T)


#Condition
#now load all CONDITIONS for relevant patient IDs, to obtain other conditions (comorbidities) of relevant patients
#use "patient" as FHIR-search parameter in Condition resource
body_conditions <- fhir_body(content = list("subject" = patient_ids_with_conditions))
request_conditions <- fhir_url(url = diz_url, resource = "Condition")
#code or normcode?; normcode appears to work
bundles_condition <- fhir_search(request = request_conditions)

#give out statements after certain chunks to document progress
write("Finished Search for Condition-Ressources at", Sys.time(), "\n", file = log, append = T)
write(paste(length(bundles_condition), " Bundles for the Condition-Ressource were found \n"), file = log, append = T)


# Observation
#use "subject" as FHIR search parameter for Observation resource
body_observation <- fhir_body(content = list("subject" = paste(patient_ids_with_conditions, collapse = ","), "code" = LOINC_codes_all))
request_observations <- fhir_url(url = diz_url, resource = "Observation")
bundles_observation <- fhir_search(request = request_observations, body = body_observation)

#give out statements after certain chunks to document progress
write(paste("Finished Search for Observation-Ressources at", Sys.time(), "\n"), file = log, append = T)
write(paste(length(bundles_observation), " Bundles for the Observation-Ressource were found \n"), file = log, append = T)


# medicationAdministration
#use "subject" as FHIR-Search parameter in medicationAdministration resource
#restrict data used by implementing the relevant ATC codes here -> medications_all
body_medicationAdministration <- fhir_body(content = list("subject" = paste(patient_ids_with_conditions, collapse = ","), "medication" = medications_all))
request_medicationAdministrations <- fhir_url(url = diz_url, resource = "MedicationAdministration")
bundles_medicationAdministration <- fhir_search(request = request_medicationAdministrations)

#give out statements after certain chunks to document progress
write(paste("Finished Search for MedicationAdministration-Ressources at", Sys.time(), "\n"), file = log, append = T)
write(paste(length(bundles_medicationAdministration), " Bundles for the MedicationAdministration-Ressource were found \n"), file = log, append = T)


#save for later loading, and to check for entries
fhir_save(bundles = bundles_medicationAdministration, directory = "XML_Bundles/bundles_medicationAdministration")
#crack immediately to provide ids for medication-search

if(check_fhir_bundles_in_folder("XML_Bundles/bundles_medicationAdministration") == FALSE) {
  message("The bundle you are trying to crack is empty. This will result in an error. Therefore the bundle will not be cracked.")
  #create list of medications in the medicationAdministrations of the Patients
  medicationAdministration_ids <- NA
} else {
    message("Cracking ", length(bundles_medicationAdministration), " medicationAdministration Bundles.\n")
    table_medicationAdministrations <- fhir_crack(bundles = bundles_medicationAdministration, design = tabledescription_medicationAdministration, verbose = 1)
    #create list of medications in the medicationAdministrations of the Patients
    medicationAdministration_ids <- sub("Medication/", "", table_medicationAdministrations$medicationAdministration_medication_reference)
    #give out statements after certain chunks to document progress
    write(paste("Cracked Table for MedicationAdministration-Ressources at", Sys.time(), "\n"), file = log, append = T)
    write(paste(nrow(table_medicationAdministrations), " Elements were created for MedicationAdministration \n"), file = log, append = T)
}



# Medication
if(contains_ids(medicationAdministration_ids)) {
  body_medication <- fhir_body(content = list("_id" = paste(medicationAdministration_ids, collapse = ","), "code" = medications_all))
  request_medications <- fhir_url(url = diz_url, resource = "Medication")
  bundles_medication <- fhir_search(request = request_medications, body = body_medication)
} else {
    message("There are no entries in the Resource medicationAdministrations, therefore the corresponding Medications could not be retrieved")
}

#give out statements after certain chunks to document progress
write(paste("Finished Search for Medication-Ressources at", Sys.time(), "\n"), file = log, append = T)
write(paste(length(bundles_medication), " Bundles for the Medication-Ressource were found \n"), file = log, append = T)

#(Modul Fall für Einrichtungskontakt: nicht möglich, da Abteilungsschlüssel nur in Beschreibung aber nicht in FHIR-Profil hinterlegt ist)


# Save Bundles ------------------------------------------------------------
# (only after first download) move to FHIR Search section (so far only medicationAdministration)
#save and load to circumvent long download times for bundles; comment and uncomment with line above (fhir_search) as necessary
message("Saving  Bundles.\n")
fhir_save(bundles = bundles_patient, directory = "XML_Bundles/bundles_patient")
fhir_save(bundles = bundles_condition, directory = "XML_Bundles/bundles_condition")
fhir_save(bundles = bundles_observation, directory = "XML_Bundles/bundles_observation")
#medicationStaements is cracked earlier to retrieve IDs for download of Medication data
fhir_save(bundles = bundles_medication, directory = "XML_Bundles/bundles_medication")
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

#cracking above, to provide ids for medications
# message("Cracking ", length(bundles_medicationAdministration), " medicationAdministration Bundles.\n")
# table_medicationAdministrations <- fhir_crack(bundles = bundles_medicationAdministration, design = tabledescription_medicationAdministration, verbose = 1)

if(check_fhir_bundles_in_folder("XML_Bundles/bundles_medication") == FALSE) {
  message("The bundle you are trying to crack is empty. This will result in an error. Therefore the bundle will not be cracked.")
} else {
message("Cracking ", length(bundles_medication), " Medication Bundles.\n")
table_medications <- fhir_crack(bundles = bundles_medication, design = tabledescription_medication, verbose = 1)
write(paste(nrow(table_medications), " Elements were created for Medications \n"), file = log, append = T)
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
loinc_codes <- read.csv("Loinc_2.76/LoincTable/Loinc.csv")
#add content of LOINC codes to observation table
table_observations <-  merge(table_observations, loinc_codes[, c("LOINC_NUM", "COMPONENT")], by.x = "observation_code", by.y = "LOINC_NUM", all.x = TRUE)
# Rename column COMPONENT to observation_LOINC_term
colnames(table_observations)[colnames(table_observations) == "COMPONENT"] <- "observation_LOINC_term"
}

#give out statements after certain chunks to document progress
write(paste("Data Cleaning was finished at", Sys.time(), "\n"), file = log, append = T)

# Link Resources ----------------------------------------------------------
message("Combining Tables.\n")

if(check_fhir_bundles_in_folder("XML_Bundles/bundles_Patient") == FALSE | check_fhir_bundles_in_folder("XML_Bundles/bundles_Condition") == FALSE) {
  message("One of the tables you are trying to merge does not exist (Possibly due to empty resources). Therefore the merge-statement will not be carried out.")
} else {
#add conditions to the patients where available
table_pat_cond <- merge(table_patients, table_conditions, by.x = "patient_identifier", by.y = "condition_subject", all.x = TRUE)
}

if(check_fhir_bundles_in_folder("XML_Bundles/bundles_Observation") == FALSE) {
  message("One of the tables you are trying to merge does not exist (Possibly due to empty resources). Therefore the merge-statement will not be carried out.")
} else {
#add observations to the patients and conditions where available
table_pat_cond_obs <- merge(table_pat_cond, table_observations, by.x = "patient_identifier", by.y = "observation_subject", all.x = TRUE)
}

if(check_fhir_bundles_in_folder("XML_Bundles/bundles_medicationAdministration") == FALSE) {
  message("One of the tables you are trying to merge does not exist (Possibly due to empty resources). Therefore the merge-statement will not be carried out.")
} else {
#combine medication statement with the respective medications
table_meds <- merge(table_medicationAdministrations, table_medications, by.x = "medicationAdministration_medication_reference", by.y = "medication_identifier", all.x = TRUE)
}

if(check_fhir_bundles_in_folder("XML_Bundles/bundles_medicationAdministration") == FALSE) {
  message("One of the tables you are trying to merge does not exist (Possibly due to empty resources). Therefore the merge-statement will not be carried out.")
} else {
#add medications to patients and conditions and observations
table_pat_cond_obs_med <- merge(table_pat_cond_obs, table_meds, by.x = "patient_identifier", by.y = "medicationAdministration_subject", all.x = TRUE)
table_all <- table_pat_cond_obs_med
rm(table_pat_cond, table_pat_cond_obs, table_pat_cond_obs_med)
}

if(is.null(table_all) == TRUE) {
  message("One of the tables you are trying to merge does not exist (Possibly due to empty resources). Therefore the merge-statement will not be carried out.")
} else {

#column with time since first CVD Diagnosis for each patient per patient
#calculate time since first Cardiovascular Diagnosis (I05-I09, I20-I25, I30-I52)
#for recordedDate (mandatory)
table_all %>%
  filter(condition_code %in% icd10_codes_patient_conditions) %>%
  group_by(patient_identifier) %>%
  mutate(condition_first_diagnosis_date = min(condition_recordedDate)) %>%
  ungroup() %>%
  mutate(condition_time_since_first_cvd_record = as.numeric(difftime(Sys.Date(), condition_first_diagnosis_date, units = "days")))
#should work if data is available, otherwise warning
#same for onsetDate if available (optional)
table_all %>%
  filter(condition_code %in% icd10_codes_patient_conditions) %>%
  group_by(patient_identifier) %>%
  mutate(condition_first_diagnosis_date = min(condition_onsetDate)) %>%
  ungroup() %>%
  mutate(condition_time_since_first_cvd_onset = as.numeric(difftime(Sys.Date(), condition_first_diagnosis_date, units = "days")))
#should work if data is available, otherwise warning

#give out statements after certain chunks to document progress
write(paste("Resource-Tables were combined into one Table at", Sys.time(), "\n"), file = log, append = T)
write(paste("The combined Table across all Resources has ", nrow(table_all), " Entries for ", length(unique(table_all$patient_identifier)) ," Patients \n"), file = log, append = T)


# Feasibility Analysis ----------------------------------------------------
message("Analysing Data.\n")
## check availability of parameters 
#sum up all entries of NA in each of the columns of table_all
navalues_all_columns <- table_all %>% summarise(across(everything(), ~ sum(is.na(.))))


## possibly repeat for each Score-specific table
#count number of NAs in each column for every ID, multiple entries per ID expected with multiple conditions, medications and observations
na_counts_table_all <- table_all %>%
  group_by(patient_identifier) %>%
  summarise_all(~ sum(is.na(.)))
#count number of observations in each column for every ID
observation_counts_table_all <- table_all %>%
  group_by(patient_identifier) %>%
  summarise(observations_count = n())
#subtract number of overall observations from number of NA-observations
observations_empty_columns <- na_counts_table_all[2:28] - observation_counts_table_all$observations_count 
#re-add IDs
observations_empty_columns <- cbind(na_counts_table_all$patient_identifier, observations_empty_columns)
#count number of IDs that have columns where all observations were NA
observations_NA_columns <- colSums(observations_empty_columns == 0)


#count number of patients (navalues_all_columns counts data entries not patients) who have NA in condition code, observation code or medication code 
patients_with_navalues_condition <- table_all %>%
  filter(is.na(condition_code)) %>%
  summarise(condition_code_na = n_distinct(patient_identifier))
patients_with_navalues_observation <- table_all %>%
  filter(is.na(observation_code)) %>%
  summarise(observation_code_na = n_distinct(patient_identifier))
patients_with_navalues_medication <- table_all %>%
  filter(is.na(medication_code)) %>%
  summarise(medication_code_na = n_distinct(patient_identifier))

#count different combinations of NA values for the condition code, the observations code, and the medication code 
#identify common combinations(?)
patients_with_condition_observation_medication <- sqldf('select count(distinct patient_identifier), condition_code, observation_code, medication_code
                                                    from table_all
                                                    group by condition_code, observation_code, medication_code')

length(patients_with_navalues_condition)
length(patients_with_navalues_observation)
length(patients_with_navalues_medication)
patients_with_condition_observation_medication

## Check distribution of parameters ##########################################################################
#gives min, max, mean, median and n where applicable (discrete and continuous data)
desc_patient_age <- table_patients %>% summarise(min_age = min(patient_age), mean_age = mean(patient_age), median_age = median(patient_age), max_age = max(patient_age), n = n())
#observation
desc_observation <- table_observations %>% filter(!is.na(observation_code)) %>% group_by(observation_code, observation_LOINC_term) %>% summarise(min = min(observation_value_num), mean = mean(observation_value_num), median = median (observation_value_num), max = max(observation_value_num), n=n())
#condition
desc_conditions <- table_conditions %>% filter(!is.na(condition_code)) %>% count(condition_code)
#medications
desc_medication <- table_meds %>% filter(!is.na(medication_code)) %>% count(medication_code)

desc_patient_gender <- as.data.frame(table(table_patients$patient_gender))

desc_patient_age
desc_patient_gender
desc_observation
desc_conditions
desc_medication


### Create Tables for Observation (not Patients) with respective Score criteria 

#shorten ICD-10 code to simplify operations (only first three characters are needed)
table_all$condition_code_short <- substr(table_all$condition_code,1,3)

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


# create variable to indicate if patient/observation is score eligible and if score can be calculated
#eligible
table_all$chadsvasc_eligible <- ifelse((table_all$patient_age >= 18) 
                                       & (table_all$condition_code %in% chadsvasc_inclusion_icd_codes$icd_normcode), 1, 0)
table_all$smart_eligible <- ifelse(table_all$patient_age >= 40 & table_all$patient_age <= 80 
                                   & table_all$condition_code %in% smart_inclusion_icd_codes$icd_normcode, 1, 0)
table_all$maggic_eligible <- ifelse(table_all$patient_age >= 18 
                                    & table_all$condition_code %in% maggic_inclusion_icd_codes$icd_normcode, 1, 0)
#define loinc codes for which to check the value
charge_check_loinc_codes <- c("14682-9", "2160-0", "38483-4", "77140-2")

table_all$charge_eligible <- ifelse(table_all$patient_age >= 46 & table_all$patient_age <= 94 
                                    & table_all$condition_code_short != "I48" 
                                    & (!(table_all$observation_code %in% charge_check_loinc_codes & table_all$observation_value_num > 2)), 1, 0)
table_all$charge_eligible <- ifelse(is.na(table_all$charge_eligible), 0, table_all$charge_eligible)

#can_calc, alle necessary observations are available; if patient does not conditions/medications they are (correctly) missing
table_all$chadsvasc_can_calc <- ifelse(table_all$patient_age >= 18 
                                       & !is.na(table_all$patient_gender), 1, 0)
table_all$smart_can_calc <- ifelse(table_all$patient_age >= 18 
                                   & !is.na(table_all$patient_gender) 
                                   & (table_all$observation_code %in% LOINC_codes_cholesterol_hdl | table_all$observation_code %in% LOINC_codes_cholesterol_overall) 
                                   & table_all$observation_code %in% LOINC_codes_bp_sys, 1, 0)
table_all$maggic_can_calc <- ifelse(table_all$patient_age >= 18 
                                    & !is.na(table_all$patient_gender) 
                                    & table_all$observation_code %in% LOINC_codes_bp_sys 
                                    & table_all$observation_code %in% LOINC_codes_lvef 
                                    & table_all$observation_code %in% LOINC_codes_creatinine, 1, 0)
table_all$charge_can_calc <- ifelse(table_all$patient_age >= 18 
                                    & !is.na(table_all$patient_gender) 
                                    & (table_all$observation_code %in% LOINC_codes_bmi | (table_all$observation_code %in% LOINC_codes_height & table_all$observation_code %in% LOINC_codes_weight)), 1, 0)
#check definitions above, are all mandatory variables taken into account? others are assumed to be 0 if not available


#cross table for eligibility and variables availability (can_calc) for each Score
crosstabs_eligibility_availability_chadsvasc <- table(table_all$chadsvasc_eligible, table_all$chadsvasc_can_calc, dnn = list("Eligible", "Calculable"))
crosstabs_eligibility_availability_smart <- table(table_all$smart_eligible, table_all$smart_can_calc, dnn = list("Eligible", "Calculable"))
crosstabs_eligibility_availability_maggic <- table(table_all$maggic_eligible, table_all$maggic_can_calc, dnn = list("Eligible", "Calculable"))
crosstabs_eligibility_availability_charge <- table(table_all$charge_eligible, table_all$charge_can_calc, dnn = list("Eligible", "Calculable")) 


#check how many patients are eligible (group by patient_id) and for how many score can be calculated (required observations made, eg. Lab-data)
#Assumption: if Medications or Conditions are missing, the patient does not have them (sensitivity?) non-existence cannot be confirmed by routine data, correct?
table_all$any_score_eligible <- ifelse(table_all$chadsvasc_eligible == 1 | table_all$smart_eligible == 1 | table_all$maggic_eligible == 1 | table_all$charge_eligible == 1, 1, 0)
table_all$any_score_can_calc <- ifelse(table_all$chadsvasc_can_calc == 1 | table_all$smart_can_calc == 1 | table_all$maggic_can_calc == 1 | table_all$charge_can_calc == 1, 1, 0)

#Percentage with inclusion of min 1 score
prob_algibility_any_score <- prop.table(table(table_all$any_score_eligible))
#Percentage for which any score can be calculated
prop.table(table(table_all$any_score_can_calc))

#bei Calc noch die Elig hinzufügen, da ja die Frage ist von wie vielen die infrage kommen, kann  der Score berechnet werden
prop.table(table(table_all$any_score_eligible, table_all$any_score_can_calc),1)



#Calculate percentage with NAs per Variable for each score, if eligible
navalues_chadsvasc <- filter(table_all, table_all$chadsvasc_eligible == 1) %>%
  group_by(patient_identifier) %>%
  summarise_all(~sum(is.na(.)))
navalues_chadsvasc <- colSums(navalues_chadsvasc[-1])

navalues_smart <- filter(table_all, table_all$smart_eligible == 1) %>%
  group_by(patient_identifier) %>%
  summarise_all(~sum(is.na(.)))
navalues_smart <- colSums(navalues_smart[-1])

navalues_maggic <- filter(table_all, table_all$maggic_eligible == 1) %>%
  group_by(patient_identifier) %>%
  summarise_all(~sum(is.na(.)))
navalues_maggic <- colSums(navalues_maggic[-1])

navalues_charge <- filter(table_all, table_all$charge_eligible == 1) %>%
  group_by(patient_identifier) %>%
  summarise_all(~sum(is.na(.)))
navalues_charge <- colSums(navalues_charge[-1])

navalues_chadsvasc
navalues_smart
navalues_maggic
navalues_charge

#give out statements after certain chunks to document progress
write(paste("Analysis Steps were finished at", Sys.time(), "\n"), file = log, append = T)


# Data Export -------------------------------------------------------------
message("Writing Results into CSV-Files.\n")
#export relevant data as csv for further use
write.csv(navalues_all_columns, "Output/missing_values_all_columns.csv")
write.csv(observations_empty_columns, "Output/observation_empty_columns.csv")
write.csv(observations_NA_columns, "Output/observation_NA_columns_only.csv")


#combinations of conditions corresponding observations and medications
write.csv(patients_with_condition_observation_medication, "Output/number_of_patients_per_combinations_of_condition_observation_medication.csv")
#descriptives (min, max, mean, n) of available Observations, Conditions and Medications
write.csv(desc_patient_age, "Output/Descriptives_of_Patient_Age.csv")
write.csv(desc_patient_gender, "Output/Descriptives_of_Patient_Gender.csv")
write.csv(desc_observation, "Output/Descriptives_of_Observations.csv")
write.csv(desc_conditions, "Output/Descriptives_of_Conditions.csv")
write.csv(desc_medication, "Output/Descriptives_of_Medications.csv")
#number of eligible and calculable observations per Risk Score
write.csv(as.data.frame(table(table_all$chadsvasc_eligible, table_all$chadsvasc_can_calc, dnn = list("Eligible", "Calculable"))), "Output/crosstabs_eligible_calculable_chadsvasc")
write.csv(as.data.frame(table(table_all$smart_eligible, table_all$smart_can_calc, dnn = list("Eligible", "Calculable"))), "Output/crosstabs_eligible_calculable_smart")
write.csv(as.data.frame(table(table_all$maggic_eligible, table_all$maggic_can_calc, dnn = list("Eligible", "Calculable"))), "Output/crosstabs_eligible_calculable_maggic")
write.csv(as.data.frame(table(table_all$charge_eligible, table_all$charge_can_calc, dnn = list("Eligible", "Calculable"))), "Output/crosstabs_eligible_calculable_charge")
#number of eligible and calculable observations for any Score
write.csv(as.data.frame(table(table_all$any_score_eligible, table_all$any_score_can_calc, dnn = list("Eligible", "Calculable"))), "Output/crosstabs_eligible_calculable_charge")
#number patients who have NAs in any of the columns, per Risk Score
write.csv(navalues_chadsvasc, "Output/number_of_patients_with_NAs_per_column_chadsvasc.csv")
write.csv(navalues_smart, "Output/number_of_patients_with_NAs_per_column_smart.csv")
write.csv(navalues_maggic, "Output/number_of_patients_with_NAs_per_column_maggic.csv")
write.csv(navalues_charge, "Output/number_of_patients_with_NAs_per_column_charge.csv")

#crosstables for eligibility und availbility 
write.csv(crosstabs_eligibility_availability_chadsvasc, "Output/eligibility_availability_chadsvasc")

#give out statements after certain chunks to document progress
write(paste("Data Exports were finished at", Sys.time(), "\n"), file = log, append = T)


#description of populations that eligible for each risk score (age, gender, maybe condition/observation?)?
#additional variables for description of observation, condition, medication?
message("End.\n")

}
