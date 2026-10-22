output "cluster_sg_id" {
  value = aws_security_group.cluster.id
}

output "web_node_sg_id" {
  value = aws_security_group.web_node.id
}

output "app_node_sg_id" {
  value = aws_security_group.app_node.id
}

output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}

output "management_sg_id" {
  value = aws_security_group.management.id
}
