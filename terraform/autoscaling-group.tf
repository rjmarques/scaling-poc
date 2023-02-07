resource "aws_autoscaling_group" "ric-autoscaling-group" {
  name                      = "ric-scaling-autoscaling-group"
  max_size                  = 2
  min_size                  = 1
  health_check_grace_period = 30
  health_check_type         = "EC2"
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
  heartbeat_timeout      = 600
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
}