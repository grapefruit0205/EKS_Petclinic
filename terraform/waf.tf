###############################################################################
# AWS WAF (설계안 4.4 / Phase 7)
#   - Regional WebACL 을 internet-facing ALB 에 연결한다.
#   - 연결(association)은 Ingress annotation
#       alb.ingress.kubernetes.io/wafv2-acl-arn
#     으로 AWS Load Balancer Controller 가 수행한다.
#     => ALB 는 LBC 소유, WebACL 은 Terraform 소유로 분리(이중 소유 금지).
#   - 관리형 규칙은 오탐 가능성이 있으므로 초기에는 count 모드 관측을 권장한다.
###############################################################################

resource "aws_wafv2_web_acl" "alb" {
  name        = "${local.name_prefix}-alb-waf"
  description = "WAF for the internet-facing ALB (petclinic 3-tier)"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # 1) AWS 관리형 공통 규칙 (XSS, LFI, 프로토콜 위반 등)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rule-set"
      sampled_requests_enabled   = false
    }
  }

  # 2) SQL 인젝션
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "sqli-rule-set"
      sampled_requests_enabled   = false
    }
  }

  # 3) 알려진 악성 입력
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "known-bad-inputs"
      sampled_requests_enabled   = false
    }
  }

  # 4) IP 기반 과다 요청 차단 (5분 윈도우)
  rule {
    name     = "RateLimitPerIp"
    priority = 40

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = false
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-alb-waf"
    sampled_requests_enabled   = false
  }

  tags = { Name = "${local.name_prefix}-alb-waf" }
}

###############################################################################
# WAF 로그 (CloudWatch Logs)
#   로그 그룹 이름은 반드시 `aws-waf-logs-` 로 시작해야 한다.
#   본문은 수집하지 않고, 쿠키 등 민감 필드는 redacted_fields 로 제거한다.
###############################################################################
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${local.name_prefix}"
  retention_in_days = var.waf_log_retention_days

  tags = { Name = "${local.name_prefix}-waf-logs" }
}

resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  resource_arn            = aws_wafv2_web_acl.alb.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }

      condition {
        action_condition {
          action = "COUNT"
        }
      }
    }
  }
}
