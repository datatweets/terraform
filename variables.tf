variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t2.micro"
}

variable "db_username" {
  description = "Username for the RDS database."
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Password for the RDS database."
  type        = string
  sensitive   = true
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet."
  type        = string
  default     = "10.0.1.0/24"
}
