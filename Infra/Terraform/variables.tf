variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "aws_region" {
default = "us-east-1"
}


variable "key_name" {
description = "Existing EC2 keypair"
type = string
}


variable "instance_type" {
description = "EC2 instance type"
type        = string
}

variable "nat_instance_type" {
  type    = string
}

variable "vpc_cidr" {
description = "CIDR block for the VPC"
type        = string
}

variable "public_subnets_cidr" {
description = "CIDR block for the public subnet"
type        = list(string)
default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets_cidr" {
description = "CIDR block for the private subnet"
type        = list(string)
default = ["10.0.3.0/24", "10.0.4.0/24"]
}


variable "private_key_path" {
  description = "Path to the private key file for SSH access"
  type        = string
}

variable "ssh_user" {
  description = "SSH user for the EC2 instances"
  type        = string
}

