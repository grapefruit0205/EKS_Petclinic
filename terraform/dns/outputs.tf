output "app_fqdn" {
  value = local.foundation.app_fqdn
}

output "alb_dns_name" {
  value = data.aws_lb.this.dns_name
}

output "alb_arn" {
  value = data.aws_lb.this.arn
}

output "alb_scheme" {
  value = data.aws_lb.this.internal ? "internal" : "internet-facing"
}
