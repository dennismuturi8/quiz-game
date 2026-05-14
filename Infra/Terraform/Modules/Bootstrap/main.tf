/*resource "null_resource" "cluster_bootstrap" {
  # This ensures the resource only runs AFTER the control plane VM is fully created
  depends_on = [var.control_plane_ip] 

  connection {
    type                = "ssh"
    host                = var.control_plane_ip
    user                = "ubuntu"
    private_key         = file(var.private_key_path)
    bastion_host        = var.bastion_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(var.private_key_path)
    agent               = false
  }

 provisioner "remote-exec" {
  inline = [
    # 1. Wait for System/Apt locks to clear
    "echo 'Waiting for cloud-init/apt locks...'",
    "while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done",
    
    # 2. Update Apt
    "sudo apt-get update -y",

    # 3. Wait for Kubernetes API
    "echo 'Waiting for Kubernetes API to respond...'",
    "timeout 300 bash -c 'until sudo kubectl --kubeconfig /etc/kubernetes/admin.conf cluster-info; do sleep 10; done'",

    # 4. Create ArgoCD Namespace
    "echo 'Creating ArgoCD Namespace...'",
    "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf create namespace argocd --dry-run=client -o yaml | sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f -",

    # 5. Install ArgoCD
    "echo 'Installing ArgoCD...'",
    "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml",

    # 6. Create NGINX Ingress Namespace
    "echo 'Creating NGINX Ingress Namespace...'",
    "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf create namespace ingress-nginx --dry-run=client -o yaml | sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f -",

    # 7. Install NGINX Ingress Controller
    "echo 'Installing NGINX Ingress Controller...'",
    "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml",

    # 8. Wait for Ingress Controller to be ready
    "echo 'Waiting for NGINX Ingress Controller...'",
    "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf wait --namespace ingress-nginx --for=condition=available deployment/ingress-nginx-controller --timeout=300s",

    # 9. Patch NodePorts (for ALB compatibility)
    "echo 'Patching NodePorts for ALB...'",
    "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p='[{\"op\": \"replace\", \"path\": \"/spec/ports/0/nodePort\", \"value\": 31000}, {\"op\": \"replace\", \"path\": \"/spec/ports/1/nodePort\", \"value\": 31001}]'"
  ]
  
 }
  }


variable "bastion_ip" {
  type = string
}

variable "control_plane_ip" {
  type = string
}

variable "worker_ips" {
  type = list(string)
}

variable "private_key_path" {
  type = string
}*/



