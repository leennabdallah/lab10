#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"
cd "$ROOT_DIR"

export AWS_PROFILE="${AWS_PROFILE:-friend-shopcloud}"
REGION="${REGION:-us-east-1}"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-cicd-lab}"

fail() {
  printf 'VERIFY FAIL: %s\n' "$1" >&2
  FAILED=1
}

FAILED=0

if grep -rq '^[[:space:]]*namespace:[[:space:]]' manifests/ 2>/dev/null; then
  fail 'manifests/ must not contain explicit namespace metadata fields'
fi

required_files=(
  app/server.js
  app/package.json
  app/package-lock.json
  app/Dockerfile
  app/server.test.js
  app/server.integration.test.js
  app/frontend/index.html
  app/frontend/nginx.conf
  app/frontend/Dockerfile
  manifests/redis.yaml
  manifests/backend.yaml
  manifests/frontend.yaml
  terraform/main.tf
  terraform/variables.tf
  terraform/versions.tf
  terraform/terraform.tfvars
  .github/workflows/ci.yml
  .github/workflows/terraform.yml
  submission/screenshots
  submission/COMMAND_LOG.md
  scripts/preflight.sh
)

for f in "${required_files[@]}"; do
  [[ -e "$f" ]] || fail "missing $f"
done

if aws configure list-profiles 2>/dev/null | grep -qx "${AWS_PROFILE}"; then
  ACCOUNT="$(aws sts get-caller-identity --profile "${AWS_PROFILE}" --query Account --output text)"
  printf 'AWS_ACCOUNT_ID (%s): %s\n' "${AWS_PROFILE}" "${ACCOUNT}"

  aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" --profile "${AWS_PROFILE}" >/dev/null 2>&1 || fail "cluster ${CLUSTER_NAME} not found via AWS API"

  if kubectl get nodes >/dev/null 2>&1; then
    NOT_READY="$(kubectl get nodes --no-headers 2>/dev/null | awk '{if ($2 != "Ready") print}' || true)"
    if [[ -n "${NOT_READY}" ]]; then
      fail "kubectl reports non-Ready nodes"
    fi
  else
    fail "kubectl cannot query cluster (kubeconfig/context?)"
  fi

  for ns in dev prod; do
    kubectl get ns "${ns}" >/dev/null 2>&1 || fail "namespace ${ns} missing"
  done

  for repo in k8s-frontend k8s-backend; do
    aws ecr describe-repositories --repository-names "${repo}" --region "${REGION}" --profile "${AWS_PROFILE}" >/dev/null 2>&1 ||
      fail "ECR repo ${repo} missing"
  done

  check_pods_running() {
    local ns="$1"
    local bad
    bad="$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null | awk '{print $3}' | grep -v '^Running' | grep -v '^Succeeded' || true)"
    [[ -z "${bad}" ]] || fail "namespace ${ns} has pods not in Running/Succeeded state"
    local count
    count="$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')"
    [[ "${count}" -gt 0 ]] || fail "namespace ${ns} has no pods"
  }

  for ns in dev prod; do
    check_pods_running "${ns}"
  done

  for svc in redis-service backend-service frontend-service; do
    kubectl get svc "${svc}" -n dev >/dev/null 2>&1 || fail "dev service ${svc} missing"
    kubectl get svc "${svc}" -n prod >/dev/null 2>&1 || fail "prod service ${svc} missing"
  done

  for ns in dev prod; do
    kubectl rollout status deployment/backend -n "${ns}" --timeout=10s >/dev/null 2>&1 || fail "backend rollout unhealthy (${ns})"
    kubectl rollout status deployment/frontend -n "${ns}" --timeout=10s >/dev/null 2>&1 || fail "frontend rollout unhealthy (${ns})"
    kubectl rollout status deployment/redis -n "${ns}" --timeout=10s >/dev/null 2>&1 || fail "redis rollout unhealthy (${ns})"
  done
else
  fail "cannot verify AWS without profile ${AWS_PROFILE}"
fi

[[ -f .github/workflows/ci.yml ]] && printf 'Workflow present: ci.yml\n'
[[ -f .github/workflows/terraform.yml ]] && printf 'Workflow present: terraform.yml\n'

if command -v gh >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then
  printf 'GitHub CLI repo context reachable.\n'
fi

if [[ "${FAILED}" -eq 0 ]]; then
  printf '\nverify_lab completed without flagged failures.\n'
else
  printf '\nverify_lab exited with flagged failures — scroll up for VERIFY FAIL messages.\n' >&2
  exit 1
fi
