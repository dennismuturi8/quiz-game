# Fetch the latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

locals {
  # Shared token for automated joining (format: [a-z0-9]{6}.[a-z0-9]{16})
  k8s_token = "abcdef.1234567890abcdef"

  k8s_userdata_base = <<-EOF
    #!/bin/bash
    set -eux

    # 1. Fix Kernel Modules & Sysctl Params
    cat <<EOT | tee /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
    EOT

    modprobe overlay
    modprobe br_netfilter

    cat <<EOT | tee /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    EOT

    sysctl --system

    # 2. Disable Swap
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab

    # 3. Install Containerd
    apt-get update
    apt-get install -y containerd curl apt-transport-https
    mkdir -p /etc/containerd
    
    # 4. Fix SystemdCgroup mismatch
    containerd config default | tee /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    systemctl restart containerd

    # 5. Install Kubernetes Binaries
    mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | tee /etc/apt/sources.list.d/k8s.list
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
  EOF
}

resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnets_id
  vpc_security_group_ids = [var.sg_id]
  key_name                = var.key_name

  user_data = <<-EOF
    ${local.k8s_userdata_base}
    
    # Initialize Cluster with fixed token
    kubeadm init --token ${local.k8s_token} --pod-network-cidr=192.168.0.0/16 --ignore-preflight-errors=NumCPU
    
    # Setup kubeconfig
    mkdir -p /home/ubuntu/.kube
    cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    chown ubuntu:ubuntu /home/ubuntu/.kube/config
    
    # Install Calico
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml
  EOF

  tags = { Name = "k8s-control-plane" }
}

resource "aws_instance" "workers" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnets_id
  vpc_security_group_ids = [var.sg_id]
  key_name                = var.key_name
  
  user_data = <<-EOF
    ${local.k8s_userdata_base}

    # Automated Join using the Control Plane's private IP
    kubeadm join ${aws_instance.control_plane.private_ip}:6443 \
      --token ${local.k8s_token} \
      --discovery-token-unsafe-skip-ca-verification
  EOF

  tags = { Name = "k8s-worker-${count.index}" }
}

variable "private_subnets_id" {}
variable "sg_id" {}
variable "key_name" {}
variable "instance_type" {}