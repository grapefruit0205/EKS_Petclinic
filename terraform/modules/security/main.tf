###############################################################################
# 보안 그룹 (설계안 4.2)
#   인터넷(0.0.0.0/0) -> sg-alb   : TCP 443 (WAF 경유), TCP 80 -> 443 리다이렉트
#   sg-alb     -> sg-web-node      : TCP 8080(업무), 8081(health)
#   sg-web-node-> sg-app-node      : TCP 8080
#   sg-app-node-> sg-rds           : TCP 3306
#   node <-> control plane         : 클러스터 통신 (업무 흐름표와 별개로 유지)
###############################################################################

# ── EKS control plane 추가 SG ────────────────────────────────────────────────
resource "aws_security_group" "cluster" {
  name        = "${var.name_prefix}-eks-cluster-sg"
  description = "EKS control plane additional security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-eks-cluster-sg" })
}

# ── 노드 SG: web-system / app 분리 ──────────────────────────────────────────
resource "aws_security_group" "web_node" {
  name        = "${var.name_prefix}-web-node-sg"
  description = "EKS web-system node group security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-web-node-sg"
    Tier = "web"
  })
}

resource "aws_security_group" "app_node" {
  name        = "${var.name_prefix}-app-node-sg"
  description = "EKS app node group security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-app-node-sg"
    Tier = "app"
  })
}

# ── internet-facing ALB SG ──────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Internet-facing ALB security group (WAF attached)"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-sg" })
}

# ── RDS SG ──────────────────────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "RDS MySQL security group (app nodes only)"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-sg" })
}

# ── 관리용(SSM) SG ──────────────────────────────────────────────────────────
resource "aws_security_group" "management" {
  name        = "${var.name_prefix}-management-sg"
  description = "SSM-managed admin/bastion security group (no inbound)"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-management-sg" })
}

###############################################################################
# 규칙
###############################################################################

# sg-alb -> sg-web-node : 8080 / 8081
resource "aws_vpc_security_group_ingress_rule" "web_node_from_alb_8080" {
  security_group_id            = aws_security_group.web_node.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  description                  = "Web app traffic from internal ALB"
}

resource "aws_vpc_security_group_ingress_rule" "web_node_from_alb_8081" {
  security_group_id            = aws_security_group.web_node.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8081
  to_port                      = 8081
  ip_protocol                  = "tcp"
  description                  = "Web health listener from internal ALB"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_web_node" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.web_node.id
  from_port                    = 8080
  to_port                      = 8081
  ip_protocol                  = "tcp"
  description                  = "To web workload targets"
}

# web-node -> app-node : 8080
resource "aws_vpc_security_group_ingress_rule" "app_node_from_web_node" {
  security_group_id            = aws_security_group.app_node.id
  referenced_security_group_id = aws_security_group.web_node.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  description                  = "Nginx to app-svc"
}

resource "aws_vpc_security_group_egress_rule" "web_node_to_app_node" {
  security_group_id            = aws_security_group.web_node.id
  referenced_security_group_id = aws_security_group.app_node.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  description                  = "Nginx upstream to app"
}

# app-node -> rds : 3306
resource "aws_vpc_security_group_ingress_rule" "rds_from_app_node" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.app_node.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  description                  = "MySQL from app nodes only"
}

resource "aws_vpc_security_group_egress_rule" "app_node_to_rds" {
  security_group_id            = aws_security_group.app_node.id
  referenced_security_group_id = aws_security_group.rds.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  description                  = "JDBC to RDS"
}

# 노드 <-> control plane (EKS 필수 통신, 업무 흐름표와 별개)
resource "aws_vpc_security_group_ingress_rule" "cluster_from_nodes" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.web_node.id
  ip_protocol                  = "-1"
  description                  = "Node to control plane"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_app_nodes" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.app_node.id
  ip_protocol                  = "-1"
  description                  = "Node to control plane"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_self" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "-1"
  description                  = "Control plane self"
}

resource "aws_vpc_security_group_egress_rule" "cluster_all" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Control plane egress"
}

resource "aws_vpc_security_group_ingress_rule" "web_node_from_cluster" {
  security_group_id            = aws_security_group.web_node.id
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "-1"
  description                  = "Control plane to kubelet"
}

resource "aws_vpc_security_group_ingress_rule" "web_node_self" {
  security_group_id            = aws_security_group.web_node.id
  referenced_security_group_id = aws_security_group.web_node.id
  ip_protocol                  = "-1"
  description                  = "Node to node (CNI, DNS, webhook)"
}

resource "aws_vpc_security_group_egress_rule" "web_node_all" {
  security_group_id = aws_security_group.web_node.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Node egress (NAT/endpoint)"
}

resource "aws_vpc_security_group_ingress_rule" "app_node_from_cluster" {
  security_group_id            = aws_security_group.app_node.id
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "-1"
  description                  = "Control plane to kubelet"
}

resource "aws_vpc_security_group_ingress_rule" "app_node_self" {
  security_group_id            = aws_security_group.app_node.id
  referenced_security_group_id = aws_security_group.app_node.id
  ip_protocol                  = "-1"
  description                  = "Node to node (CNI, DNS, webhook)"
}

resource "aws_vpc_security_group_egress_rule" "app_node_all" {
  security_group_id = aws_security_group.app_node.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Node egress (NAT/endpoint)"
}

# ALB egress: health check / target 로만 나가면 충분하지만 ALB 는 노드 SG 로 제한한다.
# 관리 SG: 아웃바운드 전체 (SSM/ECR 등), 인바운드 없음
resource "aws_vpc_security_group_egress_rule" "management_all" {
  security_group_id = aws_security_group.management.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Admin egress (SSM endpoints / NAT)"
}

# 관리 경로 -> EKS API (설계안 4.2 표: 관리 경로 -> EKS API TCP 443)
resource "aws_vpc_security_group_ingress_rule" "cluster_from_management" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.management.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Admin path to EKS API"
}

# 관리 runner -> RDS 3306 (설계안 Phase 4: 승인된 VPC 내부 관리 runner 의 DB bootstrap/TLS 검증)
resource "aws_vpc_security_group_ingress_rule" "rds_from_management" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.management.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  description                  = "MySQL bootstrap from admin runner"
}

# ── 인터넷 -> internet-facing ALB ───────────────────────────────────────────
# WAF는 SG 계층이 아니라 ALB 앞단에서 요청을 검사한다. SG는 포트/대역만 다룬다.
resource "aws_vpc_security_group_ingress_rule" "alb_from_internet_443" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from internet (via AWS WAF)"
}

# HTTP 80 은 ALB 리스너에서 443 으로 리다이렉트하기 위해 연다.
resource "aws_vpc_security_group_ingress_rule" "alb_from_internet_80" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from internet (redirect to 443)"
}
