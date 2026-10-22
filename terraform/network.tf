###############################################################################
# 네트워크 (설계안 4.1)
###############################################################################
module "network" {
  source = "./modules/network"

  name_prefix  = local.name_prefix
  region       = var.region
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  azs          = var.azs

  public_subnet_cidrs   = var.public_subnet_cidrs
  ingress_subnet_cidrs  = var.ingress_subnet_cidrs
  workload_subnet_cidrs = var.workload_subnet_cidrs
  data_subnet_cidrs     = var.data_subnet_cidrs

  single_nat_gateway  = var.single_nat_gateway
  interface_endpoints = var.interface_endpoints
  enable_flow_logs    = var.enable_flow_logs
}
