# variables.tf

variable "env" {
  description = "Deployment environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be one of: dev, staging, prod."
  }
}

variable "eks_endpoint_public_access_cidrs" {
  description = "IPv4 CIDRs permitted to reach the public EKS API endpoint."
  type        = list(string)
  default     = ["99.243.74.50/32"]

  validation {
    condition = length(var.eks_endpoint_public_access_cidrs) > 0 && alltrue([
      for cidr in var.eks_endpoint_public_access_cidrs :
      can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0"
    ])
    error_message = "Provide at least one valid restricted IPv4 CIDR; 0.0.0.0/0 is forbidden."
  }
}

variable "tags" {
  description = "Additional tags merged into the required project tags."
  type        = map(string)
  default     = {}
}
