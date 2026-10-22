###############################################################################
# 출력값 — 이후 platform / workload / edge 단계에서 사용
###############################################################################

output "account_id" {
  value = local.account_id
}

output "region" {
  value = var.region
}

output "name_prefix" {
  value = local.name_prefix
}

# ── 네트워크 ────────────────────────────────────────────────────────────────
output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "workload_subnet_ids" {
  value = module.network.workload_subnet_ids
}

output "data_subnet_ids" {
  value = module.network.data_subnet_ids
}

output "nat_public_ips" {
  value = module.network.nat_public_ips
}

# ── 보안 그룹 ───────────────────────────────────────────────────────────────
output "alb_sg_id" {
  value = module.security.alb_sg_id
}

output "web_node_sg_id" {
  value = module.security.web_node_sg_id
}

output "app_node_sg_id" {
  value = module.security.app_node_sg_id
}

output "rds_sg_id" {
  value = module.security.rds_sg_id
}

# ── EKS ────────────────────────────────────────────────────────────────────
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "node_group_status" {
  value = module.eks.node_group_status
}

output "addon_versions" {
  value = merge(module.eks.addon_versions, {
    ebs-csi-driver = aws_eks_addon.ebs_csi.addon_version
  })
}

# ── IRSA 역할 ARN ──────────────────────────────────────────────────────────
output "irsa_role_arns" {
  value = {
    lbc                = aws_iam_role.lbc.arn
    ebs_csi            = aws_iam_role.ebs_csi.arn
    cluster_autoscaler = aws_iam_role.cluster_autoscaler.arn
    app                = aws_iam_role.app.arn
    migration          = aws_iam_role.migration.arn
  }
}

# ── ECR ────────────────────────────────────────────────────────────────────
output "ecr_repository_urls" {
  value = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

# ── RDS ────────────────────────────────────────────────────────────────────
output "rds_endpoint" {
  value = module.rds.db_endpoint
}

output "rds_address" {
  value = module.rds.db_address
}

output "rds_port" {
  value = module.rds.db_port
}

output "rds_master_secret_arn" {
  value = module.rds.master_user_secret_arn
}

# ── Secrets ────────────────────────────────────────────────────────────────
output "secret_arns" {
  value = {
    app       = aws_secretsmanager_secret.app.arn
    migration = aws_secretsmanager_secret.migration.arn
    session   = aws_secretsmanager_secret.session.arn
  }
}

# ── DNS ────────────────────────────────────────────────────────────────────
output "route53_zone_id" {
  value = local.zone_id
}

output "route53_name_servers" {
  value = var.create_hosted_zone ? aws_route53_zone.this[0].name_servers : []
}

output "app_fqdn" {
  value = local.app_fqdn
}

# ── 관리 인스턴스 ───────────────────────────────────────────────────────────
output "management_instance_id" {
  value = aws_instance.management.id
}

output "management_instance_private_ip" {
  value = aws_instance.management.private_ip
}

# ── ACM (커스텀 도메인) ─────────────────────────────────────────────────────
output "acm_certificate_arn" {
  value = aws_acm_certificate.app.arn
}

output "acm_certificate_domain" {
  value = aws_acm_certificate.app.domain_name
}

# 가비아 등록기관에서 NS 위임을 마치면 이 CNAME 레코드가 공개 해석되어 검증이 완료된다.
output "acm_validation_records" {
  value = [
    for r in aws_route53_record.app_validation : {
      name  = r.name
      type  = r.type
      value = one(r.records)
    }
  ]
}

# ── WAF (internet-facing ALB 앞단) ─────────────────────────────────────────
output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.alb.arn
}

output "waf_log_group" {
  value = aws_cloudwatch_log_group.waf.name
}
