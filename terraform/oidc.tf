###############################################################################
# IRSA — EKS OIDC provider + 워크로드별 IAM 역할 (설계안 4.3)
#   컨트롤러/앱/마이그레이션 권한을 각각 분리한다.
###############################################################################

locals {
  oidc_issuer       = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn

  app_namespace       = "petclinic-${var.environment}"
  app_service_account = "petclinic-app"
  mig_service_account = "petclinic-migration"

  # IRSA 신뢰 정책 생성 헬퍼
  irsa_conditions = {
    (local.oidc_issuer) = "sts.amazonaws.com"
  }
}

data "tls_certificate" "eks" {
  url = module.eks.cluster_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = module.eks.cluster_oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = { Name = "${var.cluster_name}-oidc" }
}

# ── 공통 신뢰 정책 팩토리 ────────────────────────────────────────────────────
data "aws_iam_policy_document" "irsa_assume" {
  for_each = {
    lbc                = "system:serviceaccount:kube-system:aws-load-balancer-controller"
    ebs_csi            = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
    cluster_autoscaler = "system:serviceaccount:kube-system:cluster-autoscaler"
    app                = "system:serviceaccount:${local.app_namespace}:${local.app_service_account}"
    migration          = "system:serviceaccount:${local.app_namespace}:${local.mig_service_account}"
  }

  statement {
    effect = "Allow"

    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = [each.value]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

###############################################################################
# 1. AWS Load Balancer Controller
###############################################################################
resource "aws_iam_policy" "lbc" {
  name        = "${local.name_prefix}-lbc-policy"
  description = "AWS Load Balancer Controller policy"
  policy      = file("${path.module}/policies/aws-load-balancer-controller-iam-policy.json")

  tags = { Name = "${local.name_prefix}-lbc-policy" }
}

resource "aws_iam_role" "lbc" {
  name               = "${local.name_prefix}-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["lbc"].json

  tags = { Name = "${local.name_prefix}-lbc-role" }
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

###############################################################################
# 2. EBS CSI Driver
###############################################################################
resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["ebs_csi"].json

  tags = { Name = "${local.name_prefix}-ebs-csi-role" }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

###############################################################################
# 3. Cluster Autoscaler
###############################################################################
data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${local.name_prefix}-cluster-autoscaler-policy"
  description = "Cluster Autoscaler policy (scoped to this cluster tag)"
  policy      = data.aws_iam_policy_document.cluster_autoscaler.json

  tags = { Name = "${local.name_prefix}-cluster-autoscaler-policy" }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${local.name_prefix}-cluster-autoscaler-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["cluster_autoscaler"].json

  tags = { Name = "${local.name_prefix}-cluster-autoscaler-role" }
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

###############################################################################
# 4. App / Migration — Secrets Manager 읽기 전용 (DB 비밀)
###############################################################################
data "aws_iam_policy_document" "app_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      aws_secretsmanager_secret.app.arn,
      aws_secretsmanager_secret.session.arn,
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.main.arn]
  }
}

data "aws_iam_policy_document" "migration_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.migration.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_policy" "app_secrets" {
  name        = "${local.name_prefix}-app-secrets-policy"
  description = "Read app runtime secrets"
  policy      = data.aws_iam_policy_document.app_secrets.json

  tags = { Name = "${local.name_prefix}-app-secrets-policy" }
}

resource "aws_iam_policy" "migration_secrets" {
  name        = "${local.name_prefix}-migration-secrets-policy"
  description = "Read migration secrets"
  policy      = data.aws_iam_policy_document.migration_secrets.json

  tags = { Name = "${local.name_prefix}-migration-secrets-policy" }
}

resource "aws_iam_role" "app" {
  name               = "${local.name_prefix}-app-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["app"].json

  tags = { Name = "${local.name_prefix}-app-role" }
}

resource "aws_iam_role_policy_attachment" "app_secrets" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app_secrets.arn
}

resource "aws_iam_role" "migration" {
  name               = "${local.name_prefix}-migration-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["migration"].json

  tags = { Name = "${local.name_prefix}-migration-role" }
}

resource "aws_iam_role_policy_attachment" "migration_secrets" {
  role       = aws_iam_role.migration.name
  policy_arn = aws_iam_policy.migration_secrets.arn
}
