###############################################################################
# VPC Link V2 (설계안 6.2)
#   - ingress 서브넷 2개(AZ별), sg-vpclink 사용
#   - 생성 후 subnet/SG 변경 불가 → 변경 시 교체 필요
###############################################################################
resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.name_prefix}-vpclink"
  subnet_ids         = local.foundation.ingress_subnet_ids
  security_group_ids = [local.foundation.vpclink_sg_id]

  tags = {
    Name = "${var.name_prefix}-vpclink"
  }
}

###############################################################################
# HTTP API (Regional, public endpoint)
###############################################################################
resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.name_prefix}/access"
  retention_in_days = var.log_retention_days

  tags = { Name = "${var.name_prefix}-api-access-logs" }
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name_prefix}-http-api"
  protocol_type = "HTTP"

  description = "Petclinic external entrypoint -> VPC Link -> internal ALB -> Web -> App -> RDS"

  # 같은 도메인 사용이므로 CORS 는 열지 않는다(설계안 6.3).
  tags = {
    Name = "${var.name_prefix}-http-api"
  }
}

resource "aws_apigatewayv2_integration" "alb" {
  api_id = aws_apigatewayv2_api.this.id

  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"

  # DNS 주소/ClusterIP 가 아니라 ALB listener ARN 을 지정한다.
  integration_uri = var.alb_listener_arn

  connection_type = "VPC_LINK"
  connection_id   = aws_apigatewayv2_vpc_link.this.id

  payload_format_version = "1.0"
  timeout_milliseconds   = var.integration_timeout_ms
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      routeKey           = "$context.routeKey"
      status             = "$context.status"
      integrationLatency = "$context.integrationLatency"
      responseLatency    = "$context.responseLatency"
      integrationStatus  = "$context.integrationStatus"
      errorMessage       = "$context.error.message"
      sourceIp           = "$context.identity.sourceIp"
      # 인증 토큰·본문은 기록하지 않는다.
    })
  }

  tags = { Name = "${var.name_prefix}-default-stage" }
}

###############################################################################
# 커스텀 도메인 (ACM ISSUED + Route53 NS 위임 이후에만)
###############################################################################
resource "aws_apigatewayv2_domain_name" "this" {
  count = var.custom_domain_enabled ? 1 : 0

  domain_name = local.foundation.app_fqdn

  domain_name_configuration {
    certificate_arn = var.acm_certificate_arn != "" ? var.acm_certificate_arn : local.foundation.acm_certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = { Name = local.foundation.app_fqdn }
}

resource "aws_apigatewayv2_api_mapping" "this" {
  count = var.custom_domain_enabled ? 1 : 0

  api_id          = aws_apigatewayv2_api.this.id
  domain_name     = aws_apigatewayv2_domain_name.this[0].id
  stage           = aws_apigatewayv2_stage.default.id
  api_mapping_key = ""
}

resource "aws_route53_record" "app" {
  count = var.custom_domain_enabled ? 1 : 0

  zone_id = local.foundation.route53_zone_id
  name    = local.foundation.app_fqdn
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
