variable "domain_name" {
  type        = string
  description = "Desired retool domain name"
}

variable "vpc" {
  type = object({
    vpc_id            = string
    public_subnet_ids = list(string)
  })
  description = <<-EOD
    VPC related inputs:
      vpc_id: VPC where the load balancer and target group are created
      public_subnet_ids: Subnet IDs (one per AZ) where the internet-facing ALB is placed
  EOD
}

variable "eks" {
  type = object({
    node_security_group_id = string
  })
  description = <<-EOD
    EKS related inputs:
      node_security_group_id: EKS worker node security group ID; must allow TCP from the user ALB to reach pod IPs registered by TargetGroupBinding
  EOD
}

variable "retool_service_name" {
  type        = string
  description = "Name of the Kubernetes Service fronting Retool pods"
  default     = "retool"
}

variable "retool_service_namespace" {
  type        = string
  description = "Namespace of the Kubernetes Service fronting Retool pods"
  default     = "default"
}

variable "retool_service_port" {
  type        = number
  description = "Port on the Kubernetes Service that serves Retool traffic"
  default     = 3000
}

variable "enable_https_listener" {
  type        = bool
  description = <<-EOT
    When true, request an ACM certificate (plus DNS validation records in this
    hosted zone) and attach an HTTPS listener on port 443. The certificate must
    reach ISSUED state (requires delegating the hosted zone NS at the registrar
    unless the domain is already publicly resolvable).
    When false, no ACM certificate is created and the ALB serves Retool on HTTP
    port 80 only — suitable for first apply before DNS delegation, sandbox
    domains that cannot publicly validate, or TLS termination elsewhere.
  EOT
  default     = false
}
