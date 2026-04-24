variable "project_name"       { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "sg_rds_id"          { type = string }
variable "db_name"            { type = string }

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}
