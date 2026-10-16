output "state_bucket" {
  description = "S3 bucket for Terraform state (put in envs/*/backend.tf as bucket)"
  value       = aws_s3_bucket.state.bucket
}

output "lock_table" {
  description = "DynamoDB table for Terraform state locking (put in envs/*/backend.tf as dynamodb_table)"
  value       = aws_dynamodb_table.lock.name
}

output "ecr_repository_url" {
  description = "ECR repository URL for the orders-api image"
  value       = aws_ecr_repository.app.repository_url
}

output "ci_role_arn" {
  description = "IAM role GitHub Actions assumes to push images (set as the AWS_ROLE_ARN repository variable)"
  value       = aws_iam_role.ci.arn
}
