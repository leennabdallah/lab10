#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"
cd "$ROOT_DIR"

export AWS_PROFILE="${AWS_PROFILE:-friend-shopcloud}"
REGION="${REGION:-us-east-1}"
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

if ! aws configure list-profiles 2>/dev/null | grep -qx "${AWS_PROFILE}"; then
  printf 'Missing profile %s\n' "${AWS_PROFILE}" >&2
  exit 2
fi

ACCOUNT="$(aws sts get-caller-identity --profile "${AWS_PROFILE}" --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

export AWS_DEFAULT_REGION="$REGION"

log_block "docker login ECR" bash -lc "aws ecr get-login-password --region \"${REGION}\" --profile \"${AWS_PROFILE}\" | docker login --username AWS --password-stdin \"${REGISTRY}\""

log_block "docker build backend v1" docker build -t "${REGISTRY}/k8s-backend:v1" ./app

log_block "docker build frontend v1" docker build -t "${REGISTRY}/k8s-frontend:v1" ./app/frontend

log_block "docker push backend v1" docker push "${REGISTRY}/k8s-backend:v1"

log_block "docker push frontend v1" docker push "${REGISTRY}/k8s-frontend:v1"

log_block "kubectl apply dev" kubectl -n dev apply -f manifests/
log_block "kubectl apply prod" kubectl -n prod apply -f manifests/

log_block "kubectl set image dev" bash -lc "\
kubectl -n dev set image deployment/backend backend=${REGISTRY}/k8s-backend:v1;\
kubectl -n dev set image deployment/frontend frontend=${REGISTRY}/k8s-frontend:v1;\
kubectl -n dev set env deployment/backend APP_ENV=dev"

log_block "kubectl set image prod" bash -lc "\
kubectl -n prod set image deployment/backend backend=${REGISTRY}/k8s-backend:v1;\
kubectl -n prod set image deployment/frontend frontend=${REGISTRY}/k8s-frontend:v1;\
kubectl -n prod set env deployment/backend APP_ENV=prod"

log_block "kubectl rollout status dev/backend" kubectl -n dev rollout status deployment/backend --timeout=120s
log_block "kubectl rollout status dev/frontend" kubectl -n dev rollout status deployment/frontend --timeout=120s
log_block "kubectl rollout status prod/backend" kubectl -n prod rollout status deployment/backend --timeout=120s
log_block "kubectl rollout status prod/frontend" kubectl -n prod rollout status deployment/frontend --timeout=120s

log_block "kubectl get pods dev wide" kubectl get pods -n dev -o wide
log_block "kubectl get pods prod wide" kubectl get pods -n prod -o wide

printf '\nDONE seed_initial_deploy using account %s\n' "${ACCOUNT}"
