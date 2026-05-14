# modules/compute/outputs.tf
output "control_plane_ip" { value = aws_instance.control_plane.private_ip }
output "worker_ips"        { value = aws_instance.workers[*].private_ip }
output "worker_instance_ids" {
  description = "IDs of worker instances"
  value       = aws_instance.workers[*].id
}

