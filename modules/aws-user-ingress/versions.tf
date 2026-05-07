terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.94.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19"
    }
  }
}
