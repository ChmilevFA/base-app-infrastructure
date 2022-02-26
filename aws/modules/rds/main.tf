locals {
  db_username = "db_user"
  db_password = "db_password"

  db_name = "template_main_db"
  db_identifier = "template-main-db"
}

data "aws_vpc" "vpc" {
  id = var.vpc_id
}

resource "aws_db_subnet_group" "main" {
  name       = "db-main"
  subnet_ids = var.subnets

  tags = {
    Name        = "db-main-subnet-group"
  }
}

resource "aws_security_group" "main_sg" {
  name   = "${local.db_identifier}-rds-sg"
  description = "Allow inbound traffic from vpc"
  vpc_id      = var.vpc_id

  ingress {
    description      = "Allow inbound traffic from vpc"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    cidr_blocks      = [data.aws_vpc.vpc.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.db_identifier}-rds-sg"
    Db = local.db_identifier
  }
}

resource "aws_db_instance" "rds_main" {
  allocated_storage     = 5
  max_allocated_storage = 10
  engine                = "postgres"
  engine_version        = "14.1"
  instance_class        = "db.t3.micro"
  name                  = local.db_name
  identifier            = local.db_identifier
  username              = local.db_username
  password              = local.db_password
  db_subnet_group_name  = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.main_sg.id]
  skip_final_snapshot   = true
  tags = {
    Name        = "db-main"
  }
}

resource "aws_ssm_parameter" "rds_main_address" {
  name  = "db-main-address"
  type  = "String"
  value = aws_db_instance.rds_main.address
}

resource "aws_ssm_parameter" "rds_main_name" {
  name  = "db-main-name"
  type  = "String"
  value = local.db_name
}
