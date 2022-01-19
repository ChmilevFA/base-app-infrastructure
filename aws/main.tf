terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.48.0"
    }
  }

  required_version = "~> 1.1.2"
}

provider "aws" {
  region = var.aws_region
}

locals {
  ecr_policy           = <<EOF
  {
    "Version": "2008-10-17",
    "Statement": [
      {
        "Sid": "adds full ecr access to the demo repository",
        "Effect": "Allow",
        "Principal": "*",
        "Action": [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetLifecyclePolicy",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
      }
    ]
  }
  EOF
}

# Create ECR repository
resource "aws_ecr_repository" "ecr_repository_template_app_java" {
  name     = "template_app_java"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository_policy" "ecr_repository_template_app_java" {
  repository = aws_ecr_repository.ecr_repository_template_app_java.name

  policy     = local.ecr_policy
}