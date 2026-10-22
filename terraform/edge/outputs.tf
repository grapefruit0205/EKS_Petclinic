output "api_id" {
  value = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.this.api_endpoint
}

output "default_stage_url" {
  value = "${aws_apigatewayv2_api.this.api_endpoint}/"
}

output "vpc_link_id" {
  value = aws_apigatewayv2_vpc_link.this.id
}

output "vpc_link_status" {
  value = aws_apigatewayv2_vpc_link.this.security_group_ids
}

output "integration_id" {
  value = aws_apigatewayv2_integration.alb.id
}

output "custom_domain_target" {
  value = var.custom_domain_enabled ? aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name : null
}
