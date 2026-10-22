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

variable "ingress_subnet_cidrs" {
  description = "Private ingress 서브넷 CIDR"
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

variable "single_nat_gateway" {
  description = "NAT 1개만 생성"
  type        = bool
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
