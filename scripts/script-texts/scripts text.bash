# Navigate to the bash scripts directory
cd ~/CC_AI/assignments/a2/unify-revision-poll/scripts/aws/bash 

# --- Run Full Deployment ---
# Ensure AWS credentials and HOSTED_ZONE_ID are set first!
# (See previous instructions)
sh 00-deploy-all.sh

# Add | cat for longer output
sh script-name.sh | cat
# --- Individual Script Execution Order (for reference/debugging) ---
# Note: Running 00-deploy-all.sh is the standard way.
sh 01-setup-variables.sh
sh 02-configure-aws-cli.sh
sh 02b-create-hosted-zone.sh
sh 03-setup-networking.sh
sh 04-create-rds.sh
sh 04b-setup-bastion.sh
sh 05-create-ecr.sh
sh 06-build-push-docker.sh
sh 07-create-secrets.sh
sh 08-setup-domain-ssl.sh
sh 09-create-ecs-resources.sh
sh 09-create-ecs-resources.sh | cat
sh 09b-create-dns-record.sh
sh 10-finalize-deployment.sh

# --- Troubleshooting (If deployment has issues) ---
# Run this script to check the status of various resources
sh 11-diagnose-ecs.sh

# --- Cleanup (Destructive - Use with Caution!) ---
# Run this script to delete all resources created by the deployment
# WARNING: Make sure you want to delete everything before uncommenting and running!
sh 12-cleanup-resources.sh



