###############################################################################
# Amazon EKS (설계안 Phase 5)
#   - private API endpoint 기본
#   - Managed Node Group: web-system / app 분리, 2 AZ
#   - EKS Auto Mode 사용하지 않음
#   - VPC CNI NetworkPolicy 활성화
###############################################################################

locals {
  # 노드그룹 이름 -> SG
  node_sg = var.node_group_security_group_ids

  cluster_log_group = "/aws/eks/${var.cluster_name}/cluster"
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = local.cluster_log_group
  retention_in_days = 14

  tags = merge(var.tags, { Name = "${var.cluster_name}-control-plane-logs" })
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  enabled_cluster_log_types = var.enabled_cluster_log_types

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.cluster_security_group_id]
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = true
    public_access_cidrs     = var.endpoint_public_access ? var.endpoint_public_access_cidrs : null
  }

  dynamic "encryption_config" {
    for_each = var.kms_key_arn != "" ? [1] : []
    content {
      provider {
        key_arn = var.kms_key_arn
      }
      resources = ["secrets"]
    }
  }

  tags = merge(var.tags, { Name = var.cluster_name })

  depends_on = [aws_cloudwatch_log_group.cluster]
}

###############################################################################
# 노드그룹 (Managed Node Group)
###############################################################################
# 노드 추가 SG 를 붙이기 위해 launch template 을 사용한다.
# user_data 는 지정하지 않아 EKS 기본 bootstrap 을 그대로 사용한다.
resource "aws_launch_template" "node" {
  for_each = var.node_groups

  name_prefix = "${var.name_prefix}-${each.key}-"

  # 계층별 노드 SG + EKS 관리형 cluster SG (control plane <-> kubelet 통신 보장)
  vpc_security_group_ids = lookup(local.node_sg, each.key, null) != null ? [
    local.node_sg[each.key],
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
  ] : null

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 강제
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = each.value.disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.name_prefix}-${each.key}"
      Tier = each.key
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.name_prefix}-${each.key}"
    })
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}-lt" })
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.node_instance_type]
  capacity_type   = each.value.capacity
  ami_type        = "AL2023_x86_64_STANDARD"

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${each.key}"
    Tier = each.key
  })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_eks_cluster.this, aws_eks_addon.vpc_cni]
}

###############################################################################
# 핵심 addon
#   addon_version 을 지정하지 않으면 해당 Kubernetes 버전의 최신 호환 버전이 선택된다.
#   운영 전환 시 조회한 버전을 명시적으로 고정한다(설계안 Phase 5 버전 잠금).
###############################################################################
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  # 설계안 4.2: VPC CNI NetworkPolicy 지원 활성화
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(var.tags, { Name = "${var.cluster_name}-vpc-cni" })

  depends_on = [aws_eks_cluster.this]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(var.tags, { Name = "${var.cluster_name}-kube-proxy" })

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(var.tags, { Name = "${var.cluster_name}-coredns" })

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(var.tags, { Name = "${var.cluster_name}-pod-identity-agent" })

  depends_on = [aws_eks_node_group.this]
}
