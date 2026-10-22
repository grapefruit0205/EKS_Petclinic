variable "custom_domain_enabled" {
  description = "커스텀 도메인 매핑 활성화 (ACM ISSUED + NS 위임 이후)"
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "커스텀 도메인용 ACM 인증서 ARN (ap-northeast-2)"
  type        = string
  default     = ""
}
