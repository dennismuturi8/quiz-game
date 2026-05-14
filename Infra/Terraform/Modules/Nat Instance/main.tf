data "aws_ami" "this" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"] # Specified architecture in the name
  }

  filter {
    name   = "architecture"
    values = ["x86_64"] # Double-down with a dedicated filter
  }
}
resource "aws_instance" "nat" {
  ami                         = data.aws_ami.this.id
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.nat_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  source_dest_check = false   # CRITICAL

  user_data = <<-EOF
              #!/bin/bash
              sysctl -w net.ipv4.ip_forward=1
              echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

              iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
              iptables -A FORWARD -s ${var.private_cidr} -j ACCEPT
              EOF

  tags = {
    Name = "nat-instance"
  }
}

resource "aws_security_group" "nat_sg" {
  vpc_id = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.private_cidr]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # restrict later
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


variable "public_subnet_id" {}







