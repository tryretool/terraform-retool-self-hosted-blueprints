provider "aws" {
  profile = local.aws_profile
  region  = local.region
  default_tags {
    tags = merge(local.tags, {
      "retool.com/deployment-name" = local.prefix
    })
  }
}

locals {
  k8s_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["--profile", local.aws_profile, "eks", "get-token", "--region", local.region, "--cluster-name", local.cluster_name]
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = local.k8s_exec.api_version
    command     = local.k8s_exec.command
    args        = local.k8s_exec.args
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = local.k8s_exec.api_version
      command     = local.k8s_exec.command
      args        = local.k8s_exec.args
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  load_config_file       = false

  exec {
    api_version = local.k8s_exec.api_version
    command     = local.k8s_exec.command
    args        = local.k8s_exec.args
  }
}
