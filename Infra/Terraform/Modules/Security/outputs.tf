output "bastion_sg" { value = aws_security_group.bastion_sg.id }
output "private_sg" { value = aws_security_group.private_sg.id }
output "alb_sg" { value = aws_security_group.alb_sg.id }


