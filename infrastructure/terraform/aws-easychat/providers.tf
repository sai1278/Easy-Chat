terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # NOTE: Local state is used by default for safety.
  # To enable remote state in a dedicated S3 bucket (NOT shared with any other project):
  # backend "s3" {
  #   bucket         = "easychat-terraform-state"
  #   key            = "production/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "easychat-terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "EasyChat"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "EasyChat-Platform"
    }
  }
}
