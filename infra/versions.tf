terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # For real use, store state in S3 + DynamoDB lock. Left local here for clarity.
  # backend "s3" {
  #   bucket         = "REPLACE-tfstate-bucket"
  #   key            = "aws-eks-ha-platform/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "REPLACE-tf-locks"
  #   encrypt        = true
  # }
}
