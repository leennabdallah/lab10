#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"
cd "$ROOT_DIR"

export AWS_PROFILE="${AWS_PROFILE:-friend-shopcloud}"
export REGION="${REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"

LOG_FILE="${ROOT_DIR}/submission/COMMAND_LOG.md"

log() {
  local line="[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
  printf '%s\n' "$line" | tee -a "$LOG_FILE"
}

log_block() {
  local title="$1"
  shift
  {
    printf '\n## %s\n\n' "$title"
    printf '```text\n'
    "$@" 2>&1 || true
    printf '\n```\n'
  } >>"$LOG_FILE"
}

require_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    log "OK: $1 found ($($1 --version 2>&1 | head -n 1 || echo version unknown))"
  else
    log "MISSING: $1 not found in PATH"
  fi
}

mkdir -p "$ROOT_DIR/submission/screenshots"

if [[ ! -f "$LOG_FILE" ]]; then
  printf '# Lab 010 command log\n\n' >"$LOG_FILE"
fi

log "preflight: starting from $ROOT_DIR"
log "preflight: AWS_PROFILE=$AWS_PROFILE REGION=$REGION"

log_block "aws configure list-profiles" aws configure list-profiles

mapfile -t PROFILES < <(aws configure list-profiles 2>/dev/null || true)
FOUND="false"
for p in "${PROFILES[@]+"${PROFILES[@]}"}"; do
  if [[ "$p" == "$AWS_PROFILE" ]]; then
    FOUND="true"
    break
  fi
done

if [[ "$FOUND" != "true" ]]; then
  log "ERROR: AWS profile '$AWS_PROFILE' is not configured."
  log "Available profiles: ${PROFILES[*]:-<(none)>}"
  log "Configure the correct profile before continuing."
  printf '\n❌ Aborting preflight — expected profile `%s`.\nAvailable: %s\n' "$AWS_PROFILE" "${PROFILES[*]:-<(none)>}" >&2
  exit 2
fi

require_cmd aws
require_cmd kubectl
require_cmd eksctl
require_cmd docker
require_cmd git
require_cmd node
require_cmd npm
require_cmd terraform

if command -v gh >/dev/null 2>&1; then
  log "OK: gh found ($("${GH:-gh}" --version 2>/dev/null | head -n 1 || echo gh))"
else
  log "MISSING: gh (GitHub CLI) not found — set secrets manually (see submission/CHECKLIST.md)"
fi

log_block "aws sts get-caller-identity" aws sts get-caller-identity --profile "$AWS_PROFILE"

export ACCOUNT_ID
ACCOUNT_ID="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
log "AWS account ID resolved: ${ACCOUNT_ID}"

if docker info >/dev/null 2>&1; then
  log_block "docker info (summary)" bash -c "docker info 2>/dev/null | head -n 40"
  log "OK: Docker daemon is reachable"
else
  log "ERROR: Docker daemon not running or inaccessible"
  printf '\n❌ Docker is required for image builds.\n' >&2
  exit 3
fi

SAFE_CWD="$(pwd)"
if [[ "$SAFE_CWD" =~ ^/(bin|boot|dev|etc|lib|sbin|sys|usr)$ ]]; then
  log "Refusing to run from unsafe cwd: $SAFE_CWD"
  exit 4
fi

log "preflight OK. ACCOUNT_ID exported for child scripts."
