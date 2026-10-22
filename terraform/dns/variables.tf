variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "비용 태그 Project"
  type        = string
  default     = "petclinic-3tier"
}

variable "environment" {
  description = "비용 태그 Environment"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "비용 태그 Owner"
  type        = string
  default     = "kdt5"
}

variable "expires_at" {
  description = "비용 태그 ExpiresAt"
  type        = string
  default     = "2026-11-05"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 (LBC 가 ALB 에 붙이는 태그 조회용)"
  type        = string
  default     = "petclinic-dev"
}

variable "ingress_group" {
  description = "Ingress group.name 값 (LBC 태그 ingress.k8s.aws/stack)"
  type        = string
  default     = "petclinic"
}
