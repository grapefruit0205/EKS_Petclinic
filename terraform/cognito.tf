###############################################################################
# Cognito User Pool / Client (설계안 Phase 7-1, 6.3)
#   - 공개 self-signup 비활성화
#   - Authorization Code + OIDC, confidential client
###############################################################################
resource "aws_cognito_user_pool" "this" {
  name = "${local.name_prefix}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OPTIONAL"

  admin_create_user_config {
    allow_admin_create_user_only = true # 공개 self-signup 금지
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  software_token_mfa_configuration {
    enabled = true
  }

  tags = { Name = "${local.name_prefix}-users" }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = local.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

# 읽기/쓰기 역할 분리 (설계안 5.1)
resource "aws_cognito_user_group" "readers" {
  name         = "petclinic-readers"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Read-only access to petclinic data"
  precedence   = 10
}

resource "aws_cognito_user_group" "writers" {
  name         = "petclinic-writers"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Read/write access to petclinic data"
  precedence   = 5
}

resource "aws_cognito_user_pool_client" "app" {
  name         = "${local.name_prefix}-app-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = true # confidential client (서버 사이드 OIDC)

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true

  supported_identity_providers = ["COGNITO"]

  callback_urls = [
    "https://${local.app_fqdn}/login/oauth2/code/cognito",
    "http://localhost:8080/login/oauth2/code/cognito",
  ]

  logout_urls = [
    "https://${local.app_fqdn}/",
    "http://localhost:8080/",
  ]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  prevent_user_existence_errors = "ENABLED"

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
}
