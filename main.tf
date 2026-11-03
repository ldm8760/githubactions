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

# bucket for general use
resource "aws_s3_bucket" "recordings_bucket" {
  bucket = "audio-drop-bucket"

  tags = {
    Name = "MyBucket"
    Environment = "Dev"
  }
}

# folder to drop recordings into
resource "aws_s3_object" "folder1" {
  bucket = aws_s3_bucket.recordings_bucket.id
  acl = "private"
  key = "recordings/"
}

# folder to store transcripts
resource "aws_s3_object" "folder2" {
  bucket = aws_s3_bucket.recordings_bucket.id
  acl = "private"
  key = "transcripts/"
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

# 3. Create a Custom IAM Policy for Amazon Transcribe
resource "aws_iam_policy" "transcribe_access" {
  name        = "lambda-transcribe-access-policy"
  description = "Provides Lambda permissions to start and manage Transcribe jobs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "transcribe:StartTranscriptionJob",
          "transcribe:GetTranscriptionJob",
          "transcribe:ListTranscriptionJobs"
        ]
        Resource = "*"
      }
    ]
  })
}

# attach policy to role (lambda)

resource "aws_iam_role_policy_attachment" "attach_iam_to_iam_role" {
  role = aws_iam_role.lambda_role.name  
  policy_arn = aws_iam_policy.lambda_iam_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_transcribe_policy" {
  role = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.transcribe_access.arn
}

# create lambda function
resource "aws_lambda_function" "terraform_lambda_function" {
  role = aws_iam_role.lambda_role.arn
  function_name = "terraform_for_transcribe"
  filename = "${path.module}/python/transcribe_handler.zip"  
  handler = "transcribe_handler.lambda_handler"
  runtime = "python3.15"
  depends_on = [ aws_iam_role_policy_attachment.attach_iam_to_iam_role ]
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

# handle new files in s3
# 
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.terraform_lambda_function.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.recordings_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.recordings_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.terraform_lambda_function.arn
    events = [ "s3:ObjectCreated:*" ]
    filter_prefix = "${aws_s3_object.folder1.key}" # trigger for new files in recordings/
  }
  depends_on = [ aws_lambda_permission.allow_bucket ]
}
