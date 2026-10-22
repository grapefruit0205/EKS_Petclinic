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

variable "name_prefix" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "petclinic-dev"
}

variable "alb_listener_arn" {
  description = "AWS Load Balancer Controller 가 만든 internal ALB listener ARN"
  type        = string
}

variable "throttling_rate_limit" {
  description = "steady 요청 제한(req/s)"
  type        = number
  default     = 50
}

variable "throttling_burst_limit" {
  description = "burst 요청 제한"
  type        = number
  default     = 100
}

variable "integration_timeout_ms" {
  description = "integration timeout (HTTP API 최대 30000ms)"
  type        = number
  default     = 29000
}

variable "log_retention_days" {
  description = "access log 보관 일수"
  type        = number
  default     = 14
}
