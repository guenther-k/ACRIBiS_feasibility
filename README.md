# About ACRIBiS_feasibility

!! Currently restricted to cases from 2024 via the encounter resource. Please report any problems to guenther_k1@ukw.de !!

The r-files will enable you to conduct the necessary analysis steps for the ACRIBiS-Feasibility. Goal of this project is to gain insights into the availability and completeness of data items required for the calculation of cardiovascular risk scores
In Addition you will need the folder with LOINC-Codes in the directory from which you run the r-scripts

Steps
1. Add your FHIR-server address in the config file under "diz_url" and run the script
2. Run the install_packages script
3. Download the LOINC-Codes from https://loinc.org/file-access/?download-id=470626 (Free Account might be necessary) and place the folder in the working directory. Unfortunately the file is too large to upload to github. The Script currently uses Version 2.78
4. Run the analysis script
5. Document your environmant and the results in corresponding file in the "Test Logs" Folder

