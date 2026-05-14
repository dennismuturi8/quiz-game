provider "aws" {
  region = var.aws_region
}

module "iam" {
  source = "./Modules/IAM"
}

module "nat_instance" {
  source            = "./Modules/Nat Instance"
  name = "nat-instance"
  vpc_id            = module.network.vpc_id
  public_subnets_id = module.network.public_subnet_ids[0]
  public_subnet_id = module.network.public_subnet_ids[0]
  key_name          = var.key_name
  private_cidr = var.vpc_cidr
}

resource "aws_route" "private_nat" {
  route_table_id         = module.network.private_rt_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.nat_instance.primary_network_interface_id
}

module "network" {
  source = "./Modules/Network"
  vpc_cidr       = var.vpc_cidr
  public_subnets_cidr = var.public_subnets_cidr[*]
  private_subnets_cidr = var.private_subnets_cidr[*]
  availability_zones = var.availability_zones
}

module "security" {
  source = "./Modules/Security"
  vpc_id = module.network.vpc_id
  bastion_ip = module.bastion.bastion_ip
  nat_instance_public_ip = module.nat_instance.nat_instance_public_ip
  alb_sg_id = module.security.alb_sg
}

module "bastion" {
  source    = "./Modules/Bastion"
  public_subnets_id = module.network.public_subnet_ids[0]
  sg_id = module.security.bastion_sg
  key_name  = var.key_name
  instance_type = var.instance_type
}

module "compute" {
  source    = "./Modules/Compute"
  private_subnets_id = module.network.private_subnet_ids[0]
  sg_id     = module.security.private_sg
  key_name  = var.key_name
  instance_type = var.instance_type
  depends_on = [ module.nat_instance]
}


module "alb" {
  source    = "./Modules/ALB"
  vpc_id    = module.network.vpc_id
  sg_id     = module.security.alb_sg
  targets   = module.compute.worker_instance_ids
  public_subnet_ids = module.network.public_subnet_ids
}

/*module "bootstrap" {
  source = "./Modules/Bootstrap"
  bastion_ip        = module.bastion.bastion_ip
  control_plane_ip  = module.compute.control_plane_ip
  worker_ips        = module.compute.worker_ips
  private_key_path       = var.private_key_path

  depends_on = [
    module.bastion,
    module.compute
  ]
}*/


