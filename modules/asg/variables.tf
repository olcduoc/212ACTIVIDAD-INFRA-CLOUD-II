variable "project_name"     { type = string }
variable "ami_id"            { type = string }
variable "instance_type"     { type = string }
variable "key_name"          { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "sg_ec2_id"         { type = string }
variable "tg_frontend_arn"   { type = string }
variable "tg_backend_arn"    { type = string }
variable "db_host"           { type = string }
variable "db_name"           { type = string }
variable "aws_region"        { type = string }
variable "account_id"        { type = string }

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}
