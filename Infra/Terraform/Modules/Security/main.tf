# Bastion SG (SSH from your IP)
resource "aws_security_group" "bastion_sg" {
  name   = "bastion-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # For demo purposes, allow SSH from anywhere. In production, restrict to your IP.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Control Plane + Worker SG
resource "aws_security_group" "private_sg" {
  name   = "private-sg"
  vpc_id = var.vpc_id

  # SSH from bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks = ["${var.bastion_ip}/32"]  # Only allow SSH from bastion's public IP
    security_groups = [aws_security_group.bastion_sg.id]
  }

  #AgroCD ports. To be deledted later
  ingress {
  from_port   = 30700
  to_port     = 32700
  protocol    = "tcp"
  cidr_blocks = ["${var.nat_instance_public_ip}/32"]  # Only allow from NAT instance's public IP
}

  # Kubernetes API (6443) from bastion
  ingress {
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Node communication (for kubelet, pod network, etc.)
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB SG
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = var.vpc_id

  # HTTP/HTTPS from internet
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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
}

# 1. Allow ALB to reach the Private Nodes 
resource "aws_security_group_rule" "alb_to_nodes" {
  type                     = "ingress"
  from_port                = 31000
  to_port                  = 31000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb_sg.id
  source_security_group_id = aws_security_group.private_sg.id
}

# 2. Allow Private Nodes to receive from ALB 
resource "aws_security_group_rule" "nodes_from_alb" {
  type                     = "ingress"
  from_port                = 31000
  to_port                  = 31000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
}

# Variables
variable "vpc_id" {
  type = string
}

variable "bastion_ip" {
  type = string
  
}
variable "nat_instance_public_ip" {
  type = string
}
variable "alb_sg_id" {
  type = string
}



