cd ~/CC_AI/assignments/a2/unify-revision-poll/scripts/aws/bash 


sh 00-deploy-all.sh
sh 01-setup-variables.sh
sh 02-configure-aws-cli.sh
sh 03-create-vpc.sh
sh 04-create-rds.sh
sh 05-create-ecr.sh
sh 06-create-secrets.sh
sh 07-push-docker.sh
sh 08-create-ssl-certificate.sh
sh 09-create-ecs-resources.sh
sh 10-create-route53-record.sh
--- Check first---
sh 11-finalize-deployment.sh


Before we continue, I can't remember if I added that I would
 like to be able to access the RDS DB
  from my local machine.
  Is that something we can do already?