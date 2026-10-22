###############################################################################
# Secrets Manager (설계안 4.3 / 5.2)
#   - 앱 런타임 DML 계정 / migration DDL 계정 / 공유 세션 Secret
#   - 값은 ephemeral random_password 로 생성하고 write-only 인자로 기록한다.
#     => 평문이 Terraform state 에 저장되지 않는다.
#   - RDS master 는 RDS 관리형 Secret 을 사용한다 (modules/rds).
###############################################################################

ephemeral "random_password" "app" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

ephemeral "random_password" "migration" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

ephemeral "random_password" "session" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ── App 런타임 계정 (DML only) ──────────────────────────────────────────────
resource "aws_secretsmanager_secret" "app" {
  name        = "${local.name_prefix}/app/db"
  description = "Petclinic app runtime DB credentials (DML only)"
  kms_key_id  = aws_kms_key.main.arn

  recovery_window_in_days = 7

  tags = {
    Name       = "${local.name_prefix}-app-db"
    SecretType = "runtime"
  }
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string_wo = jsonencode({
    username = "petclinic_app"
    password = ephemeral.random_password.app.result
    engine   = "mysql"
    host     = module.rds.db_address
    port     = module.rds.db_port
    dbname   = module.rds.db_name
    jdbcUrl  = "jdbc:mysql://${module.rds.db_address}:${module.rds.db_port}/${module.rds.db_name}?useSSL=true&requireSSL=true&verifyServerCertificate=true"
  })
  secret_string_wo_version = 1
}

# ── Migration 계정 (DDL) ────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "migration" {
  name        = "${local.name_prefix}/migration/db"
  description = "Petclinic migration DB credentials (DDL)"
  kms_key_id  = aws_kms_key.main.arn

  recovery_window_in_days = 7

  tags = {
    Name       = "${local.name_prefix}-migration-db"
    SecretType = "migration"
  }
}

resource "aws_secretsmanager_secret_version" "migration" {
  secret_id = aws_secretsmanager_secret.migration.id
  secret_string_wo = jsonencode({
    username = "petclinic_migrator"
    password = ephemeral.random_password.migration.result
    engine   = "mysql"
    host     = module.rds.db_address
    port     = module.rds.db_port
    dbname   = module.rds.db_name
    jdbcUrl  = "jdbc:mysql://${module.rds.db_address}:${module.rds.db_port}/${module.rds.db_name}?useSSL=true&requireSSL=true&verifyServerCertificate=true"
  })
  secret_string_wo_version = 1
}

# ── 공유 세션 (Spring Session JDBC) ─────────────────────────────────────────
resource "aws_secretsmanager_secret" "session" {
  name        = "${local.name_prefix}/app/session"
  description = "Petclinic Spring Session signing/encryption secret"
  kms_key_id  = aws_kms_key.main.arn

  recovery_window_in_days = 7

  tags = {
    Name       = "${local.name_prefix}-session"
    SecretType = "session"
  }
}

resource "aws_secretsmanager_secret_version" "session" {
  secret_id = aws_secretsmanager_secret.session.id
  secret_string_wo = jsonencode({
    sessionSecret = ephemeral.random_password.session.result
  })
  secret_string_wo_version = 1
}

# ── Cognito 앱 클라이언트 자격증명 ──────────────────────────────────────────
resource "aws_secretsmanager_secret" "cognito" {
  name        = "${local.name_prefix}/app/cognito"
  description = "Petclinic Cognito OIDC client credentials"
  kms_key_id  = aws_kms_key.main.arn

  recovery_window_in_days = 7

  tags = {
    Name       = "${local.name_prefix}-cognito"
    SecretType = "oidc"
  }
}

resource "aws_secretsmanager_secret_version" "cognito" {
  secret_id = aws_secretsmanager_secret.cognito.id
  secret_string_wo = jsonencode({
    clientId     = aws_cognito_user_pool_client.app.id
    clientSecret = aws_cognito_user_pool_client.app.client_secret
    issuerUri    = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
    userPoolId   = aws_cognito_user_pool.this.id
  })
  secret_string_wo_version = 1
}
