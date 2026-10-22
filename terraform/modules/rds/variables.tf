variable "name_prefix" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "identifier" {
  description = "DB 인스턴스 식별자"
  type        = string
}

variable "db_name" {
  description = "초기 데이터베이스 이름"
  type        = string
}

variable "master_username" {
  description = "마스터 사용자 이름"
  type        = string
}

variable "instance_class" {
  description = "인스턴스 클래스"
  type        = string
}

variable "engine_version" {
  description = "MySQL 엔진 버전"
  type        = string
}

variable "parameter_group_family" {
  description = "파라미터 그룹 패밀리"
  type        = string
  default     = "mysql8.4"
}

variable "allocated_storage" {
  description = "할당 스토리지(GiB)"
  type        = number
}

variable "max_allocated_storage" {
  description = "자동 확장 상한(GiB)"
  type        = number
}

variable "multi_az" {
  description = "Multi-AZ"
  type        = bool
}

variable "backup_retention_days" {
  description = "자동 백업 보관 일수"
  type        = number
}

variable "deletion_protection" {
  description = "삭제 보호"
  type        = bool
}

variable "skip_final_snapshot" {
  description = "최종 스냅샷 생략"
  type        = bool
}

variable "subnet_ids" {
  description = "DB 서브넷 그룹에 넣을 isolated data 서브넷"
  type        = list(string)
}

variable "security_group_ids" {
  description = "RDS SG"
  type        = list(string)
}

variable "ca_cert_identifier" {
  description = "RDS CA 인증서 식별자 (JDBC TLS 검증)"
  type        = string
  default     = "rds-ca-rsa2048-g1"
}

variable "performance_insights_enabled" {
  description = "Performance Insights"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring 간격(초). 0 이면 비활성"
  type        = number
  default     = 60
}

variable "kms_key_id" {
  description = "스토리지 암호화 KMS key (선택)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "추가 태그"
  type        = map(string)
  default     = {}
}
