resource "aws_cognito_user_pool" "pool" {
  name = "${var.project}-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 10
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.project}-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

resource "random_password" "temp" {
  length  = 16
  special = false
}

# Create the user with a temporary password (script will handle NEW_PASSWORD_REQUIRED)
resource "aws_cognito_user" "test_user" {
  user_pool_id = aws_cognito_user_pool.pool.id
  username     = var.email

  attributes = {
    email          = var.email
    email_verified = "true"
  }

  temporary_password = random_password.temp.result
  message_action     = "SUPPRESS"
}
