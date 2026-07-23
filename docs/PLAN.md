# Implementation Plan

## 1. Objective

Implement the AWS architecture defined in `docs/SPEC.md` so the repository can
provision an Amazon EKS cluster with Terraform and deploy Ollama and Open WebUI
with pinned Helm chart versions.

The initial target is a cost-conscious `dev` environment in `us-east-1` with
private worker nodes, one NAT Gateway, CPU inference by default, and optional GPU
inference.

## 2. Delivery principles

- Complete and verify each phase before starting work that depends on it.
- Keep Terraform inputs small; derive names, subnet ranges, tags, and identifiers
  where practical.
- Pin Terraform providers, EKS add-ons, Helm charts, container images, and the
  Ollama model tag for repeatable deployments.
- Never commit credentials, backend configuration, variable values, kubeconfig,
  Terraform state, or plan files.
- Use separate Terraform root modules for backend bootstrap and the platform.
- Prefer EKS Pod Identity for AWS access from Kubernetes workloads.
- Keep Ollama, Open WebUI, and Argo CD private behind ClusterIP services.
- Treat GPU support as an optional path that does not block the CPU-based base
  deployment.

## 3. Milestones

| Milestone                    | Outcome                                                      | Depends on |
| ---------------------------- | ------------------------------------------------------------ | ---------- |
| M1: Repository foundation    | Terraform structure, constraints, examples, and checks exist | None       |
| M2: State bootstrap          | Secure remote state backend is available                     | M1         |
| M3: Network foundation       | Multi-AZ VPC, subnets, routing, and endpoints are ready      | M2         |
| M4: EKS foundation           | Cluster, access, node groups, and core add-ons are healthy   | M3         |
| M5: Cluster services         | Storage and controllers are ready for workloads              | M4         |
| M6: LLM workloads            | Ollama and Open WebUI run with persistent storage            | M5         |
| M7: Operator access          | Open WebUI is reachable through a local port-forward         | M6         |
| M8: Operations and hardening | Monitoring, backup, documentation, and acceptance tests pass | M7         |

## 4. Detailed work plan

### Phase 0: Confirm deployment decisions

Status: **Complete — July 22, 2026**

| Decision           | Selected value                                                                                          |
| ------------------ | ------------------------------------------------------------------------------------------------------- |
| AWS region         | `us-east-1` (corrected from `us-ease-1`)                                                                |
| Environment        | `dev`                                                                                                   |
| EKS version        | `1.35`, confirmed in current EKS standard support                                                       |
| EKS API access     | Public and private endpoints; public restricted to `99.243.74.50/32`                                    |
| Application access | ClusterIP services with local `kubectl port-forward`; no ALB/public IP                                  |
| General nodes      | `t3.large`, EKS-optimized AL2023                                                                        |
| Initial inference  | CPU; GPU node group disabled                                                                            |
| Optional GPU       | One `g5.xlarge`, EKS-optimized AL2023 NVIDIA                                                            |
| Ollama model       | `llama3.2:3b`                                                                                           |
| Persistent storage | Ollama 100 GiB and Open WebUI 10 GiB, encrypted gp3                                                     |
| NAT                | One NAT Gateway for dev                                                                                 |
| Secrets            | Kubernetes Secrets, never committed in plaintext                                                        |
| Delivery ownership | Terraform provisions infrastructure and bootstraps Argo CD via Helm; Argo CD owns Ollama and Open WebUI |
| Destruction        | Application PVCs and EBS volumes are deleted with the dev environment                                   |

Before provisioning billable resources, record the following environment choices
in `terraform.tfvars`:

- AWS account and `us-east-1` region access are available.
- EKS public endpoint administrator CIDR: `99.243.74.50/32`, refreshed with
  `curl.exe -4 https://ifconfig.me` if the workstation IP changes.
- Open WebUI has no public endpoint and is accessed by local port-forward.
- Initial Ollama model: `llama3.2:3b`, subject to license approval.
- CPU-only inference initially; the GPU node group remains disabled.
- If GPU is enabled, confirm `g5.xlarge` availability and EC2 GPU quota.
- No Route 53 name, ACM certificate, ALB, or public application IP is required.
- State bucket names must be globally unique.

Exit criteria:

- No CIDR defaults to `0.0.0.0/0`; EKS access is restricted to
  `99.243.74.50/32`.
- The model fits within the selected node memory/GPU memory and the 100 GiB
  default model volume.
- Estimated recurring costs for EKS, NAT Gateway, EBS, and optional GPU are
  accepted.

### Phase 1: Establish the repository foundation

Current implementation note: the Terraform root is `infra/`. Public inputs have
been reduced to `env`, `eks_endpoint_public_access_cidrs`, and `tags`. Region,
VPC CIDR/AZ count, EKS version, and CPU/GPU node-group sizing are locals.

Create the `infra/` Terraform root described by the specification:

```text
infra/
|-- 01-variables.tf
|-- 02-locals.tf
|-- 03-providers.tf
|-- 04-outputs.tf
|-- vpc.tf
|-- kms.tf
|-- eks.tf
|-- eks-addons.tf
|-- iam.tf
|-- storage.tf
|-- controllers.tf
|-- argocd.tf
|-- monitoring.tf
|-- backend.hcl.example
`-- terraform.tfvars.example
```

GitOps application definitions live outside the Terraform root under `gitops/`.
The separately initialized backend stack lives under `bootstrap/`.

Tasks:

1. Add `.gitignore` entries for `.terraform/`, `*.tfstate*`, `*.tfplan`,
   `backend.hcl`, `terraform.tfvars`, kubeconfig files, and generated secrets.
2. Set the required Terraform version and compatible provider constraints.
3. Configure the AWS provider with `local.default_tags`.
4. Declare and validate the minimal inputs in `docs/SPEC.md`.
5. Implement locals for metadata, region, VPC, EKS, and node-group sizing.
6. Add resource outputs layer-by-layer without credentials or secret values.
7. Commit `.terraform.lock.hcl` after the first successful initialization.
8. Add a README quick-start section and document prerequisites: Terraform, AWS
   CLI, kubectl, and Helm. Document Argo CD as the application reconciler.
9. Add local or CI checks for `terraform fmt -check`, `terraform validate`,
   TFLint, and Checkov or Trivy configuration scanning.

Verification:

```powershell
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
tflint --recursive
```

Exit criteria:

- Examples contain all required non-secret settings.
- Validation rejects invalid environments, CIDRs, Kubernetes versions, and
  storage sizes.
- Formatting and static checks pass.

### Phase 2: Create the Terraform state bootstrap stack

Implement the independent `bootstrap/` Terraform stack.

Tasks:

1. Create an S3 state bucket with versioning, encryption, ownership controls,
   public access blocking, and lifecycle protection.
2. Enable native S3 lockfiles if supported by the selected Terraform version;
   otherwise create a DynamoDB lock table.
3. Apply project, environment, management, and repository tags.
4. Output the backend values needed by `backend.hcl`.
5. Populate local `backend.hcl` from `backend.hcl.example`.
6. Reinitialize the `infra/` configuration against the remote backend.

Verification:

- S3 public access is blocked.
- Bucket versioning and encryption are enabled.
- A test plan creates and releases the state lock.
- `backend.hcl` and all state files remain untracked.

Exit criteria:

- The platform state is remote, encrypted, versioned, and locked.

### Phase 3: Build networking and encryption

Implement `vpc.tf` and `kms.tf`.

Tasks:

1. Select three available AZs in the configured region.
2. Create the `10.0.0.0/16` VPC with DNS support and DNS hostnames enabled.
3. Derive and create three public and three private subnets.
4. Apply EKS cluster and load-balancer discovery subnet tags.
5. Create an Internet Gateway and public route table.
6. Create one NAT Gateway for dev; support one-per-AZ for production.
7. Create private route tables and associate them with private subnets.
8. Create a customer-managed KMS key with rotation for EKS secrets, EBS, and
   applicable logs.
9. Consider S3 and ECR VPC endpoints after measuring NAT traffic; do not add
   endpoints whose fixed cost exceeds their dev benefit.

Verification:

- All six subnets occupy non-overlapping ranges across three AZs.
- Public subnets reach the Internet Gateway.
- Private subnets have outbound access through the intended NAT Gateway.
- No worker subnet assigns public IPs automatically.
- All resources have required tags.

Exit criteria:

- The network plan matches the CIDRs and routing model in `docs/SPEC.md`.

### Phase 4: Provision EKS, access, and node groups

Implement `eks.tf` and the base portions of `iam.tf`.

Tasks:

1. Create separate least-privilege cluster and worker-node IAM roles.
2. Create the EKS cluster in private subnets using Kubernetes `1.35`, after
   confirming that version is available in `us-east-1`.
3. Enable KMS envelope encryption and all specified control-plane logs.
4. Enable the private API endpoint and restrict the public endpoint to the
   configured administrator CIDRs.
5. Grant administrators access through EKS access entries.
6. Create the general managed node group with `t3.large`, encrypted 50 GiB gp3
   roots, labels, and `1/2/3` scaling.
7. Add the optional GPU managed node group with its labels, taint, encrypted
   100 GiB roots, and `0/1/1` scaling.
8. Set safe rolling-update parameters and node metadata security settings.

Verification:

```powershell
aws eks describe-cluster --name <cluster-name>
aws eks update-kubeconfig --name <cluster-name> --region us-east-1
kubectl get nodes -o wide
kubectl auth can-i get pods --all-namespaces
```

Exit criteria:

- The cluster is active.
- Expected CPU nodes are Ready and have no public IP addresses.
- Access entries work without manually editing `aws-auth`.
- GPU resources are not created when `enable_gpu = false`.

### Phase 5: Install EKS add-ons and cluster controllers

Implement `eks-addons.tf`, remaining `iam.tf`, `storage.tf`, and
`controllers.tf`.

Tasks:

1. Resolve, test, and pin EKS-compatible versions of VPC CNI, CoreDNS,
   kube-proxy, EBS CSI, and Pod Identity Agent.
2. Create an EKS Pod Identity association and least-privilege IAM role for EBS
   CSI.
3. Create the encrypted gp3 StorageClass with `WaitForFirstConsumer`, expansion,
   and `Delete` reclaim behavior for dev.
4. Resolve, test, and pin Helm versions for metrics-server and Argo CD.
5. Install Argo CD through Terraform Helm and expose it only as ClusterIP.
6. Install the NVIDIA device plugin only when GPU support is enabled.
7. Wait for deployments and daemon sets to become Ready before deploying
   application charts.

Verification:

```powershell
kubectl get pods -A
kubectl get storageclass
kubectl get csidriver
helm list -A
```

For GPU deployments, also verify allocatable `nvidia.com/gpu` resources on the
GPU node.

Exit criteria:

- Core add-ons and controllers are healthy.
- Dynamic encrypted EBS provisioning succeeds with a temporary PVC and pod.
- Pinned versions are recorded in Terraform and the dependency lock file.

### Phase 6: Deploy Ollama

Create the Ollama GitOps application definition reconciled by Argo CD. Terraform
must not manage the Ollama Helm release directly.

Tasks:

1. Create the `llm` namespace.
2. Select the maintained Ollama chart, review its release notes, and pin the
   latest compatible chart version.
3. Configure one replica with a ClusterIP service on port `11434`.
4. Attach an encrypted 100 GiB gp3 PVC at `/root/.ollama`.
5. Add CPU/memory requests, limits, and health probes.
6. When GPU is enabled, add the node selector, taint toleration, and one-GPU
   resource limit. Otherwise schedule on the general node group.
7. Configure an idempotent model-pull mechanism using the pinned
   `llama3.2:3b` value in the Argo CD-managed Helm values.
8. Use a deployment strategy compatible with the single RWO volume, normally
   `Recreate`.
9. Ensure no public Service or Ingress is created.

Verification:

```powershell
kubectl -n llm get pods,pvc,svc
kubectl -n llm exec deploy/<ollama-deployment> -- ollama list
kubectl -n llm run ollama-test --rm -i --restart=Never --image=curlimages/curl -- `
  curl -s http://<ollama-service>:11434/api/tags
```

Run a small inference request and restart the pod to confirm that the model is
not downloaded again.

Exit criteria:

- Ollama is Ready and responds inside the cluster.
- The selected model persists across a pod restart.
- With GPU enabled, inference uses the GPU node and device.
- Ollama has no externally reachable endpoint.

### Phase 7: Deploy Open WebUI

Create the Open WebUI GitOps application definition reconciled by Argo CD.
Terraform must not manage the Open WebUI Helm release directly.

Tasks:

1. Select the official Open WebUI chart, review its release notes, and pin the
   latest compatible chart version.
2. Configure the internal Ollama service URL.
3. Attach an encrypted 10 GiB gp3 PVC at `/app/backend/data`.
4. Set one replica with appropriate resource requests, limits, and health
   probes.
5. Enable authentication and create Kubernetes bootstrap secrets out-of-band
   without committing plaintext or rendered Secret manifests.
6. Document that Kubernetes administrators can read these secrets and ensure EKS
   envelope encryption is active.
7. Confirm Open WebUI can list and invoke the configured Ollama model.

Verification:

- Open WebUI is Ready.
- Its logs contain no Ollama connection errors or secret values.
- A pod restart preserves Open WebUI application data.
- A temporary port-forward permits authenticated login and model inference.

Exit criteria:

- The complete application path works inside the cluster before public ingress
  is enabled.

### Phase 8: Configure private operator access

Tasks:

1. Keep Argo CD, Open WebUI, and Ollama services as ClusterIP.
2. Confirm no Ingress or LoadBalancer service exists.
3. Restrict the public EKS endpoint to `99.243.74.50/32`.
4. Document commands that bind port-forwards only to `127.0.0.1`.
5. Port-forward Open WebUI for user access and Argo CD for operations.
6. Document how to refresh the allowlist after a public IP change.

Verification:

```powershell
kubectl -n llm port-forward --address 127.0.0.1 service/<open-webui-service> 8080:80
```

- `http://127.0.0.1:8080` returns Open WebUI while the port-forward is running.
- No application service has an external IP or hostname.
- The EKS API rejects connections outside the configured `/32`.

Exit criteria:

- Open WebUI is reachable only through an authenticated local port-forward.

### Phase 9: Add observability, backup, and operational safeguards

Implement `monitoring.tf` and supporting documentation.

Tasks:

1. Set CloudWatch control-plane log retention to 30 days for dev.
2. Install/configure the chosen container and node metrics integration.
3. Add alarms for unhealthy nodes, crash loops,
   PVC usage, and application probe failures.
4. Add GPU utilization and memory alarms when GPU support is enabled.
5. Define disruption budgets for components with more than one replica.
6. Document EBS snapshot/AWS Backup configuration for production and perform a
   sample data restore.
7. Create an upgrade runbook covering EKS, node AMIs, add-ons, providers, Helm
   charts, Open WebUI, Ollama, and model changes.
8. Create a destroy runbook that explicitly deletes application PVCs before EKS
   teardown and preserves only Terraform state/backend resources.
9. Add cost-allocation tags and document cost review commands/dashboards.

Exit criteria:

- Logs and metrics are visible.
- At least one test alarm is exercised.
- Restore and upgrade procedures are documented.
- Destructive PVC and EBS cleanup behavior is understood before any destroy
  operation.

### Phase 10: Run final acceptance and handoff

Execute every acceptance test in `docs/SPEC.md` and save a deployment record that
includes:

- Terraform and provider versions.
- EKS version and managed add-on versions.
- Helm chart and application versions.
- Node AMI release versions and instance types.
- Pinned Ollama model tag.
- Terraform plan summary.
- URLs and non-sensitive resource identifiers.
- Test results, known limitations, and outstanding production hardening items.

Final commands:

```powershell
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra validate
terraform -chdir=infra plan -input=false -out=platform.tfplan
terraform -chdir=infra show platform.tfplan
kubectl get nodes,pods -A
helm list -A
```

Exit criteria:

- All specification acceptance criteria pass.
- No secrets or generated local artifacts are tracked by Git.
- The plan produces no unexplained changes immediately after a successful apply.
- A new operator can deploy, test, upgrade, and safely tear down the dev
  environment using repository documentation.

## 5. Suggested pull request sequence

Keep changes reviewable and ensure each pull request has a useful validation
boundary.

1. `foundation`: Terraform structure, providers, variables, locals, examples,
   CI/static checks, and documentation.
2. `state-backend`: independent bootstrap stack and backend configuration.
3. `network-kms`: VPC, subnets, routing, KMS, and outputs.
4. `eks`: control plane, access entries, CPU node group, and optional GPU group.
5. `cluster-services`: managed add-ons, Pod Identity, storage, metrics-server,
   Argo CD bootstrap, and optional NVIDIA plugin.
6. `ollama`: private inference service, persistence, scheduling, and model pull.
7. `open-webui`: UI, persistence, authentication, and internal Ollama connection.
8. `private-access`: ClusterIP verification and port-forward runbook.
9. `operations`: monitoring, backup/restore, runbooks, acceptance evidence, and
   production hardening.

## 6. Risk register

| Risk                                                      | Impact                                       | Mitigation                                                                                                            |
| --------------------------------------------------------- | -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| EKS `1.35` is unavailable in the target region            | Cluster creation fails                       | Query supported versions before planning; change the input to the newest supported version and update the spec record |
| GPU quota or capacity is unavailable                      | GPU node group cannot launch                 | Validate quota early; begin with CPU mode; request quota or approve an alternate GPU type                             |
| Model exceeds node memory or disk                         | Pod eviction, OOM, or failed download        | Select and pin an appropriately sized model; increase node/PVC size before deployment                                 |
| Upstream Helm chart changes values or behavior            | Deployment or upgrade fails                  | Pin exact versions, render charts, review release notes, and test upgrades in dev                                     |
| Single NAT Gateway fails                                  | Private nodes lose outbound access           | Accept in dev; use one NAT per AZ in production                                                                       |
| Single Ollama replica is disrupted                        | Inference is temporarily unavailable         | Use maintenance windows; design per-replica storage and multiple GPU nodes before production HA                       |
| EBS volume is tied to one AZ                              | Rescheduling may be delayed or blocked       | Use `WaitForFirstConsumer`, retain and back up data, and test recovery                                                |
| Kubernetes Secrets are readable by cluster administrators | Sensitive data exposure                      | Use least-privilege RBAC, EKS envelope encryption, and never commit plaintext Secret manifests                        |
| Workstation public IP changes                             | EKS API and port-forward access stop working | Re-run `curl.exe -4 https://ifconfig.me` and update the `/32` variable                                                |
| Unrestricted public endpoints                             | Unauthorized access                          | Require explicit administrator/client CIDRs, authentication, HTTPS, and production WAF/private EKS endpoint           |
| NAT and GPU resources generate unexpected cost            | Budget overrun                               | Tag resources, create budgets/alerts, disable GPU by default, and destroy unused dev environments                     |

## 7. Definition of done

The project is done when Terraform reproducibly creates the documented AWS and
EKS architecture and bootstraps pinned Argo CD, Argo CD deploys pinned Ollama
and Open WebUI releases, the chosen
model performs an inference request through authenticated Open WebUI, data
survives pod restarts, Ollama remains private, monitoring is operational, and
all acceptance criteria in `docs/SPEC.md` have recorded passing evidence.
