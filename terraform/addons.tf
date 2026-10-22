###############################################################################
# EKS 관리형 addon — EBS CSI Driver (IRSA 역할 필요하므로 root 에서 생성)
###############################################################################
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = { Name = "${var.cluster_name}-ebs-csi-driver" }

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi,
    module.eks,
  ]
}
