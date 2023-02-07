resource "aws_autoscaling_group" "ric-autoscaling-group" {
  name                      = "ric-scaling-autoscaling-group"
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 30
  health_check_type         = "EC2"
  default_cooldown          = 60 # in a real world example 60 seconds is too low and might cause large swings in capacity
  default_instance_warmup   = 0
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

resource "aws_autoscaling_policy" "target-cpu" {
  autoscaling_group_name    = aws_autoscaling_group.ric-autoscaling-group.name
  name                      = "CPUTargetScaling"
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 0

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}