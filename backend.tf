terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "tienda-tech-tfstate-533267352641"
    key            = "tienda-tech-ec2/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tienda-tech-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}
