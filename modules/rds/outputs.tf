output "rds_endpoint" {
  value     = aws_db_instance.mysql.address
  sensitive = true
}
output "multi_az" { value = aws_db_instance.mysql.multi_az }
