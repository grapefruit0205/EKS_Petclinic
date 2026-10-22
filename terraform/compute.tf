###############################################################################
# 관리 인스턴스 (SSM 전용, VPC 내부 운영 경로)
#   설계안 4.1: private EKS API 는 VPN 또는 private 관리 EC2 의 SSM 으로 접근
#   public IP 없음 · SSH 키 없음 · 인바운드 규칙 없음
###############################################################################
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "management" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.management_instance_type
  subnet_id              = module.network.workload_subnet_ids[0]
  vpc_security_group_ids = [module.security.management_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.management.name

  # public IP 미할당, SSH 키 없음 (SSM Session Manager 사용)
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/management-userdata.sh.tftpl", {
    region       = var.region
    cluster_name = var.cluster_name
    ecr_registry = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  })

  tags = {
    Name = "${local.name_prefix}-management"
    Role = "admin"
  }

  depends_on = [
    aws_iam_role_policy_attachment.management_ssm,
    module.network,
    module.eks,
  ]
}
