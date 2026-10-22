###############################################################################
# ECR (설계안 Phase 3-3)
#   private · immutable tag · 암호화 · scan-on-push · lifecycle
###############################################################################
resource "aws_ecr_repository" "this" {
  for_each = toset(var.ecr_repositories)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.main.arn
  }

  tags = {
    Name        = each.value
    Application = "petclinic"
  }
}

# 설계안 Phase 3-3:
# BuildKit/buildx 는 태그가 붙은 manifest index 아래에 untagged 하위 매니페스트를 만든다.
# "태그 없는 이미지 즉시 만료" 규칙은 활성 태그의 하위 참조를 깨뜨릴 수 있으므로
# untagged 는 보수적으로 14일 후 만료하고, 태그된 이미지는 개수 기준으로만 정리한다.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.ecr_untagged_expire_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.ecr_untagged_expire_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.ecr_max_tagged_images} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.ecr_max_tagged_images
        }
        action = { type = "expire" }
      },
    ]
  })
}

# 리포지토리 접근 정책: 계정 내 principal 만 push/pull (교차계정 차단)
resource "aws_ecr_repository_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowAccountAccess"
      Effect = "Allow"
      Principal = {
        AWS = "arn:${local.partition}:iam::${local.account_id}:root"
      }
      Action = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
      ]
    }]
  })
}
