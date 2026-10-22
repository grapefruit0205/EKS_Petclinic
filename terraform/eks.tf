###############################################################################
# Amazon EKS (설계안 Phase 5)
###############################################################################
module "eks" {
  source = "./modules/eks"

  name_prefix        = local.name_prefix
  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version

  cluster_role_arn = aws_iam_role.eks_cluster.arn
  node_role_arn    = aws_iam_role.eks_node.arn

  # 노드/ENI 는 private workload 서브넷에만 배치한다.
  subnet_ids                = module.network.workload_subnet_ids
  cluster_security_group_id = module.security.cluster_sg_id

  # web-system / app 노드그룹을 별도 SG 로 격리 (설계안 4.2)
  node_group_security_group_ids = {
    web-system = module.security.web_node_sg_id
    app        = module.security.app_node_sg_id
  }

  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  node_instance_type = var.node_instance_type
  node_groups        = var.node_groups

  kms_key_arn = aws_kms_key.main.arn
}
