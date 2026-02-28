variable "project" {
  type    = string
  default = "unleash-live-assessment"
}

variable "region_1" {
  type    = string
  default = "us-east-1"
}

variable "region_2" {
  type    = string
  default = "eu-west-1"
}

variable "email" {
  description = "Your real email to create Cognito test user + SNS payload"
  type        = string
}

variable "repo_url" {
  description = "Repo URL for SNS payload"
  type        = string
}

variable "sns_verification_topic_arn" {
  type    = string
  default = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
}
