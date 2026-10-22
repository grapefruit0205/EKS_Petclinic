terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # 로컬 state 를 기본으로 사용한다. 운영 전환 시 S3 + DynamoDB 잠금으로 이전한다.
  # (설계안 7.2: state 암호화·접근 제한·잠금·버전 보관)
  backend "local" {
    path = "terraform.tfstate"
  }
}
