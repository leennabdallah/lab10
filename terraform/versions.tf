terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "cicd-lab-tfstate-youssef-lab010-n4h8pz"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "cicd-lab-tflocks"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
