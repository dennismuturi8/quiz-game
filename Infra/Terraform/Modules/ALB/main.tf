resource "aws_lb" "alb" {
  name               = "k8s-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.sg_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "tg" {
  target_type = "instance"
  name        = "k8s-tg"
  port     = 31000
  protocol = "HTTP"
  vpc_id   = var.vpc_id
 
  health_check {
    path = "/healthz"
    port = "31000"
    protocol = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group_attachment" "targets" {
  count            = length(var.targets)
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = var.targets[count.index]
  port             = 31000
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

variable "vpc_id" {
  type = string
}

variable "sg_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "targets" {
    type = list(string)
}

output "alb_dns" {
  value = aws_lb.alb.dns_name
}
