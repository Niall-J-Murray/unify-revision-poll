#!/bin/bash

# RDS Configuration
export RDS_ENDPOINT=feature-poll-db.c72euymwgjn7.eu-west-1.rds.amazonaws.com
export SECURITY_GROUP_ID=sg-068e684666bbc3521 # <-- Ensure this is saved
export DB_NAME=feature_poll
export DB_USERNAME=dbadmin # <-- Use the variable, not hardcoded 'admin'
export DB_PASSWORD='9b8e1a9d317b35f9ae3568c6f94c2002eeb96256d1f60e31657960189389a79b' # <-- Use single quotes to preserve special chars if any
