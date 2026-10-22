variable "name_prefix" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes 버전"
  type        = string
}

variable "cluster_role_arn" {
  description = "EKS control plane IAM role ARN"
  type        = string
}

variable "node_role_arn" {
  description = "EKS 노드 IAM role ARN"
  type        = string
}

variable "subnet_ids" {
  description = "EKS 노드/ENI 를 배치할 private workload 서브넷"
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "control plane 추가 SG"
  type        = string
}

variable "node_group_security_group_ids" {
  description = "노드그룹 이름 -> 추가 SG ID 매핑"
  type        = map(string)
  default     = {}
}

variable "endpoint_public_access" {
  description = "EKS API 퍼블릭 엔드포인트 허용"
  type        = bool
}

variable "endpoint_public_access_cidrs" {
  description = "퍼블릭 엔드포인트 허용 CIDR"
  type        = list(string)
}

variable "node_instance_type" {
  description = "노드 인스턴스 타입"
  type        = string
}

variable "node_groups" {
  description = "관리형 노드그룹 정의"
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
}

variable "kms_key_arn" {
  description = "Secrets envelope encryption KMS key ARN (선택)"
  type        = string
  default     = ""
}

variable "enabled_cluster_log_types" {
  description = "control plane 로그 유형"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "tags" {
  description = "추가 태그"
  type        = map(string)
  default     = {}
}
