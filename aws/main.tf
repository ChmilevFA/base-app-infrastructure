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
  profile = var.aws_profile
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

resource "aws_ecr_lifecycle_policy" "ecr_repository_template_app_java-policy" {
  repository = aws_ecr_repository.ecr_repository_template_app_java.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Expire images older than 1 day",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 1
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

# Create and set up ECS cluster
resource "aws_ecs_cluster" "ecs_cluster_template_app_java" {
  name = "ecs-template_app_java"
}

  resource "aws_ecs_task_definition" "template_app_java-task" {
  family                   = "template_app_java-task"
  container_definitions    = <<DEFINITION
  [
    {
      "name": "template_app_java-task",
      "image": "${aws_ecr_repository.ecr_repository_template_app_java.repository_url}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 7000,
          "hostPort": 7000
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_service" "template_app_java-service" {
  name            = "template_app_java-service"
  cluster         = aws_ecs_cluster.ecs_cluster_template_app_java.id
  task_definition = aws_ecs_task_definition.template_app_java-task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = aws_ecs_task_definition.template_app_java-task.family
    container_port   = 7000
  }

  network_configuration {
    subnets          = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.template_app_java-service_security_group.id]
  }
}

resource "aws_security_group" "template_app_java-service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = [aws_security_group.load_balancer_security_group.id]
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}

# Providing a reference to our default VPC
resource "aws_default_vpc" "default_vpc" {
}

# Providing a reference to our default subnets
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = data.aws_availability_zones.available.names[1]
}

# set up load balancer
resource "aws_alb" "application_load_balancer" {
  name               = "application-lb-tf"
  load_balancer_type = "application"
  subnets = [
    aws_default_subnet.default_subnet_a.id,
    aws_default_subnet.default_subnet_b.id
  ]
  security_groups = [aws_security_group.load_balancer_security_group.id]
}

# Creating a security group for the load balancer:
resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port   = 80 # Allowing traffic in from port 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}

resource "aws_lb_target_group" "target_group" {
  name        = "target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.default_vpc.id
  health_check {
    matcher = "200,301,302"
    path = "/"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_alb.application_load_balancer.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

module "rds" {
  source        = "./modules/rds"
  vpc_id        = aws_default_vpc.default_vpc.id
  subnets       = [
    aws_default_subnet.default_subnet_a.id,
    aws_default_subnet.default_subnet_b.id
  ]
}
