#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"
cd "$ROOT_DIR"

export AWS_PROFILE="${AWS_PROFILE:-friend-shopcloud}"
REGION="${REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-cicd-lab}"
LOG_PATH="${ROOT_DIR}/submission/COMMAND_LOG.md"

log_block() {
  local title="$1"
  shift
  {
    printf '\n## %s\n\n' "$title"
    printf '```text\n'
    "$@" 2>&1 || true
    printf '\n```\n'
  } >>"$LOG_PATH"
}

mkdir -p "${ROOT_DIR}/submission/screenshots"

if ! aws configure list-profiles 2>/dev/null | grep -qx "${AWS_PROFILE}"; then
  printf 'Profile %s missing. Available:\n%s\n' "$AWS_PROFILE" "$(aws configure list-profiles)" >&2
  exit 2
fi

log_block "sts get-caller-identity (${AWS_PROFILE})" aws sts get-caller-identity --profile "${AWS_PROFILE}"

if aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
  log_block "EKS cluster already exists (${CLUSTER_NAME})" aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" --profile "${AWS_PROFILE}" --output text
else
  log_block "eksctl create cluster (${CLUSTER_NAME})" \
    eksctl create cluster \
    --name "${CLUSTER_NAME}" \
    --region "${REGION}" \
    --nodegroup-name workers \
    --node-type t3.medium \
    --nodes 2 \
    --nodes-min 1 \
    --nodes-max 3 \
    --managed \
    --profile "${AWS_PROFILE}"
fi

log_block "aws eks update-kubeconfig" \
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}" --profile "${AWS_PROFILE}"

log_block "kubectl get nodes" kubectl get nodes -o wide

ACCOUNT="$(aws sts get-caller-identity --profile "${AWS_PROFILE}" --query Account --output text)"

for repo in k8s-frontend k8s-backend; do
  if aws ecr describe-repositories --repository-names "${repo}" --region "${REGION}" --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
    log_block "ECR repo exists (${repo})" aws ecr describe-repositories --repository-names "${repo}" --region "${REGION}" --profile "${AWS_PROFILE}" --output text
  else
    log_block "ECR create-repository (${repo})" aws ecr create-repository --repository-name "${repo}" --region "${REGION}" --profile "${AWS_PROFILE}"
  fi
done

if kubectl get ns dev >/dev/null 2>&1; then
  printf 'namespace dev exists\n'
else
  kubectl create namespace dev
fi
if kubectl get ns prod >/dev/null 2>&1; then
  printf 'namespace prod exists\n'
else
  kubectl create namespace prod
fi

log_block "kubectl get namespaces" kubectl get ns

printf '\nDONE setup_infra. Account=%s cluster=%s\n' "${ACCOUNT}" "${CLUSTER_NAME}"
