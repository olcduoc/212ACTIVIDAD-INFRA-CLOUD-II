variable "aws_region" {
  default = "us-east-1"
}
variable "project_name" {
  default = "tienda-tech"
}
variable "vpc_id" {
  type = string
}
variable "public_subnet_ids" {
  type = list(string)
}
variable "private_subnet_ids" {
  type = list(string)
}
variable "ami_id" {
  type = string
}
variable "instance_type" {
  default = "t3.micro"
}
variable "key_name" {
  type = string
}
variable "db_username" {
  type      = string
  sensitive = true
}
variable "db_password" {
  type      = string
  sensitive = true
}
variable "db_name" {
  default = "tienda_tecnologica"
}
variable "account_id" {
  default = "975050244181"
}

variable "sns_email" {
  description = "Correo para recibir alertas CloudWatch"
  type        = string
}
