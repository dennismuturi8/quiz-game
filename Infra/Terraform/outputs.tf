output "bastion_ip" {
  value = module.bastion.bastion_ip
}

output "control_plane_ip" {
  value = module.compute.control_plane_ip
}

output "nat_instance_public_ip" {
  value = module.nat_instance.nat_instance_public_ip
}

output "worker_ips" {
  value = module.compute.worker_ips
}

output "alb_dns" {
  value = module.alb.alb_dns
}


output "ssh_user" {
description = "SSH user for nodes"
value = var.ssh_user
}

output "ssh_key_path" {
description = "Path to the private key for SSH access"
value = var.private_key_path
}