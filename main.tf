terraform {
  backend "s3" {
    bucket = "s3-github-actions-terraform"
    key = "prod/terraform.tfstate"
    region = "us-east-1"
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"  # Set AWS region to US East 1 (N. Virginia)
}

# Local variables block for configuration values
locals {
    aws_key = "LM_KEY_PAIR_useast1"   # SSH key pair name for EC2 instance access
}

resource "aws_s3_bucket" "recordings_bucket" {
  bucket = "audio_drop_bucket"

  tags = {
    Name = "MyBucket"
    Environment = "Dev"
  }
}

resource "aws_s3_object" "folder1" {
  
  bucket = aws_s3_bucket.recordings_bucket
  acl = "private"
  key = "recordings/"
}

# setup for lambda function
# iam role
resource "aws_iam_role" "lambda_role" {
  name = "terraform_aws_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

#iam policy for logging from a lambda
resource "aws_iam_policy" "lambda_iam_policy" {
  name = "aws_iam_policy_for_terraform_lambda_role"
  path = "/"
  description = "aws_iam_policy_for_terraform_lambda_role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      Effect = "Allow",
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

# security group resource definition
resource "aws_security_group" "allow_http_ssh" {
  name = "allow_http"
  description = "allow incoming http traffic"

  ingress {
    description = "allow http entry"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow ssh entry"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "allow all outbound traffic"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instance resource definition
resource "aws_instance" "my_server" {
   ami           = data.aws_ami.amazonlinux.id  # Use the AMI ID from the data source
   instance_type = var.instance_type            # Use the instance type from variables
   key_name      = "${local.aws_key}"          # Specify the SSH key pair name
  
   user_data = "${file("wp_install.sh")}" # Run shell script to startup wordpress installation
   security_groups = [aws_security_group.allow_http_ssh.name] # specify security group

   # Add tags to the EC2 instance for identification
   tags = {
     Name = "my ec2"
   }
}
