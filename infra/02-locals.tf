# locals.tf

locals {
  # ##############################
  # Metadata
  # ##############################
  project     = "llm-ollama-eks"
  name_prefix = "${local.project}-${var.env}"
  aws_region  = "us-east-1"
  default_tags = merge(
    {
      Project     = local.project
      Environment = var.env
      ManagedBy   = "Terraform"
      Repository  = "llm-ollama-eks"
    },
    var.tags
  )

  # ##############################
  # VPC
  # ##############################
  vpc_cidr     = "10.0.0.0/16"
  vpc_az_count = 3

  # ##############################
  # EKS
  # ##############################
  eks_cluster_name = "${local.name_prefix}-eks"
  eks_version      = "1.35"

  eks_cpu_node_instance_types = ["t3.large"]
  eks_cpu_node_min            = 1
  eks_cpu_node_desired        = 1
  eks_cpu_node_max            = 3

  eks_gpu_node_instance_types = ["g5.xlarge"]
  eks_gpu_node_min            = 0
  eks_gpu_node_desired        = 0
  eks_gpu_node_max            = 2
}
