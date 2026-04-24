module "security" {
  source       = "./modules/security"
  project_name = var.project_name
  vpc_id       = var.vpc_id
}

module "alb" {
  source            = "./modules/alb"
  project_name      = var.project_name
  vpc_id            = var.vpc_id
  public_subnet_ids = var.public_subnet_ids
  sg_alb_id         = module.security.sg_alb_id
}

module "rds" {
  source             = "./modules/rds"
  project_name       = var.project_name
  private_subnet_ids = var.private_subnet_ids
  sg_rds_id          = module.security.sg_rds_id
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
}

module "asg" {
  source            = "./modules/asg"
  project_name      = var.project_name
  ami_id            = var.ami_id
  instance_type     = var.instance_type
  key_name          = var.key_name
  public_subnet_ids = var.public_subnet_ids
  sg_ec2_id         = module.security.sg_ec2_id
  tg_frontend_arn   = module.alb.tg_frontend_arn
  tg_backend_arn    = module.alb.tg_backend_arn
  db_host           = module.rds.rds_endpoint
  db_username       = var.db_username
  db_password       = var.db_password
  db_name           = var.db_name
  aws_region        = var.aws_region
  account_id        = var.account_id
}
