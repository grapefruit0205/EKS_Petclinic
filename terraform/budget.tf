###############################################################################
# AWS Budgets (설계안 Phase 3-5, 10.1)
#   알림은 자동 비용 상한이 아니다.
###############################################################################
locals {
  # for_each 는 문자열 set 이어야 하므로 변환한다.
  budget_thresholds = toset([for t in var.budget_notification_thresholds : tostring(t)])
}

resource "aws_budgets_budget" "this" {
  name         = "${local.name_prefix}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # 형식: user:<TagKey>$<TagValue>
  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Project$%s", var.project)]
  }

  dynamic "notification" {
    for_each = length(var.budget_alert_emails) > 0 ? local.budget_thresholds : []

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = tonumber(notification.value)
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.budget_alert_emails
    }
  }

  dynamic "notification" {
    for_each = length(var.budget_alert_emails) > 0 ? local.budget_thresholds : []

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = tonumber(notification.value)
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = var.budget_alert_emails
    }
  }
}
