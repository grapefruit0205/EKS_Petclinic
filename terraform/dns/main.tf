###############################################################################
# Route 53 A(alias) → internet-facing ALB
#   ALB 는 Ingress 를 통해 LBC 가 생성한 것을 조회해 사용한다.
###############################################################################
resource "aws_route53_record" "app" {
  zone_id = local.foundation.route53_zone_id
  name    = local.foundation.app_fqdn
  type    = "A"

  alias {
    name                   = data.aws_lb.this.dns_name
    zone_id                = data.aws_lb.this.zone_id
    evaluate_target_health = false
  }
}
