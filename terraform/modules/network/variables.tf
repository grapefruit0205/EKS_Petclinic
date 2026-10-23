variable "name_prefix" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "region" {
  description = "리전 (endpoint 서비스 이름 구성)"
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 (서브넷 검색 태그)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "azs" {
  description = "가용영역 목록"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public 서브넷 CIDR"
  type        = list(string)
}

variable "workload_subnet_cidrs" {
  description = "Private workloads 서브넷 CIDR"
  type        = list(string)
}

variable "data_subnet_cidrs" {
  description = "Isolated data 서브넷 CIDR"
  type        = list(string)
}

variable "nat_gateway_mode" {
  description = "NAT 방식: regional = 단일 Regional NAT Gateway (VPC 전체 AZ 커버·AZ 자동 확장) / zonal = AZ별 NAT"
  type        = string
  default     = "regional"

  validation {
    condition     = contains(["regional", "zonal"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode 는 regional 또는 zonal 이어야 합니다."
  }
}

variable "regional_nat_eip_count" {
  description = "regional NAT 에 연결할 EIP 개수 (AZ 수와 맞추면 AZ별 EIP 1개)"
  type        = number
  default     = 2
}

variable "interface_endpoints" {
  description = "interface VPC endpoint 서비스 접미사 목록"
  type        = list(string)
}

variable "enable_flow_logs" {
  description = "VPC Flow Logs 생성"
  type        = bool
}

variable "tags" {
  description = "추가 태그"
  type        = map(string)
  default     = {}
}
