resource "aws_instance" "master_server" {
  ami                         = "ami-0a0133c265730ee1b"
  associate_public_ip_address = true
  availability_zone           = "eu-west-2a"
  instance_type               = "t3.micro"
  key_name                    = local.key_name
  vpc_security_group_ids      = ["sg-0f32395615e529070"]
  subnet_id                   = local.subnet
  iam_instance_profile        = aws_iam_instance_profile.ric_scaling_profile.name
  tags = {
    "Name" = "RicScalingTestMasterServer"
  }
  root_block_device {
    delete_on_termination = true
    volume_size           = 8
    volume_type           = "standard"
  }

  # create container at startup with latest master image fro ECR
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
docker create --name master --network host --pull always 032258715043.dkr.ecr.eu-west-2.amazonaws.com/master:latest
docker start master

--//--

EOF
}