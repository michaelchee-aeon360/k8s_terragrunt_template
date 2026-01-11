# Kubernetes & Terragrunt Project Template

This repository serves as a standardized reference for structuring Kubernetes manifests and Infrastructure as Code (IaC) using Terragrunt. It establishes the architectural patterns, naming conventions, and CI/CD standards required for internal teams.

---

## 📂 Repository Structure

### 1. Kubernetes (`/k8s`)

The Kubernetes configuration utilizes a **Helm-integrated Kustomize** pattern. This approach standardizes base deployments via Helm while providing environment-specific flexibility through Kustomize overlays.

* **`/helm-charts`**: Contains localized Helm charts (e.g., `common-apps`) that serve as the foundation for multiple applications. These charts include standard templates for Deployments, Services, HPAs, and Service Accounts.
* **`/apps`**: Houses application-specific configurations organized by environment.
* **`/base`**: Defines the "source of truth". It includes a `kustomization.yaml` that calls the relevant Helm chart and a `values.yaml` for shared configuration.
* **`/dev`, `/staging`, `/prod`, `/dr**`: Environment-specific overlays. These directories contain patches to adjust replicas, ingress URLs, or IAM service account annotations per environment.



### 2. Terragrunt (`/terragrunt`)

Infrastructure management is handled via Terragrunt to ensure DRY (Don't Repeat Yourself) Terraform code.

* **`/modules`**: Contains pure Terraform resource definitions (e.g., Firestore, IAM).
* **`/environments`**: A hierarchical live infrastructure tree.
* **`root.hcl`**: The central configuration file. It manages global locals (Project ID, Region), remote state in GCS buckets (named `${env}-${project_id}-tfstate`), and provider generation.
* **Resource Tree**: Organized by `environment / project / region / resource` (e.g., `dev/a360-dev-data/asia-southeast1/firestore`).



---

## 🚀 CI/CD Pipelines

### Kubernetes CI (`k8s-ci.yaml`)

Triggered on Pull Requests to `k8s/apps/**`.

* **Validation**: Enforces valid YAML syntax and lowercase, dashed app names via `validate-yaml-and-app-names.sh`.
* **Impact Detection**: Uses `detect-changed-envs.sh` to identify affected environments based on manifest or Helm chart changes.
* **Kustomize Diff**: Runs `kustomize-diff.sh` to generate a visual diff of the rendered manifests.

### Terragrunt CI/CD

The Terragrunt pipeline is designed for safety and automated orchestration:

* **PR Plan (`terragrunt-pr-plan.yaml`)**: Runs formatting checks and validations on pull requests.
* **Apply (`terragrunt-apply.yaml`)**: Executes changes upon merging into the `main` branch.
* **Concurrency Control**: The pipeline is limited to one active run at a time (`group: terragrunt-apply`) to prevent state lock conflicts during deployments.
* **Production Gate**: The apply job is tied to the `production` environment, requiring manual approval before the infrastructure changes are executed.
## ⛓️ Terragrunt Handling Dependencies

To manage complex infrastructures without manually modifying CI/CD workflows, we leverage Terragrunt's native orchestration capabilities.

**How to solve dependency problems without changing the CI:**

When Resource B depends on Resource A (e.g., a Database requiring a Service Account), use the **`run --all`** command provided by Terragrunt.

1. **Use `dependency` Blocks**: Define a `dependency` block in your `terragrunt.hcl` to pull outputs from a parent module. [Terragrunt Dependencies Block](https://terragrunt.gruntwork.io/docs/reference/hcl/blocks/#dependencies), [Terragrunt Dependency Block](https://terragrunt.gruntwork.io/docs/reference/hcl/blocks/#dependency)
2. **`run --all` Orchestration**: Our CI is configured to use `terragrunt run --all plan` and `terragrunt run --all apply`. This command automatically discovers the dependency graph and executes modules in the correct order.
3. **No CI Changes Required**: By using `run --all`, we do not need to update GitHub Action files when adding new resources or dependencies. Terragrunt handles the execution sequence dynamically based on the HCL configuration.
4. **Mock Outputs**: Always provide `mock_outputs` for the `plan` phase to allow CI to validate the entire stack even before upstream resources exist.

---

## 🛠 Standards & Requirements

* **Formatting**:
* **Terraform**: `terraform fmt --recursive`.
* **Terragrunt**: `terragrunt hcl fmt`.
* **Kubernetes**: `yq eval '.' -i <file>`.


* **Naming**: All Kubernetes application directories must follow lowercase, alphanumeric, and dash naming conventions.
* **Exclusions**: Local directories like `.terraform` and `.terragrunt-cache` are excluded from version control.