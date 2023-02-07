# in the real world mast and slave would have seperate roles of course
resource "aws_iam_instance_profile" "ric_scaling_profile" {
  name = "ric_scaling_profile"
  role = aws_iam_role.role.name
}

resource "aws_iam_role" "role" {
  name               = "scaling_poc_role"
  path               = "/"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecr-reader-role-attachment" {
  role       = aws_iam_role.role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_policy" "ric-autoscaling-policy" {
  name        = "ScalingAccessPolicy"
  description = "Allows EC2 instance to access auto scaling group data"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
              "autoscaling:DescribeAutoScalingGroups",
              "autoscaling:SetInstanceHealth",
              "autoscaling:CompleteLifecycleAction",
              "ec2:DescribeInstances"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "asg-reader-policy-attachment" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.ric-autoscaling-policy.arn
}