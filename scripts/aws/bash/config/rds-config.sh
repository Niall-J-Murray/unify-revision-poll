#!/bin/bash

# RDS Configuration
export RDS_ENDPOINT=feature-poll-db.c72euymwgjn7.eu-west-1.rds.amazonaws.com
export SECURITY_GROUP_ID=sg-0a68566886e2153db # <-- Ensure this is saved
export DB_NAME=feature_poll
export DB_USERNAME=dbadmin # <-- Use the variable, not hardcoded 'admin'
export DB_PASSWORD=\'7c31da42d009b742a2d39a0d2d171fdf1b199b94b1281123ff47ed9f7d06a249\' # <-- Use single quotes to preserve special chars if any
