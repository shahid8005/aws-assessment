variable "project" { type = string }
variable "region" { type = string }

variable "cognito_user_pool_id" { type = string }
variable "cognito_user_pool_client_id" { type = string }
variable "cognito_issuer_url" { type = string }

variable "sns_topic_arn" { type = string }
variable "email" { type = string }
variable "repo_url" { type = string }
