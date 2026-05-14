terraform {
  backend "s3" {
    bucket = "kbucci-bucket-438438438"
        key    = "voting-app/terraform.tfstate"
        region = "us-east-1"
        encrypt = true
  }
}

