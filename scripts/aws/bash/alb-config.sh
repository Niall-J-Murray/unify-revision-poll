#!/bin/bash

# ALB Configuration
export ALB_ARN=arn:aws:elasticloadbalancing:eu-west-1:765194364851:loadbalancer/app/feature-poll-alb/8df3342ec9a47f96
export ALB_DNS_NAME=feature-poll-alb-188799200.eu-west-1.elb.amazonaws.com
export TARGET_GROUP_ARN=arn:aws:elasticloadbalancing:eu-west-1:765194364851:targetgroup/feature-poll-tg/c30b7a2e6ea7282f
export ALB_HOSTED_ZONE_ID=Z32O12XQLNTSW2
export ALB_SG_ID=sg-07e528fc498edba22
export ECS_SG_ID=sg-060c453a48f061539
