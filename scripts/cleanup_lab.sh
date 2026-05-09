#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"
cd "$ROOT_DIR"

export AWS_PROFILE="${AWS_PROFILE:-friend-shopcloud}"
REGION="${REGION:-us-east-1}"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-cicd-lab}"

TFSTATE_BUCKET_FALLBACK="${TF_STATE_BUCKET:-cicd-lab-tfstate-youssef-lab010-n4h8pz}"
DEMO_BUCKET_FALLBACK="$(grep -E '^\s*bucket_suffix' terraform/terraform.tfvars 2>/dev/null | sed -n 's/.*=\s*"\(.*\)".*/cicd-lab-demo-\1/p' || true)"

printf '\n'
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
printf '⚠️  Lab 010 cleanup destroys AWS resources billed to account\n'
printf '    PROFILE=%s REGION=%s CLUSTER=%s\n' "${AWS_PROFILE}" "${REGION}" "${CLUSTER_NAME}"
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
printf '\nType DELETE-LAB-010 to proceed (anything else aborts).\n'
read -r ACK
if [[ "${ACK}" != "DELETE-LAB-010" ]]; then
  printf 'Aborted.\n'
  exit 1
fi

if ! aws configure list-profiles 2>/dev/null | grep -qx "${AWS_PROFILE}"; then
  printf 'Profile %s missing.\n' "${AWS_PROFILE}" >&2
  exit 2
fi

log_id() {
  aws sts get-caller-identity --profile "${AWS_PROFILE}" --output yaml
}

log_id || true

if kubectl delete namespace dev prod --ignore-not-found --wait=false >/dev/null 2>&1; then
  printf 'Marked dev/prod namespaces for deletion.\n'
fi

TF_DIR="$ROOT_DIR/terraform"
if [[ -d "${TF_DIR}/.terraform" ]]; then
  pushd "${TF_DIR}" >/dev/null
  if terraform init -backend=false >/dev/null 2>&1; then
    terraform destroy -auto-approve || printf 'terraform destroy failed — inspect state.\n' >&2
  else
    printf 'terraform init failed — skipping destroy.\n'
  fi
  popd >/dev/null
else
  printf 'terraform/.terraform missing — skipping terraform destroy unless you initialize first.\n'
fi

eksctl delete cluster --name "${CLUSTER_NAME}" --region "${REGION}" --profile "${AWS_PROFILE}" \
  --wait ||
  aws eks delete-cluster --name "${CLUSTER_NAME}" --region "${REGION}" --profile "${AWS_PROFILE}" || printf 'cluster delete skipped or failed\n'

aws ecr delete-repository --repository-name k8s-frontend --force --region "${REGION}" --profile "${AWS_PROFILE}" >/dev/null 2>&1 || true
aws ecr delete-repository --repository-name k8s-backend --force --region "${REGION}" --profile "${AWS_PROFILE}" >/dev/null 2>&1 || true

if aws s3 ls "s3://${TFSTATE_BUCKET_FALLBACK}" --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
  aws s3 rb "s3://${TFSTATE_BUCKET_FALLBACK}" --force --profile "${AWS_PROFILE}" || printf 'could not fully delete tfstate bucket %s\n' "${TFSTATE_BUCKET_FALLBACK}"
else
  printf 'tfstate bucket %s absent or inaccessible\n' "${TFSTATE_BUCKET_FALLBACK}"
fi

if [[ -n "${DEMO_BUCKET_FALLBACK}" ]] && aws s3 ls "s3://${DEMO_BUCKET_FALLBACK}" --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
  aws s3 rb "s3://${DEMO_BUCKET_FALLBACK}" --force --profile "${AWS_PROFILE}" || true
fi

aws dynamodb delete-table --table-name cicd-lab-tflocks --region "${REGION}" --profile "${AWS_PROFILE}" >/dev/null 2>&1 || printf 'dynamo cicd-lab-tflocks delete skipped.\n'

if aws iam get-user --user-name cicd-lab-github --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
  printf '\n⚠ IAM user cicd-lab-github detected — detach policies and delete access keys manually;\n\
this script skips automated IAM user deletion.\nSuggested:\n\
  aws iam list-attached-user-policies --user-name cicd-lab-github --profile %s\n\
  aws iam detach-user-policy --user-name cicd-lab-github --policy-arn <arn> ...\n' "${AWS_PROFILE}"
fi

remaining_clusters="$(aws eks list-clusters --region "${REGION}" --profile "${AWS_PROFILE}" \
  --query "clusters[?@=='${CLUSTER_NAME}']" --output text || true)"

REPOS="$(aws ecr describe-repositories --repository-names k8s-frontend k8s-backend --region "${REGION}" --profile "${AWS_PROFILE}" >/dev/null 2>&1 && echo yes || true)"

[[ -z "${remaining_clusters}" ]] || printf '\n⚠ WARNING: Cluster %s may still exist: %s\n' "${CLUSTER_NAME}" "${remaining_clusters}"
[[ -z "${REPOS}" ]] || printf '\n⚠ WARNING: Check ECR repositories still listed.\n'

printf '\ncleanup_lab finished preliminary checks.\n'
