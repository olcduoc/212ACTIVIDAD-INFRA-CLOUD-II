output "alb_dns_name"    { value = aws_lb.main.dns_name }
output "tg_frontend_arn" { value = aws_lb_target_group.frontend.arn }
output "tg_backend_arn"  { value = aws_lb_target_group.backend.arn }

output "alb_arn_suffix" {
  value = aws_lb.main.arn_suffix
}
