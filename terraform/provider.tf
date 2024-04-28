terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.33.0"
    }
  }

  backend "s3" {
    bucket         = "flask-tr-s3"
    key            = "tfstate/state"
    region         = "us-east-1"
    dynamodb_table = "trdynamodb"
  }
}

provider "aws" {
  region = "us-east-1"
}
