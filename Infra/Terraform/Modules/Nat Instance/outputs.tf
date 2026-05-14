

output "instance_id" {
  value = aws_instance.nat.id
}

output "primary_network_interface_id" {
  value = aws_instance.nat.primary_network_interface_id
}

output "nat_instance_public_ip" {
  value = aws_instance.nat.public_ip
}


