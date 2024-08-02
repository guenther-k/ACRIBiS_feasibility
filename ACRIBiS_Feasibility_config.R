# Konfigurations-Datei 
# Bitte die folgenden Variablen entsprechend der Gegebenheiten vor Ort anpassen!

# FHIR-Endpunkt
diz_url = "https://mii-agiop-3p.life.uni-leipzig.de/blaze"

# SSL peer verification angeschaltet lassen?
# TRUE = peer verification anschalten, FALSE = peer verification ausschalten 
ssl_verify_peer <- TRUE

# Müssen die Ressourcen nach Consent gefiltert werden?
# -> Liegen auf dem Server Daten von Patienten mit und ohne Consent gemischt?
filterConsent <- FALSE # wenn gefiltern werden muss: TRUE

# Authentifizierung
# Falls Authentifizierung, bitte entsprechend anpassen (sonst ignorieren):
# Username und Passwort für Basic Authentification
username <- NULL #zB "myusername"
password <- NULL #zB "mypassword"

# Alternativ: Token für Bearer Token Authentifizierung
token <- NULL #zB "mytoken"

#add maximum number of bundles to enable faster run times for testing (e.g. 10 or 20)
bundle_limit <- FALSE