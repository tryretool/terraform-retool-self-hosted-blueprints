provider "azurerm" {
  features {}
  subscription_id = "00000000-0000-0000-0000-000000000000" # replace with your subscription ID
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
