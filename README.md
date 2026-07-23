# llm-ollama-eks

Terraform and Argo CD implementation for a private Amazon EKS development
platform running Ollama and Open WebUI.

## Delivery model

- Terraform provisions AWS networking, IAM, EKS, managed add-ons, storage, and
  bootstraps Argo CD with Helm.
- Argo CD deploys Ollama and Open WebUI from repository-managed GitOps content.
- Ollama, Open WebUI, and Argo CD use ClusterIP services. Operators use local
  `kubectl port-forward` sessions; the dev design creates no public application
  endpoint.
- Infrastructure is delivered one reviewed and applied layer at a time.

See [the architecture specification](docs/SPEC.md) and
[the implementation plan](docs/PLAN.md).

## Prerequisites

- Terraform 1.10 or newer
- AWS CLI v2 with credentials for the target account
- kubectl
- Helm

## Local configuration

Run Terraform from the `infra/` directory. Copy
`infra/terraform.tfvars.example` to the ignored `infra/terraform.tfvars` file
and review all settings. In particular, refresh the workstation public IPv4
allowlist:

```powershell
curl.exe -4 https://ifconfig.me
```

Store the result as a `/32` entry in
`eks_endpoint_public_access_cidrs`. Never commit credentials, Terraform
state, backend configuration, kubeconfig files, or plaintext Kubernetes Secrets.

Each implementation layer supplies its own reviewed saved-plan apply command.

```powershell
Set-Location infra
terraform init
terraform validate
```
