variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS profile credentials for all resources."

  type    = string
  default = "private"
}