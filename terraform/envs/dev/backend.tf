# Remote state. Bucket and lock table are created once, out of band (bootstrap).
terraform {
  backend "s3" {
    bucket         = "REPLACE-ME-tfstate"
    key            = "platform/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE-ME-tflock"
    encrypt        = true
  }
}
