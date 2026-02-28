

## Overview
This repo provisions:
- Cognito User Pool + Client (us-east-1)
- Identical regional stacks in two regions (default: us-east-1 and eu-west-1):
  - HTTP API Gateway with JWT authorizer (Cognito in us-east-1)
  - DynamoDB regional table
  - Lambda /greet (writes to DynamoDB + publishes verification SNS message)
  - Lambda /dispatch (runs ECS Fargate task)
  - ECS Fargate task publishes verification SNS message then exits
- Automated test script:
  - Auth with Cognito, gets JWT
  - Concurrently calls /greet and /dispatch in both regions
  - Prints latency + asserts response region matches endpoint region

## Prerequisites
- AWS CLI configured with sandbox credentials
- Terraform >= 1.6
- Python 3.10+
- pip install httpx boto3

## Deploy
```bash
cd infra
terraform init
terraform apply -auto-approve \
  -var "email=shahid.aslam1786@gmail.com" \
  -var "repo_url=https://github.com/shahid8005/aws-assessment"
