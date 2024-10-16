# Support Functions

#Birthyear
convert_date_to_year <- function(birthdate) {
  year <- as.numeric(substr(birthdate, 1, 4))
  return(year)
}



#Cracking empty bundles results in script termination; therefore bundles have to be checked for entries
#Data Availability in Bundles is based on entries; if there is no corresponding data in FHIR Server, bundles will be present but without entries
#Function to check if a FHIR bundle is empty
is_fhir_bundle_empty <- function(folder_path) {
  
  files <- list.files(path = folder_path, pattern = "\\.xml$", full.names = TRUE)
  
  #Read the XML file
  fhir_bundle <- read_xml(files[1])
  
  #Check if the 'entry' node is present and has any entries
  entries <- xml_find_all(fhir_bundle, "//entry")
  if (length(entries) > 0) {
    return(FALSE)  # Bundle is not empty
  } else {
    return(TRUE)   # Bundle is empty
  }
}

#Check bundles that are saved as XML files in the respective folder (unclear if check directly in R is possible)
#Function to check all XML files in a folder
are_fhir_bundles_in_folder <- function(folder_path) {
  # List all XML files in the folder
  xml_files <- list.files(folder_path, pattern = "\\.xml$", full.names = TRUE)
  
  # Initialize a flag for early termination
  entry_found <- FALSE
  
  # Check each file
  for (file in xml_files) {
    if (is_fhir_bundle_empty(folder_path) == FALSE) {
      cat(file, "is not empty.\n")
      entry_found <- TRUE
      return(entry_found)
      break
    }
  }
  
  if (entry_found == FALSE) {
    cat("All bundles are empty.\n")
    return(entry_found)
  }
}


#create function to check whether IDs could be retreived
contains_ids <- function(vec) {
  # Check if the vector is not empty and contains non-NA values
  return(length(vec) > 0 && any(!is.na(vec)))
}