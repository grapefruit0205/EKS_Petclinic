###############################################################################
# IAM — EKS 클러스터 / 노드 (설계안 4.3)
#   노드 역할에는 App DB 비밀 읽기 권한을 주지 않는다.
###############################################################################

# ── EKS control plane role ──────────────────────────────────────────────────
resource "aws_iam_role" "eks_cluster" {
  name = "${local.name_prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-eks-cluster-role" }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_vpc_controller" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSVPCResourceController"
}

# ── 노드 role ───────────────────────────────────────────────────────────────
resource "aws_iam_role" "eks_node" {
  name = "${local.name_prefix}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-eks-node-role" }
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# SSM 관리(세션 매니저)로 노드/관리 인스턴스에 접근하기 위한 최소 관리 권한
resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ── 관리 EC2 용 instance profile (SSM 전용, VPC 내부 운영 경로) ─────────────
resource "aws_iam_role" "management" {
  name = "${local.name_prefix}-management-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-management-role" }
}

resource "aws_iam_role_policy_attachment" "management_ssm" {
  role       = aws_iam_role.management.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "management_ecr" {
  role       = aws_iam_role.management.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "management_eks" {
  role       = aws_iam_role.management.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_instance_profile" "management" {
  name = "${local.name_prefix}-management-profile"
  role = aws_iam_role.management.name

  tags = { Name = "${local.name_prefix}-management-profile" }
}

# ── 관리 runner: DB 부트스트랩용 Secret 읽기 (Phase 4 승인된 내부 관리 경로) ──
resource "aws_iam_policy" "management_secrets" {
  name        = "${local.name_prefix}-management-secrets-policy"
  description = "Allow the admin runner to read DB bootstrap secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          module.rds.master_user_secret_arn,
          aws_secretsmanager_secret.app.arn,
          aws_secretsmanager_secret.migration.arn,
          aws_secretsmanager_secret.session.arn,
        ]
      },
      {
        # RDS 관리형 master Secret 은 AWS 관리형 키를 사용한다.
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = "*"
      },
    ]
  })

  tags = { Name = "${local.name_prefix}-management-secrets-policy" }
}

resource "aws_iam_role_policy_attachment" "management_secrets" {
  role       = aws_iam_role.management.name
  policy_arn = aws_iam_policy.management_secrets.arn
}
