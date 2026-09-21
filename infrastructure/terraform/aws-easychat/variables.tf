variable "aws_region" {
  description = "AWS Deployment Region for Easy Chat"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (production, staging, dev)"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name prefix used for resource tagging and naming"
  type        = string
  default     = "easychat"
}

variable "vpc_cidr" {
  description = "Isolated CIDR block for Easy Chat dedicated VPC"
  type        = string
  default     = "10.50.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for Easy Chat public subnet"
  type        = string
  default     = "10.50.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for Easy Chat single-node Docker host"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS gp3 volume size in GB"
  type        = number
  default     = 40
}

variable "domain_name" {
  description = "Production API domain name"
  type        = string
  default     = "api.easychat.com"
}

variable "s3_bucket_suffix" {
  description = "Globally unique suffix (such as AWS account ID or unique string) to ensure global S3 bucket uniqueness"
  type        = string
  default     = "storage"
}

variable "s3_media_bucket_name" {
  description = "Explicit globally unique name for Easy Chat S3 media storage. If null, derived from project_name, environment, and s3_bucket_suffix"
  type        = string
  default     = null
}

variable "admin_ssh_cidr" {
  description = "CIDR allowed to SSH to EC2 (optional; leave null or restrict to admin IP. SSM Session Manager is preferred)"
  type        = string
  default     = null
}
