terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.25.0 "
    }
  }
}

provider "aws" {
    region = "us-east-2"
}

// Create a VPC to use for the rest of our resources
module "vpc" {
  source          = "terraform-aws-modules/vpc/aws"
  name            = "iac-project-vpc"
  cidr            = "10.0.0.0/16"
  azs             = ["us-east-2a", "us-east-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  #assign_generated_ipv6_cidr_block = true
  #create_database_subnet_group     = true
  enable_nat_gateway = true
  single_nat_gateway = true
}


// Import a key pair from my current desktop environment
resource "aws_key_pair" "altan-key-pair-tf" {
  key_name   = "altan-key-pair-tf"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDY034aIVS9Rz4fQdLNscfyNJTlKuCLP1X2K4mY6W6BZshhWUPdnjnu+vhEC5uU2bVT4lHE/Ry0g14+xfJzsq0xa80+EW6sqMgECmmO+bqRqnmbht6dXwXHaI4cjnCPhH+j2uYxO9cv+mHedKYT61YtNkY5fTrrgr8vAFS2BzdXWgNU/MESpE7UlhOpR8VtfLKyoJARFs4pC6lMFw4QThJd/fDjxyypZAOmsgu6OxSj7NXgDvbv7kAo8+FLlcjxh+MwRThPTOu++pSU8/4JJIh7oJj0Lt7Yx2X7jyBdBBSRRsxdDRiG4+b9nYsoDZhA2Na+jbwpyMYOMwwDPoNy7N1v madato@orca"
}


// Create Security Group for public HTTP / HTTPS access
resource "aws_security_group" "allow_web_traffic_public" {
  name        = "iac-project-allow_web_traffic_public"
  description = "Allows inbound HTTP / HTTPS connections over the public internet"
  vpc_id      = module.vpc.vpc_id

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

// Create Security Group for internal HTTP / HTTPS access
resource "aws_security_group" "allow_web_traffic_internal" {
  name        = "iac-project-allow_web_traffic_internal"
  description = "Allows inbound HTTP / HTTPS connections on internal subnets"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allows inbound HTTP connections on internal networks"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24", "10.0.101.0/24", "10.0.102.0/24"]
  }

  ingress {
    description = "Allows inbound HTTPS connections on internal networks"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24", "10.0.101.0/24", "10.0.102.0/24"]
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



// Create Security Group for allowing SSH from my public IP (for troubleshooting)
resource "aws_security_group" "allow_ssh_public" {
  name        = "iac-project-allow_ssh_public"
  description = "Allows inbound SSH port 22 over internet"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allows inbound SSH connections over the public internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["184.148.169.106/32"]
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

# //Create S3 bucket for logs
# resource "aws_s3_bucket" "iac-project-logs" {
#   bucket_prefix = "iac-project-logs-"
#   tags = {
#     Name        = "iac-project-logs"
#     Environment = "Dev"
#   }
# }

//Create S3 bucket to source NGINX content
resource "aws_s3_bucket" "iac-project-nginx-config-files" {
  bucket = "iac-project-nginx-config-files"
  tags = {
    Name        = "iac-project-nginx-config-files"
    Environment = "Dev"
  }
}

# Upload webpage file to S3
resource "aws_s3_object" "indexhtml" {
  bucket = aws_s3_bucket.iac-project-nginx-config-files.bucket
  key    = "index.html"
  source = "./index.html"
  #source_hash = filemd5(local.object_source)
}

# Upload media file to S3
resource "aws_s3_object" "altanjpg" {
  bucket = aws_s3_bucket.iac-project-nginx-config-files.bucket
  key    = "altan.jpg"
  source = "./altan.jpg"
  #source_hash = filemd5(local.object_source)
}


//Allowing EC2 instance access to S3 bucket PART 1 - Create IAM Role
resource "aws_iam_role" "s3-iam-role" {
  name = "s3-iam-role"

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
resource "aws_iam_instance_profile" "s3-instance-profile" {
  name = "s3-instance-profile"
  role = aws_iam_role.s3-iam-role.name
}

//Allowing EC2 instance access to S3 bucket PART 3 - Create Policy
resource "aws_iam_role_policy" "s3-policy" {
  name = "s3-policy"
  role = aws_iam_role.s3-iam-role.id

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
resource "aws_launch_configuration" "iac-as-launch-config" {
  name                 = "iac_as_launch-config"
  image_id             = "ami-051dfed8f67f095f5"
  instance_type        = "t2.micro"
  key_name             = "altan-key-pair-tf"
  security_groups      = [aws_security_group.allow_web_traffic_public.id]
  iam_instance_profile = aws_iam_instance_profile.s3-instance-profile.id
  user_data            = "IyEvYmluL2Jhc2gKYW1hem9uLWxpbnV4LWV4dHJhcyBpbnN0YWxsIG5naW54MQpzeXN0ZW1jdGwgZW5hYmxlIG5naW54CnN5c3RlbWN0bCBzdGFydCBuZ2lueApjcCAtUiAvdXNyL3NoYXJlL25naW54L2h0bWwgL3Vzci9zaGFyZS9uZ2lueC9pYWMtcHJvamVjdAphd3MgczMgY3AgczM6Ly9pYWMtcHJvamVjdC1uZ2lueC1jb25maWctZmlsZXMvaW5kZXguaHRtbCAvdXNyL3NoYXJlL25naW54L2lhYy1wcm9qZWN0L2luZGV4Lmh0bWwKYXdzIHMzIGNwIHMzOi8vaWFjLXByb2plY3QtbmdpbngtY29uZmlnLWZpbGVzL2FsdGFuLmpwZyAvdXNyL3NoYXJlL25naW54L2lhYy1wcm9qZWN0L2FsdGFuLmpwZwpzZWQgLWkgJ3MvdXNyXC9zaGFyZVwvbmdpbnhcL2h0bWwvdXNyXC9zaGFyZVwvbmdpbnhcL2lhYy1wcm9qZWN0LycgL2V0Yy9uZ2lueC9uZ2lueC5jb25mCnNlZCAtaSAicy9zdHJpbmdob3N0bmFtZXJlcGxhY2UvJGhvc3RuYW1lLyIgL3Vzci9zaGFyZS9uZ2lueC9pYWMtcHJvamVjdC9pbmRleC5odG1sCnN5c3RlbWN0bCByZWxvYWQgbmdpbngK"
}


// Autoscaling Group Part 2 - Create Placement Group
resource "aws_placement_group" "iac-as-placement-group" {
  name     = "iac-as-placement-group"
  strategy = "partition"
}

// Autoscaling Group Part 3 - Create Autoscaling Group
resource "aws_autoscaling_group" "iac-as-autoscaling-group" {
  name                      = "iac-autoscaling-group"
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  force_delete              = true
  placement_group           = aws_placement_group.iac-as-placement-group.id
  launch_configuration      = aws_launch_configuration.iac-as-launch-config.id
  vpc_zone_identifier       = module.vpc.public_subnets
  depends_on                = [aws_s3_bucket.iac-project-nginx-config-files]
  target_group_arns         = [aws_lb_target_group.iac-lb-target-group.arn]
  # load_balancers = aws_lb.iac_loadbalancer
}

// Autoscaling Group Part 4 - Create an increment policy
resource "aws_autoscaling_policy" "iac-as-policy-increase" {
  autoscaling_group_name = aws_autoscaling_group.iac-as-autoscaling-group.name
  name                   = "iac-as-policy-increase"
  policy_type            = "SimpleScaling"
  cooldown               = 300
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
}

// Autoscaling Group Part 5 - Create an reduction policy
resource "aws_autoscaling_policy" "iac-as-policy-decrease" {
  autoscaling_group_name = aws_autoscaling_group.iac-as-autoscaling-group.name
  name                   = "iac-as-policy-decrease"
  policy_type            = "SimpleScaling"
  cooldown               = 300
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
}

// Load Balancer Part 1 - Load Balancer
resource "aws_lb" "iac_loadbalancer" {
  name                       = "iac-loadbalancer"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.allow_web_traffic_public.id]
  subnets                    = module.vpc.public_subnets
  enable_deletion_protection = false

}

// Load Balancer Part 2 - Target Group
resource "aws_lb_target_group" "iac-lb-target-group" {
  name     = "iac-lb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}

// Load Balancer Part 3 - Listener
resource "aws_lb_listener" "iac-lb-listener" {
  load_balancer_arn = aws_lb.iac_loadbalancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.iac-lb-target-group.arn
  }
}

