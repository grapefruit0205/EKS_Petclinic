provider "aws" {
  region = var.region

  # 모든 리소스에 공통 태그를 강제 적용한다.
  # 개별 리소스에서 추가 태그를 지정하면 병합된다.
  default_tags {
    tags = local.common_tags
  }
}

# ACM/CloudFront 계열을 쓰지 않으므로 us-east-1 별칭 provider 는 두지 않는다.
# API Gateway(Regional) 커스텀 도메인 인증서는 ap-northeast-2 에 생성한다.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
