output "db_instance_id" {
  value = aws_db_instance.this.id
}

output "db_instance_arn" {
  value = aws_db_instance.this.arn
}

output "db_endpoint" {
  value = aws_db_instance.this.endpoint
}

output "db_address" {
  value = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_subnet_group_name" {
  value = aws_db_subnet_group.this.name
}

# RDS 관리형 master Secret (Terraform 이 값을 읽지 않는다)
output "master_user_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "master_user_secret_kms_key_id" {
  value = try(aws_db_instance.this.master_user_secret[0].kms_key_id, null)
}

output "ca_cert_identifier" {
  value = aws_db_instance.this.ca_cert_identifier
}
