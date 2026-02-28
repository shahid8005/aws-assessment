output "cognito_user_pool_id" {
  value = module.auth.user_pool_id
}

output "cognito_user_pool_client_id" {
  value = module.auth.user_pool_client_id
}

output "test_user_temp_password" {
  value     = module.auth.temp_password
  sensitive = true
}

output "api_region_1" {
  value = {
    region   = var.region_1
    endpoint = module.stack_r1.api_endpoint
  }
}

output "api_region_2" {
  value = {
    region   = var.region_2
    endpoint = module.stack_r2.api_endpoint
  }
}
