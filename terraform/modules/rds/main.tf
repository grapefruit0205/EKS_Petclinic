###############################################################################
# RDS MySQL (설계안 Phase 4)
#   - isolated data 서브넷 (외부 기본 경로 없음)
#   - publicly_accessible = false
#   - Multi-AZ, 삭제 보호, 자동 백업(PITR)
#   - master 자격증명은 RDS 관리형 Secrets Manager (state 에 평문 저장하지 않음)
###############################################################################

resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-db-subnet-group"
  description = "Petclinic RDS subnet group (isolated data subnets)"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-subnet-group" })
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.name_prefix}-mysql84"
  family      = var.parameter_group_family
  description = "Petclinic MySQL parameter group"

  # 운영 안전 기본값 (설계안 5.2)
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  # JDBC TLS 강제는 앱/계정 단위로도 검증한다.
  parameter {
    name         = "require_secure_transport"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "1"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-mysql84" })
}

resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_id != "" ? var.kms_key_id : null

  db_name  = var.db_name
  username = var.master_username

  # master 자격증명을 RDS 관리형 Secrets Manager 로 생성 (Terraform state 평문 노출 회피)
  manage_master_user_password = true

  multi_az            = var.multi_az
  publicly_accessible = false

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.this.name

  backup_retention_period    = var.backup_retention_days
  backup_window              = "17:00-18:00" # UTC (02:00-03:00 KST)
  maintenance_window         = "sun:18:00-sun:19:00"
  copy_tags_to_snapshot      = true
  delete_automated_backups   = false
  auto_minor_version_upgrade = false

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  enabled_cloudwatch_logs_exports = ["error", "slowquery", "general"]

  ca_cert_identifier = var.ca_cert_identifier

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final"

  apply_immediately = false

  tags = merge(var.tags, { Name = var.identifier })
}

###############################################################################
# Enhanced Monitoring IAM role
###############################################################################
resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name = "${var.name_prefix}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-monitoring-role" })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_partition" "current" {}
