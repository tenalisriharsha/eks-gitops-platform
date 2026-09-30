# Local state for now — no S3 bucket/DynamoDB table has been provisioned yet.
# Once Phase 2 stands up real AWS infrastructure, switch this to an S3 backend
# with state locking, e.g.:
#
# terraform {
#   backend "s3" {
#     bucket         = "<your-tfstate-bucket>"
#     key            = "eks-gitops-platform/dev/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "<your-tf-lock-table>"
#     encrypt        = true
#   }
# }
