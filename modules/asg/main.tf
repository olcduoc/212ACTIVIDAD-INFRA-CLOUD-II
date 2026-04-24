data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-LT-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [var.sg_ec2_id]

  iam_instance_profile {
    name = data.aws_iam_instance_profile.lab.name
  }

  user_data = base64encode(templatefile("${path.root}/scripts/user_data.sh", {
    db_host     = var.db_host
    db_user     = var.db_username
    db_password = var.db_password
    db_name     = var.db_name
    aws_region  = var.aws_region
    account_id  = var.account_id
  }))

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.project_name}-EC2" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "main" {
  name                = "${var.project_name}-ASG"
  vpc_zone_identifier = var.public_subnet_ids
  min_size            = 1
  desired_capacity    = 1
  max_size            = 3

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns         = [var.tg_frontend_arn, var.tg_backend_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180

  tag {
    key                 = "Name"
    value               = "${var.project_name}-EC2"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.project_name}-cpu-policy"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}
