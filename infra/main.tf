module "auth" {
  source = "./modules/auth"

  providers = {
    aws = aws.use1
  }

  project = var.project
  email   = var.email
}

module "stack_r1" {
  source = "./modules/regional_stack"

  providers = {
    aws = aws.r1
  }

  project                     = var.project
  region                      = var.region_1
  cognito_user_pool_id        = module.auth.user_pool_id
  cognito_user_pool_client_id = module.auth.user_pool_client_id
  cognito_issuer_url          = module.auth.issuer_url
  email                       = var.email
  repo_url                    = var.repo_url
  sns_topic_arn               = var.sns_verification_topic_arn
}

module "stack_r2" {
  source = "./modules/regional_stack"

  providers = {
    aws = aws.r2
  }

  project                     = var.project
  region                      = var.region_2
  cognito_user_pool_id        = module.auth.user_pool_id
  cognito_user_pool_client_id = module.auth.user_pool_client_id
  cognito_issuer_url          = module.auth.issuer_url
  email                       = var.email
  repo_url                    = var.repo_url
  sns_topic_arn               = var.sns_verification_topic_arn
}
