# RDS Configuration
$RDS_ENDPOINT = "feature-poll-db.c72euymwgjn7.eu-west-1.rds.amazonaws.com"
$SECURITY_GROUP_ID = "sg-077dafe09420aa1ae"
$DB_NAME = "feature_poll"
$DB_USERNAME = "dbadmin"
$DB_PASSWORD = "3Q0sZ0tuLTJotUlIV7q5KO9Ajt2bfoMIf3zW5SnDkC0="

# Export variables
$env:RDS_ENDPOINT = $RDS_ENDPOINT
$env:SECURITY_GROUP_ID = $SECURITY_GROUP_ID
$env:DB_NAME = $DB_NAME
$env:DB_USERNAME = $DB_USERNAME
$env:DB_PASSWORD = $DB_PASSWORD
