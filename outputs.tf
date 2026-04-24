output "alb_dns_name" {
  value = module.alb.alb_dns_name
}
output "asg_name" {
  value = module.asg.asg_name
}
output "rds_endpoint" {
  value     = module.rds.rds_endpoint
  sensitive = true
}
output "rds_multi_az" {
  value = module.rds.multi_az
}
