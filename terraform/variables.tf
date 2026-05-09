variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "bucket_suffix" {
  type        = string
  description = "Globally unique suffix for demo S3 bucket"
}

variable "environment" {
  type        = string
  description = "Tag value for Environment"
  default     = "lab"
}
