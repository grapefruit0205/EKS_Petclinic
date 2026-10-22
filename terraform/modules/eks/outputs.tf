output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_arn" {
  value = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  value = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "node_group_arns" {
  value = { for k, v in aws_eks_node_group.this : k => v.arn }
}

output "node_group_status" {
  value = { for k, v in aws_eks_node_group.this : k => v.status }
}

output "addon_versions" {
  value = {
    vpc-cni                = aws_eks_addon.vpc_cni.addon_version
    kube-proxy             = aws_eks_addon.kube_proxy.addon_version
    coredns                = aws_eks_addon.coredns.addon_version
    eks-pod-identity-agent = aws_eks_addon.pod_identity_agent.addon_version
  }
}
