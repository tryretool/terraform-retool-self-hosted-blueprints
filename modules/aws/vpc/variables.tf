variable "prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "cidr_block" {
  type        = string
  description = "Cidr block of IPs the VPC has"
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  type        = list(string)
  description = "List of the ip ranges for the public subnet. Should be of length 3 (given we have 3 AZs)."
  default     = ["10.0.24.0/23", "10.0.26.0/23", "10.0.28.0/23"]
}

variable "private_subnets" {
  type        = list(string)
  description = "List of the ip ranges for the private subnet. Should be of length 3 (given we have 3 AZs)."
  default     = ["10.0.0.0/21", "10.0.8.0/21", "10.0.16.0/21"]
}

variable "public_subnet_tags" {
  type        = map(string)
  description = "Additional tags for public subnets"
  default     = {}
}

variable "private_subnet_tags" {
  type        = map(string)
  description = "Additional tags for private subnets"
  default     = {}
}

variable "default_tags" {
  type        = map(string)
  description = "Default tags applied to all taggable resources. Includes service identification by default."
  default = {
    "service" = "retool"
  }
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged on top of default_tags. Use this for environment- or deployment-specific tags."
  default     = {}
}

variable "enable_flow_logs" {
  type        = bool
  description = "Enable VPC Flow Logs to CloudWatch. Recommended for production environments to audit network traffic."
  default     = false
}

variable "flow_log_retention_days" {
  type        = number
  description = "Number of days to retain VPC Flow Log entries in CloudWatch."
  default     = 90
}

variable "default_network_acl_ingress_rules" {
  type = list(object({
    rule_no         = number
    action          = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_block      = optional(string, null)
    ipv6_cidr_block = optional(string, null)
  }))
  description = "List of ingress rules for the default network ACL"
  default = [
    {
      rule_no    = 100
      action     = "allow"
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = "0.0.0.0/0"
    },
    {
      rule_no         = 101
      action          = "allow"
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      ipv6_cidr_block = "::/0"
    },
  ]
}

variable "default_network_acl_egress_rules" {
  type = list(object({
    rule_no         = number
    action          = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_block      = optional(string, null)
    ipv6_cidr_block = optional(string, null)
  }))
  description = "List of egress rules for the default network ACL"
  default = [
    {
      rule_no    = 99
      action     = "deny"
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = "169.254.0.0/16"
    },
    {
      rule_no    = 100
      action     = "allow"
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = "0.0.0.0/0"
    },
    {
      rule_no         = 101
      action          = "allow"
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      ipv6_cidr_block = "::/0"
    },
  ]
}
