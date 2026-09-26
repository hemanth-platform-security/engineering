#!/usr/bin/env bash
set -euo pipefail

if ! command -v minikube >/dev/null 2>&1; then
  echo "Error: minikube not found in PATH. Install it from https://minikube.sigs.k8s.io/docs/start/" >&2
  exit 1
fi

args=(start)

if [[ -n "${MINIKUBE_DRIVER:-}" ]]; then
  args+=(--driver "$MINIKUBE_DRIVER")
fi
if [[ -n "${MINIKUBE_CPUS:-}" ]]; then
  args+=(--cpus "$MINIKUBE_CPUS")
fi
if [[ -n "${MINIKUBE_MEMORY:-}" ]]; then
  args+=(--memory "$MINIKUBE_MEMORY")
fi
if [[ -n "${MINIKUBE_DISK_SIZE:-}" ]]; then
  args+=(--disk-size "$MINIKUBE_DISK_SIZE")
fi
if [[ -n "${MINIKUBE_KUBERNETES_VERSION:-}" ]]; then
  args+=(--kubernetes-version "$MINIKUBE_KUBERNETES_VERSION")
fi
if [[ -n "${MINIKUBE_PROFILE:-}" ]]; then
  args+=(--profile "$MINIKUBE_PROFILE")
fi

echo "Starting Minikube with: minikube ${args[*]}"
minikube "${args[@]}"
echo "Minikube is ready. Verify it with: kubectl get nodes"