provider "azurerm" {
  features {}
  subscription_id = local.subscription_id
}

# AKS kube_config provides host + client cert/key for Kubernetes provider auth.
provider "kubernetes" {
  host                   = module.aks.cluster.endpoint
  client_certificate     = base64decode(module.aks.cluster.client_certificate)
  client_key             = base64decode(module.aks.cluster.client_key)
  cluster_ca_certificate = base64decode(module.aks.cluster.certificate_authority_data)
}

provider "helm" {
  kubernetes {
    host                   = module.aks.cluster.endpoint
    client_certificate     = base64decode(module.aks.cluster.client_certificate)
    client_key             = base64decode(module.aks.cluster.client_key)
    cluster_ca_certificate = base64decode(module.aks.cluster.certificate_authority_data)
  }
}

provider "kubectl" {
  host                   = module.aks.cluster.endpoint
  client_certificate     = base64decode(module.aks.cluster.client_certificate)
  client_key             = base64decode(module.aks.cluster.client_key)
  cluster_ca_certificate = base64decode(module.aks.cluster.certificate_authority_data)
  load_config_file       = false
}
