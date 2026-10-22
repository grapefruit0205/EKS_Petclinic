###############################################################################
# 공통 / 태그
###############################################################################
variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "비용 태그 Project 값"
  type        = string
  default     = "petclinic-3tier"
}

variable "environment" {
  description = "비용 태그 Environment 값"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "비용 태그 Owner 값"
  type        = string
  default     = "kdt5"
}

variable "expires_at" {
  description = "비용 태그 ExpiresAt 값 (정리 예정일)"
  type        = string
  default     = "2026-11-05"
}

variable "name_prefix" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "petclinic"
}

###############################################################################
# 네트워크
###############################################################################
variable "vpc_cidr" {
  description = "VPC CIDR (설계안 4.1)"
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "사용할 가용영역 (2개)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b"]
}

variable "public_subnet_cidrs" {
  description = "Public 서브넷 CIDR (AZ 순서 대응)"
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "ingress_subnet_cidrs" {
  description = "Private ingress 서브넷 CIDR (internal ALB + VPC Link ENI)"
  type        = list(string)
  default     = ["10.20.8.0/24", "10.20.9.0/24"]
}

variable "workload_subnet_cidrs" {
  description = "Private workloads 서브넷 CIDR (EKS 노드/Pod)"
  type        = list(string)
  default     = ["10.20.32.0/20", "10.20.48.0/20"]
}

variable "data_subnet_cidrs" {
  description = "Isolated data 서브넷 CIDR (RDS). 인터넷 기본 경로 없음"
  type        = list(string)
  default     = ["10.20.80.0/24", "10.20.81.0/24"]
}

variable "single_nat_gateway" {
  description = "true 면 NAT 1개(축소 실습안), false 면 AZ별 NAT(운영안)"
  type        = bool
  default     = false
}

variable "interface_endpoints" {
  description = "생성할 interface VPC endpoint 서비스 (필요한 것만)"
  type        = list(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "sts",
    "secretsmanager",
    "logs",
    "eks-auth",
    "ssm",
    "ssmmessages",
    "ec2messages",
  ]
}

variable "enable_flow_logs" {
  description = "VPC Flow Logs 생성 여부 (CloudWatch Logs 비용 발생)"
  type        = bool
  default     = false
}

###############################################################################
# EKS
###############################################################################
variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
  default     = "petclinic-dev"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes 버전 (지원 중인 표준 버전)"
  type        = string
  default     = "1.34"
}

variable "cluster_endpoint_public_access" {
  description = "EKS API 퍼블릭 엔드포인트 허용 여부 (설계안 기본은 private)"
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "퍼블릭 엔드포인트 허용 CIDR (public access 사용 시 필수)"
  type        = list(string)
  default     = []
}

variable "node_instance_type" {
  description = "관리형 노드그룹 인스턴스 타입"
  type        = string
  default     = "m6i.large"
}

variable "node_groups" {
  description = "관리형 노드그룹 정의 (web-system / app 분리, 2 AZ)"
  type = map(object({
    desired_size = number
    min_size     = number
    max_size     = number
    capacity     = string
    disk_size    = number
    labels       = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
  default = {
    web-system = {
      desired_size = 2
      min_size     = 2
      max_size     = 4
      capacity     = "ON_DEMAND"
      disk_size    = 30
      labels       = { tier = "web-system" }
      taints       = []
    }
    app = {
      desired_size = 2
      min_size     = 2
      max_size     = 6
      capacity     = "ON_DEMAND"
      disk_size    = 30
      labels       = { tier = "app" }
      taints       = []
    }
  }
}

###############################################################################
# ECR
###############################################################################
variable "ecr_repositories" {
  description = "생성할 ECR 리포지토리 이름 목록"
  type        = list(string)
  default     = ["petclinic-web", "petclinic-app"]
}

variable "ecr_untagged_expire_days" {
  description = "untagged 이미지 만료 일수 (설계안 3단계: 활성 태그 하위 매니페스트 보호)"
  type        = number
  default     = 14
}

variable "ecr_max_tagged_images" {
  description = "태그된 이미지 최대 보관 개수"
  type        = number
  default     = 30
}

###############################################################################
# RDS
###############################################################################
variable "db_name" {
  description = "초기 데이터베이스 이름"
  type        = string
  default     = "petclinic"
}

variable "db_master_username" {
  description = "RDS 마스터 사용자 이름"
  type        = string
  default     = "petclinicadmin"
}

variable "db_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.m6g.large"
}

variable "db_engine_version" {
  description = "RDS MySQL 엔진 버전 (8.4 계열)"
  type        = string
  default     = "8.4.6"
}

variable "db_allocated_storage" {
  description = "RDS 스토리지 크기(GiB)"
  type        = number
  default     = 100
}

variable "db_max_allocated_storage" {
  description = "RDS 스토리지 자동 확장 상한(GiB)"
  type        = number
  default     = 200
}

variable "db_multi_az" {
  description = "RDS Multi-AZ 여부 (운영안: true)"
  type        = bool
  default     = true
}

variable "db_backup_retention_days" {
  description = "자동 백업 보관 일수 (PITR 구간)"
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "RDS 삭제 보호"
  type        = bool
  default     = true
}

variable "db_skip_final_snapshot" {
  description = "삭제 시 최종 스냅샷 생략 여부 (false 권장)"
  type        = bool
  default     = false
}

###############################################################################
# Cognito
###############################################################################
variable "cognito_domain_prefix" {
  description = "Cognito Hosted UI 도메인 접두사 (전역 유일)"
  type        = string
  default     = ""
}

###############################################################################
# 도메인 / DNS / ACM
###############################################################################
variable "domain_name" {
  description = "소유 도메인 (예: mission-critical.site)"
  type        = string
  default     = "mission-critical.site"
}

variable "app_subdomain" {
  description = "애플리케이션 서브도메인 접두사 (clinic.example.com 의 clinic)"
  type        = string
  default     = "clinic"
}

variable "create_hosted_zone" {
  description = "Route53 호스티드 존 생성 여부 (등록기관 NS 위임 필요)"
  type        = bool
  default     = true
}

variable "hosted_zone_id" {
  description = "기존 Route53 호스티드 존 ID (create_hosted_zone=false 일 때)"
  type        = string
  default     = ""
}

variable "enable_custom_domain" {
  description = "API Gateway 커스텀 도메인 연결 여부 (ACM ISSUED 이후 true)"
  type        = bool
  default     = false
}

###############################################################################
# 예산
###############################################################################
variable "budget_limit_usd" {
  description = "월 예산 한도(USD)"
  type        = number
  default     = 500
}

variable "budget_alert_emails" {
  description = "예산 알림 수신 이메일"
  type        = list(string)
  default     = []
}
variable "management_instance_type" {
  description = "SSM 관리 인스턴스 타입 (VPC 내부 운영 경로)"
  type        = string
  default     = "t3.small"
}

variable "github_repo" {
  description = "GitHub OIDC CI 를 허용할 저장소 (owner/repo). 빈 값이면 CI 역할을 만들지 않는다"
  type        = string
  default     = ""
}

variable "budget_notification_thresholds" {
  description = "예산 알림 임계 비율(%)"
  type        = list(number)
  default     = [50, 80, 100]
}
