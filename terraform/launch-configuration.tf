resource "aws_launch_configuration" "scaling-launch-configuration" {
  name_prefix          = "ric-scaling-launch-configuration"
  image_id             = "ami-0a0133c265730ee1b"
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ric_scaling_profile.name

  root_block_device {
    volume_type           = "standard"
    volume_size           = 8
    delete_on_termination = true
  }

  lifecycle {
    create_before_destroy = true
  }

  security_groups             = [local.security_group]
  associate_public_ip_address = "true"
  key_name                    = local.key_name

  # this enable cloudwatch detailed monitoring which pushed instance metrics more often to Cloudwatch (for a small added price per instance)
  # but insteac of 1 metric point per 5 minutes we get 1 per minute
  enable_monitoring = true

  # create container at startup with latest slave image fro ECR
  user_data = <<EOF
Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cloud-config.txt"

#cloud-config
cloud_final_modules:
- [scripts-user, always]

--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="userdata.txt"

#!/bin/bash

# login docker so it can pull
aws ecr get-login-password --region eu-west-2 | docker login --username AWS --password-stdin 032258715043.dkr.ecr.eu-west-2.amazonaws.com

# create and start the container
docker create --name slave --network host --pull always 032258715043.dkr.ecr.eu-west-2.amazonaws.com/slave:latest
docker start slave

# if instance is lifecycle is pending, signal termination of startup script to auto-scaling group
INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
HOOK_NAME=slave-startup
ASG_NAME=ric-scaling-autoscaling-group

aws autoscaling --region eu-west-2 complete-lifecycle-action --lifecycle-action-result CONTINUE --instance-id $INSTANCE_ID --lifecycle-hook-name $HOOK_NAME --auto-scaling-group-name $ASG_NAME
--//--

EOF
}

