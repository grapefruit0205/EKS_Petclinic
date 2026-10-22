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
# edge stack (설계안 7.2: Terraform edge)
#   foundation 출력값을 읽어 VPC Link V2 + API Gateway HTTP API 를 구성한다.
#   ALB/listener 는 AWS Load Balancer Controller 가 소유하므로 여기서 만들지 않고
#   입력값(listener ARN)으로만 연결한다. (동일 리소스 이중 소유 금지)
###############################################################################
