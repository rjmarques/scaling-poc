resource "aws_autoscaling_group" "ric-autoscaling-group" {
  name                      = "ric-scaling-autoscaling-group"
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 30
  health_check_type         = "EC2"
  default_cooldown          = 240
  default_instance_warmup   = 10
  vpc_zone_identifier       = [local.subnet]
  launch_configuration      = aws_launch_configuration.scaling-launch-configuration.name
  tag {
    key                 = "Name"
    value               = "RicScalingTestSlaveServer"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_lifecycle_hook" "slave-startup" {
  name                   = "slave-startup"
  autoscaling_group_name = aws_autoscaling_group.ric-autoscaling-group.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 600
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
}

resource "aws_autoscaling_lifecycle_hook" "slave-drain" {
  name                   = "slave-drain"
  autoscaling_group_name = aws_autoscaling_group.ric-autoscaling-group.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 3600
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
}

resource "aws_autoscaling_policy" "poc-scale-out" {
  name                   = "ric-poc-scale-out"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  policy_type            = "SimpleScaling"
  autoscaling_group_name = aws_autoscaling_group.ric-autoscaling-group.name
}

resource "aws_cloudwatch_metric_alarm" "scaling-high-cpu" {
  alarm_name          = "ric-poc-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  period              = "60"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  threshold           = "70"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.ric-autoscaling-group.name
  }

  alarm_description = "This metric monitors high ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.poc-scale-out.arn]
}

resource "aws_autoscaling_policy" "poc-scale-in" {
  name                   = "ric-poc-scale-in"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  policy_type            = "SimpleScaling"
  autoscaling_group_name = aws_autoscaling_group.ric-autoscaling-group.name
}

resource "aws_cloudwatch_metric_alarm" "scaling-low-cpu" {
  alarm_name          = "ric-poc-low-cpu"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "1"
  period              = "60"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  threshold           = "20"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.ric-autoscaling-group.name
  }

  alarm_description = "This metric monitors low ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.poc-scale-in.arn]
}