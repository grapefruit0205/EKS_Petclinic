###############################################################################
# 보안 그룹 (설계안 4.2)
###############################################################################
module "security" {
  source = "./modules/security"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
  vpc_cidr    = var.vpc_cidr
}
