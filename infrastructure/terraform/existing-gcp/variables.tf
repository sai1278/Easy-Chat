variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "mattermost-smartlead-prod"
}

variable "region" {
  description = "GCP Deployment Region"
  type        = string
  default     = "asia-south1"
}

variable "environment" {
  description = "Deployment Environment (prod, staging, dev)"
  type        = string
  default     = "prod"
}
