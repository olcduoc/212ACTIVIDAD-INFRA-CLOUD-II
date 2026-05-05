# ─── SNS ───────────────────────────────────────────────────────────────────
resource "aws_sns_topic" "alertas" {
  name = "${var.project_name}-alertas"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# ─── ALARMAS EC2 ───────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_alto" {
  alarm_name          = "${var.project_name}-ec2-cpu-alto"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "CPU EC2 supera el 70%"
  alarm_actions       = [aws_sns_topic.alertas.arn]
  ok_actions          = [aws_sns_topic.alertas.arn]

  dimensions = {
    AutoScalingGroupName = module.asg.asg_name
  }
}

# ─── ALARMAS RDS ───────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_cpu_alto" {
  alarm_name          = "${var.project_name}-rds-cpu-alto"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "CPU RDS supera el 70%"
  alarm_actions       = [aws_sns_topic.alertas.arn]
  ok_actions          = [aws_sns_topic.alertas.arn]

  dimensions = {
    DBInstanceIdentifier = module.rds.db_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_bajo" {
  alarm_name          = "${var.project_name}-rds-storage-bajo"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2000000000
  alarm_description   = "Almacenamiento RDS bajo (< 2GB)"
  alarm_actions       = [aws_sns_topic.alertas.arn]

  dimensions = {
    DBInstanceIdentifier = module.rds.db_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_conexiones" {
  alarm_name          = "${var.project_name}-rds-conexiones-altas"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 50
  alarm_description   = "Conexiones RDS superan 50"
  alarm_actions       = [aws_sns_topic.alertas.arn]

  dimensions = {
    DBInstanceIdentifier = module.rds.db_identifier
  }
}

# ─── DASHBOARD ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "tienda_tech" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x = 0
        y = 0
        width = 12
        height = 6
        properties = {
          title   = "EC2 - CPU Utilization"
          period  = 60
          stat    = "Average"
          metrics = [["AWS/EC2", "CPUUtilization",
            "AutoScalingGroupName", module.asg.asg_name]]
        }
      },
      {
        type   = "metric"
        x = 12
        y = 0
        width = 12
        height = 6
        properties = {
          title   = "RDS - CPU Utilization"
          period  = 60
          stat    = "Average"
          metrics = [["AWS/RDS", "CPUUtilization",
            "DBInstanceIdentifier", module.rds.db_identifier]]
        }
      },
      {
        type   = "metric"
        x = 0
        y = 6
        width = 12
        height = 6
        properties = {
          title   = "RDS - Free Storage Space"
          period  = 60
          stat    = "Average"
          metrics = [["AWS/RDS", "FreeStorageSpace",
            "DBInstanceIdentifier", module.rds.db_identifier]]
        }
      },
      {
        type   = "metric"
        x = 12
        y = 6
        width = 12
        height = 6
        properties = {
          title   = "RDS - Database Connections"
          period  = 60
          stat    = "Average"
          metrics = [["AWS/RDS", "DatabaseConnections",
            "DBInstanceIdentifier", module.rds.db_identifier]]
        }
      },
      {
        type   = "metric"
        x = 0
        y = 12
        width = 24
        height = 6
        properties = {
          title   = "ALB - Request Count"
          period  = 60
          stat    = "Sum"
          metrics = [["AWS/ApplicationELB", "RequestCount",
            "LoadBalancer", module.alb.alb_arn_suffix]]
        }
      }
    ]
  })
}
