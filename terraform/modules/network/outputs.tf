output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "ingress_subnet_ids" {
  value = aws_subnet.ingress[*].id
}

output "workload_subnet_ids" {
  value = aws_subnet.workload[*].id
}

output "data_subnet_ids" {
  value = aws_subnet.data[*].id
}

output "private_route_table_ids" {
  value = aws_route_table.private[*].id
}

output "data_route_table_id" {
  value = aws_route_table.data.id
}

output "nat_public_ips" {
  value = aws_eip.nat[*].public_ip
}

output "endpoint_security_group_id" {
  value = aws_security_group.endpoints.id
}

output "azs" {
  value = var.azs
}
