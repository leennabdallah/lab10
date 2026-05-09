resource "aws_s3_bucket" "demo" {
  bucket = "cicd-lab-demo-${var.bucket_suffix}"

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Lab         = "010"
    Name        = "cicd-lab-demo"
  }
}

resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "demo" {
  bucket                  = aws_s3_bucket.demo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket_name" {
  value       = aws_s3_bucket.demo.bucket
  description = "Name of the demo S3 bucket"
}
