## Lab010 CI/CD Expanded — CHECKLIST / Manual steps

Student name wired for UI/GitHub screenshots: **Youssef Al Hajj Youness**  
Terraform demo suffix baked into repo examples: **`youssef-lab010-n4h8pz`**  
Terraform remote state bucket (CREATE MANUALLY in friend AWS account before `terraform init`):

```
cicd-lab-tfstate-youssef-lab010-n4h8pz
```

If that name is unavailable globally, regenerate a new `<random>` and update BOTH:

- `terraform/versions.tf` (`backend "s3"` block `bucket`)
- `terraform/terraform.tfvars` (`bucket_suffix` / tfvars may stay but bucket name differs)
- `$TF_STATE_BUCKET` when running S3/AWS CLI commands manually

Example creation (after `AWS_PROFILE=friend-shopcloud` works):

```
export TF_STATE_BUCKET=cicd-lab-tfstate-youssef-lab010-n4h8pz
aws s3api create-bucket \
  --bucket "$TF_STATE_BUCKET" \
  --region us-east-1 \
  --profile friend-shopcloud

aws s3api put-bucket-versioning \
  --bucket "$TF_STATE_BUCKET" \
  --versioning-configuration Status=Enabled \
  --profile friend-shopcloud

aws s3api put-public-access-block \
  --bucket "$TF_STATE_BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --profile friend-shopcloud

aws dynamodb create-table \
  --table-name cicd-lab-tflocks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1 \
  --profile friend-shopcloud

cd cicd-lab/terraform
terraform init   # AFTER bucket + lock table exist
```

### AWS profile blocker (CRITICAL — read first)

Configured profiles on THIS machine (`aws configure list-profiles`) reported **ONLY**:

- `default`
- `prod712`
- `hassane-admin`

The expected lab profile **`friend-shopcloud`** was **MISSING**.

**STOP** → add `friend-shopcloud` via `aws configure --profile friend-shopcloud`, then rerun:

```
aws sts get-caller-identity --profile friend-shopcloud
```

Do **NOT** rely on personal/default credentials unless that account is intentional for grading.

Secrets for GitHub Actions (manual if `gh` cannot):

| Secret Name | Typical value |
|---|---|
| AWS_ACCESS_KEY_ID | From IAM (`cicd-lab-github` user per lab guidance) |
| AWS_SECRET_ACCESS_KEY | Matching secret |
| AWS_REGION | `us-east-1` |
| AWS_ACCOUNT_ID | Output of STS call on friend profile |
| EKS_CLUSTER_NAME | `cicd-lab` |

### Local Redis for integration tests (optional before pushing)

GitHub Actions already attaches a Redis sidecar automatically. Locally you can mimic it with Docker:

```
docker run -d --rm --name lab010-redis -p 6379:6379 redis:7-alpine
cd cicd-lab/app
REDIS_HOST=127.0.0.1 npm run test:integration
docker stop lab010-redis
```

### Git repo + branching

Inside `Lab10/cicd-lab` the repository is already initialized on branch `main`:

```
git status
git remote add origin https://github.com/<OWNER>/<REPO>.git   # substitute your URL
git branch dev                                                # create AFTER first commit
```

Follow the agent's **COMMIT NEEDED** template for precise `git add` / messages.

### GitHub Actions environments

Configure **dev** (`no protection`) and **prod** (`required reviewers = you / instructor policy`) under **Repo → Settings → Environments**.

### Dedicated IAM lab user (`cicd-lab-github`)

Prefer creating this user ONLY in friend account; attach **`AdministratorAccess` strictly for transient lab grading** exactly as instructor states. Immediately delete afterward.

Do **NOT** paste access keys anywhere in repo or Slack; use GitHub secret UI (`Settings → Secrets and variables → Actions`).

### Screenshots cadence & filenames

Screenshots MUST be genuine — never fabricated. Paths live under:

```
submission/screenshots/
```

Await explicit instructions from instructor/agent before moving on:

1. `01_actions_dev_run.png` — Actions → dev workflow all green (`test → build → deploy-dev`).  
2. `02_actions_prod_run_waiting.png` — prod deployment waiting approval.  
3. `03_prod_approval_dialog.png` — modal “Review deployments”.  
4. `04_kubectl_pods_dev.png` — `kubectl get pods -n dev -o wide` (recent AGE column).  
5. `05_kubectl_pods_prod.png` — `kubectl get pods -n prod -o wide`.  
6. `06_browser_dev.png` — localhost:8080 DEV page + student name visibly.  
7. `07_browser_prod.png` — localhost:8081 prod page.  
8. `08_rollout_history.png` — `kubectl rollout history deployment/backend -n prod` (≥2 revisions).  
9. `09_trivy_output.png` — build job logs featuring Trivy table.  
10. `10_branch_protection.png` — branch protections on `main` + required checks.  
11. `11_terraform_pr_comment.png` — PR comment embedding Terraform Plan.  
12. `12_ci_yml.png` — full `.github/workflows/ci.yml` (zoom out acceptable).

Rebuild Word doc AFTER photos exist:

```
pip install python-docx
python3 scripts/make_submission_doc.py
```

(Optional PDF if LibreOffice installed.)

### Potential CI caveat — Trivy strictness

`ci.yml` uses `aquasecurity/trivy-action@master` with `exit-code: 1`. If Alpine base images regress with HIGH vulns blocking builds temporarily, escalate with instructor BEFORE loosening thresholds.

### Secret hygiene

Avoid committing snapshots showing raw AWS/session tokens.

### Cleanup deferral

Run `scripts/cleanup_lab.sh` **only AFTER** Evidence + Word doc finalized.
