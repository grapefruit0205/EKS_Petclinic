locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # 설계안 Phase 3-5: 비용 태그 (Project, Environment, Owner, ExpiresAt)
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ExpiresAt   = var.expires_at
    ManagedBy   = "terraform"
    Stack       = "foundation"
  }

  name_prefix = "${var.name_prefix}-${var.environment}"

  # 애플리케이션 외부 도메인 (clinic.mission-critical.site)
  app_fqdn = "${var.app_subdomain}.${var.domain_name}"

  # 사용할 AZ 2개
  az_count = length(var.azs)

  # 커스텀 도메인 사용 조건
  custom_domain_enabled = var.enable_custom_domain

  # Cognito Hosted UI 도메인 접두사 (미지정 시 계정 기반 자동 생성)
  cognito_domain_prefix = var.cognito_domain_prefix != "" ? var.cognito_domain_prefix : "${var.name_prefix}-${local.account_id}"
}
