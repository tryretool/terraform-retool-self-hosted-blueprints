# Everything this module exports, enumerated explicitly. local.cluster resolves
# each cluster attribute from either the cluster we created or the one we
# adopted (see existing-cluster.tf); the rest describe the cluster-wide
# operators installed here.
#
# The shape mirrors the GKE and EKS modules' cluster output for consistency.
locals {
  outputs = {
    name = local.cluster.name

    # Used to configure kubernetes/helm providers.
    endpoint                   = local.cluster.endpoint
    certificate_authority_data = local.cluster.certificate_authority_data

    # Workload Identity — downstream modules use this to create
    # azurerm_federated_identity_credential resources linking k8s service
    # accounts to Azure managed identities.
    oidc_issuer_url = local.cluster.oidc_issuer_url

    # Kubelet identity for granting node-level access (e.g. ACR pull).
    kubelet_identity_object_id = local.cluster.kubelet_identity_object_id

    # The auto-created node resource group (contains VMSS, disks, NICs).
    node_resource_group = local.cluster.node_resource_group

    # Client credentials for provider auth.
    client_certificate    = local.cluster.client_certificate
    client_key            = local.cluster.client_key
    kube_config_raw       = local.cluster.kube_config_raw
    kube_admin_config_raw = local.cluster.kube_admin_config_raw

    # Where the cluster's shared External Secrets Operator runs. Each Retool
    # deployment federates its own managed identity to a service account in its
    # own namespace and names it on its SecretStore, so the controller itself
    # needs no Key Vault access.
    external_secrets_enabled         = var.enable_external_secrets
    external_secrets_namespace       = local.external_secrets.namespace
    external_secrets_service_account = local.external_secrets.service_account_name

    # Where the cluster's shared cert-manager runs. Unlike ESO it has no
    # per-store service account indirection: an Issuer names a managed identity
    # and cert-manager exchanges its OWN token for it, so each deployment's
    # identity must federate against this subject.
    cert_manager_enabled                 = var.enable_cert_manager
    cert_manager_namespace               = local.cert_manager.namespace
    cert_manager_service_account         = local.cert_manager.service_account_name
    cert_manager_service_account_subject = local.cert_manager_service_account_subject
  }
}

output "cluster" {
  description = "AKS cluster details"
  value       = local.outputs
}

output "outputs" {
  value       = local.outputs
  description = "Structured AKS cluster outputs for composition with downstream modules."
}

output "cert_manager_service_account_subject" {
  value       = local.outputs.cert_manager_service_account_subject
  description = "Federated-credential subject of the cluster's shared cert-manager controller. Per-deployment managed identities federate against this so cert-manager can assume them for DNS-01 challenges against their own zones."
}
