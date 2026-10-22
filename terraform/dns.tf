###############################################################################
# DNS / ACM (설계안 Phase 7-4)
#
# 현재 상태 진단(2026-10-22):
#   .site TLD 위임 → ns-42.awsdns-05.com / ns-931.awsdns-52.net /
#                    ns-1489.awsdns-58.org / ns-1909.awsdns-46.co.uk
#   위 Route53 존은 더 이상 존재하지 않아 권한 서버가 REFUSED, 재귀 조회는 SERVFAIL.
#   => 도메인이 현재 전혀 해석되지 않는다. 등록기관(가비아)에서 NS 를
#      이 스택이 만든 존의 NS 로 교체해야 한다.
#
# ACM 인증서는 항상 생성한다(무료). 검증 "대기"만 enable_custom_domain 으로 제어해
# NS 위임 전에도 apply 가 막히지 않게 한다.
###############################################################################

resource "aws_route53_zone" "this" {
  count = var.create_hosted_zone ? 1 : 0

  name    = var.domain_name
  comment = "${local.name_prefix} hosted zone"

  tags = { Name = var.domain_name }
}

locals {
  zone_id = var.create_hosted_zone ? aws_route53_zone.this[0].zone_id : var.hosted_zone_id
}

# ── ACM 인증서 (항상 생성) ──────────────────────────────────────────────────
resource "aws_acm_certificate" "app" {
  domain_name       = local.app_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = local.app_fqdn }
}

# NS 위임 후 이 레코드가 공개 해석되어 ACM 검증이 완료된다.
resource "aws_route53_record" "app_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# 검증 완료 대기: NS 위임 후 enable_custom_domain=true 로 전환할 때 수행한다.
resource "aws_acm_certificate_validation" "app" {
  count = var.enable_custom_domain ? 1 : 0

  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for r in aws_route53_record.app_validation : r.fqdn]
}
