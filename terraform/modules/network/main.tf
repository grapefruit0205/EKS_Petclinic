###############################################################################
# VPC · 서브넷 4계층 · NAT · 라우팅 · VPC endpoint
# 설계안 4.1 (네트워크·보안 설계)
###############################################################################

locals {
  az_count = length(var.azs)

  # EKS 서브넷 검색 태그 (public 서브넷이 internet-facing ALB 대상)
  cluster_tag = { "kubernetes.io/cluster/${var.cluster_name}" = "shared" }

  public_subnet_tags = merge(local.cluster_tag, {
    "kubernetes.io/role/elb" = "1"
    Tier                     = "public"
  })

  private_subnet_tags = merge(local.cluster_tag, {
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

###############################################################################
# 서브넷 (Public / Private workloads / Isolated data)
###############################################################################
resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, local.public_subnet_tags, {
    Name = "${var.name_prefix}-public-${var.azs[count.index]}"
  })
}

resource "aws_subnet" "workload" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.workload_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, local.private_subnet_tags, {
    Name = "${var.name_prefix}-workload-${var.azs[count.index]}"
    Tier = "workload"
  })
}

# Isolated data 서브넷: 인터넷 기본 경로 없음(VPC local 만).
# 실수로 PubliclyAccessible=true 가 되어도 인터넷 경로가 열리지 않게 한다.
resource "aws_subnet" "data" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.data_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-data-${var.azs[count.index]}"
    Tier = "data"
  })
}

###############################################################################
# NAT Gateway
#   regional (기본): 단일 Regional NAT Gateway 가 VPC 의 모든 AZ 를 커버한다.
#     - availability_mode = "regional", subnet_id 대신 vpc_id 로 생성한다.
#     - availability_zone_address 로 AZ↔EIP 를 명시한다 → 자동 확장 OFF, 우리 EIP 만 사용
#       (명시하지 않으면 AWS 가 EIP 를 자동 생성/관리하며 넘긴 allocation_id 를 쓰지 않는다)
#     - EIP 는 AZ 수만큼 만든다
#   zonal: AZ별 NAT Gateway (이전 방식, 참고용)
###############################################################################
locals {
  nat_is_regional = var.nat_gateway_mode == "regional"
  nat_eip_count   = local.nat_is_regional ? var.regional_nat_eip_count : local.az_count
}

resource "aws_eip" "nat" {
  count  = local.nat_eip_count
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-eip-${count.index + 1}"
    Mode = var.nat_gateway_mode
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "regional" {
  count = local.nat_is_regional ? 1 : 0

  availability_mode = "regional"
  vpc_id            = aws_vpc.this.id
  allocation_id     = aws_eip.nat[0].id

  # AZ ↔ EIP 를 명시한다.
  #   지정하지 않으면 AWS 가 EIP 를 자동 생성/관리하며(regional_nat_gateway_auto_mode=enabled)
  #   넘긴 allocation_id 를 쓰지 않는다. 명시하면 자동 확장이 꺼지고 우리 EIP 만 쓴다.
  dynamic "availability_zone_address" {
    for_each = { for i, az in var.azs : az => aws_eip.nat[i].id }
    content {
      availability_zone = availability_zone_address.key
      allocation_ids    = [availability_zone_address.value]
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-regional"
    Mode = "regional"
  })

  # 구 NAT 가 살아 있는 동안 새 NAT 를 먼저 만든다.
  #   (EIP 가 다르므로 공존 가능 → 라우팅 전환 후 구 NAT 를 지운다)
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "zonal" {
  count = local.nat_is_regional ? 0 : local.az_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-${count.index + 1}"
    AZ   = var.azs[count.index]
    Mode = "zonal"
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# 라우팅 테이블
###############################################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private workload: 0.0.0.0/0 → NAT
#   regional 이면 AZ별 route table 이 모두 같은 Regional NAT 를 가리킨다.
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = local.nat_is_regional ? aws_nat_gateway.regional[0].id : aws_nat_gateway.zonal[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-private-${var.azs[count.index]}"
    AZ   = var.azs[count.index]
  })
}

resource "aws_route_table_association" "workload" {
  count = local.az_count

  subnet_id      = aws_subnet.workload[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Isolated data: 외부 기본 경로 없음 (local 라우팅만)
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-data-isolated" })
}

resource "aws_route_table_association" "data" {
  count = local.az_count

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

###############################################################################
# VPC Endpoint
###############################################################################
# S3 Gateway endpoint (무료). ECR 레이어 다운로드를 NAT 대신 VPC 내부로 처리.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.data.id],
  )

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-s3" })
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name_prefix}-vpce-sg"
  description = "Interface VPC endpoint access from VPC"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Return traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-sg" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.workload[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-${each.value}" })
}

###############################################################################
# VPC Flow Logs (선택)
###############################################################################
resource "aws_cloudwatch_log_group" "flow" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name_prefix}/flow-logs"
  retention_in_days = 14

  tags = merge(var.tags, { Name = "${var.name_prefix}-flow-logs" })
}

resource "aws_iam_role" "flow" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name_prefix}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-flow-logs-role" })
}

resource "aws_iam_role_policy" "flow" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name_prefix}-flow-logs-policy"
  role = aws_iam_role.flow[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow[0].arn
  iam_role_arn             = aws_iam_role.flow[0].arn
  max_aggregation_interval = 60

  tags = merge(var.tags, { Name = "${var.name_prefix}-flow-log" })
}
