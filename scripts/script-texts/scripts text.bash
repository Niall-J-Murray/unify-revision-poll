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
sh 010-create-route53-record.sh
--- Check first---
sh 011-finalize-deployment.sh


I should have also added that I would like to be able to access the RDS DB from my local machine.