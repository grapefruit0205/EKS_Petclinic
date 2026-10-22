terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

###############################################################################
# dns stack (v2)
#   Ingress 가 만든 internet-facing ALB 를 조회해 Route 53 A(alias) 레코드를 만든다.
#   ALB 는 AWS Load Balancer Controller 가 소유하므로 여기서 만들지 않고 조회만 한다.
#   => kubectl apply -f k8s/30-ingress.yaml 로 ALB 가 생긴 뒤에 apply 한다.
###############################################################################
