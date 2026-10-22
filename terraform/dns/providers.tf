provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

data "terraform_remote_state" "foundation" {
  backend = "local"

  config = {
    path = "${path.module}/../terraform.tfstate"
  }
}

locals {
  foundation = data.terraform_remote_state.foundation.outputs

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ExpiresAt   = var.expires_at
    ManagedBy   = "terraform"
    Stack       = "dns"
  }
}

###############################################################################
# Ingress(LBC) 가 만든 internet-facing ALB 조회
#   LBC 는 ALB 에 아래 태그를 자동으로 붙인다.
#     elbv2.k8s.aws/cluster = <클러스터 이름>
#     ingress.k8s.aws/stack = <Ingress group.name 또는 namespace/name>
###############################################################################
data "aws_lb" "this" {
  tags = {
    "elbv2.k8s.aws/cluster" = var.cluster_name
    "ingress.k8s.aws/stack" = var.ingress_group
  }
}
