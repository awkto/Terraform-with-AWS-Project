terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 4.25.0 "
        }
    }
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name                             = "iac-project-vpc"
  cidr                             = "10.0.0.0/16"
  azs                              = ["us-east-2a", "us-east-2b"]
  private_subnets                  = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets                   = ["10.0.101.0/24", "10.0.102.0/24"]
  #assign_generated_ipv6_cidr_block = true
  #create_database_subnet_group     = true
  enable_nat_gateway               = true
  single_nat_gateway               = true
}


// Import a key pair from my current desktop environment
resource "aws_key_pair" "altan-key-pair-tf" {
  key_name   = "altan-key-pair-tf"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDY034aIVS9Rz4fQdLNscfyNJTlKuCLP1X2K4mY6W6BZshhWUPdnjnu+vhEC5uU2bVT4lHE/Ry0g14+xfJzsq0xa80+EW6sqMgECmmO+bqRqnmbht6dXwXHaI4cjnCPhH+j2uYxO9cv+mHedKYT61YtNkY5fTrrgr8vAFS2BzdXWgNU/MESpE7UlhOpR8VtfLKyoJARFs4pC6lMFw4QThJd/fDjxyypZAOmsgu6OxSj7NXgDvbv7kAo8+FLlcjxh+MwRThPTOu++pSU8/4JJIh7oJj0Lt7Yx2X7jyBdBBSRRsxdDRiG4+b9nYsoDZhA2Na+jbwpyMYOMwwDPoNy7N1v madato@orca"
}


// Create Security Group for allowing HTTP / HTTPS traffic
resource "aws_security_group" "allow_web_traffic" {
  name        = "iac-project-allow_web_traffic"
  description = "Allows inbound HTTP / HTTPS connections over the public internet"
  vpc_id      = module.vpc.vpc_id

  //Uncomment to allow public SSH for troubleshooting
  ingress {
    description = "Allows inbound SSH connections over the public internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allows inbound HTTP connections over the public internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allows inbound HTTPS connections over the public internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-project-security-group"
  }
}

//Create S3 bucket to source NGINX content
resource "aws_s3_bucket" "iac-project-nginx-configfiles" {
  bucket = "iac-project-nginx-configfiles"
  tags = {
    Name        = "iac-project-nginx-configfiles"
    Environment = "Dev"
  }
}

# resource "aws_s3_bucket_acl" "example" {
#   bucket = aws_s3_bucket.b.id
#   acl    = "private"
# }


//Allowing EC2 instance access to S3 bucket PART 1 - Create IAM Role
resource "aws_iam_role" "s3-downloader" {
  name = "s3-downloader"

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

  tags = {
      tag-key = "tag-value"
  }
}

//Allowing EC2 instance access to S3 bucket PART 2 - Create an IAM Instance Profile for EC2
resource "aws_iam_instance_profile" "s3-downloader" {
  name = "s3-downloader"
  role = "${aws_iam_role.s3-downloader.name}"
}

//Allowing EC2 instance access to S3 bucket PART 3 - Create Policy
resource "aws_iam_role_policy" "s3-downloader" {
  name = "s3-downloader"
  role = "${aws_iam_role.s3-downloader.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

// Autoscaling Group Part 1 - Create Launch Configuration
resource "aws_launch_configuration" "iac-launch-config" {
  name          = "web_config"
  image_id      = "ami-090fa75af13c156b4"
  instance_type = "t2.micro"
  key_name      = "altan-key-pair-tf"
  security_groups = [aws_security_group.allow_web_traffic.id]
  iam_instance_profile = aws_iam_instance_profile.s3-downloader.id
  user_data     = "IyEvYmluL2Jhc2gKYW1hem9uLWxpbnV4LWV4dHJhcyBpbnN0YWxsIG5naW54MQphd3MgczMgY3AgczM6Ly9pYWMtcHJvamVjdC1uZ2lueC1jb25maWdmaWxlcy90ZXN0ZmlsZSAvaG9tZS9lYzItdXNlci8K"
}


// Autoscaling Group Part 2 - Create Placement Group
resource "aws_placement_group" "iac-placement-group" {
  name     = "iac-autoscaling-group"
  strategy = "cluster"
}

// Autoscaling Group Part 3 - Create Autoscaling Group
resource "aws_autoscaling_group" "iac-autoscaling-group" {
  name                      = "iac-autoscaling-group"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 4
  force_delete              = true
  placement_group           = aws_placement_group.iac-placement-group.id
  launch_configuration      = aws_launch_configuration.iac-launch-config.name
  # vpc_zone_identifier       = [aws_subnet.example1.id, aws_subnet.example2.id]          //FIX THIS
  # vpc_zone_identifier       = ["${data.aws_subnet_ids.all.ids}"]
  vpc_zone_identifier       = module.vpc.public_subnets

  initial_lifecycle_hook {
    name                 = "foobar"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 2000
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"

    notification_metadata = <<EOF
{
  "foo": "bar"
}
EOF

    notification_target_arn = "arn:aws:sqs:us-east-1:444455556666:queue1*"
    role_arn                = "arn:aws:iam::123456789012:role/S3Access"
  }

  tag {
    key                 = "foo"
    value               = "bar"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }

  tag {
    key                 = "lorem"
    value               = "ipsum"
    propagate_at_launch = false
  }
}




# // Create an EC2 Instance
# resource "aws_instance" "web_app_server_01" {
#   ami           = "ami-051dfed8f67f095f5"
#   instance_type = "t2.micro"
#   key_name      = "altan-key-pair-tf"
#   tags = {
#     Name = "IaC-Assignment-01"
#   }
# }

# // Create a second EC2 Instance
# resource "aws_instance" "web_app_server_02" {
#   ami           = "ami-051dfed8f67f095f5"
#   instance_type = "t2.micro"
#   key_name      = "altan-key-pair-tf"
#   tags = {
#     Name = "IaC-Assignment-02"
#   }
# }


