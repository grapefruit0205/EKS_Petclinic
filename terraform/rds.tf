###############################################################################
# RDS MySQL (설계안 Phase 4)
###############################################################################
module "rds" {
  source = "./modules/rds"

  name_prefix     = local.name_prefix
  identifier      = "${local.name_prefix}-mysql"
  db_name         = var.db_name
  master_username = var.db_master_username

  instance_class        = var.db_instance_class
  engine_version        = var.db_engine_version
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  multi_az              = var.db_multi_az

  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.db_deletion_protection
  skip_final_snapshot   = var.db_skip_final_snapshot

  # isolated data 서브넷만 사용 (외부 기본 경로 없음)
  subnet_ids         = module.network.data_subnet_ids
  security_group_ids = [module.security.rds_sg_id]

  kms_key_id = aws_kms_key.main.arn
}
