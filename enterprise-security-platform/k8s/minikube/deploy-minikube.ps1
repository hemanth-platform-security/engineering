# Start a lightweight local Kubernetes cluster with Minikube.

$ErrorActionPreference = 'Stop'

if (-not (Get-Command minikube -ErrorAction SilentlyContinue)) {
    Write-Error "minikube not found in PATH. Install it from https://minikube.sigs.k8s.io/docs/start/"
    exit 1
}

$args = @('start')

if ($env:MINIKUBE_DRIVER) {
    $args += @('--driver', $env:MINIKUBE_DRIVER)
}
if ($env:MINIKUBE_CPUS) {
    $args += @('--cpus', $env:MINIKUBE_CPUS)
}
if ($env:MINIKUBE_MEMORY) {
    $args += @('--memory', $env:MINIKUBE_MEMORY)
}
if ($env:MINIKUBE_DISK_SIZE) {
    $args += @('--disk-size', $env:MINIKUBE_DISK_SIZE)
}
if ($env:MINIKUBE_KUBERNETES_VERSION) {
    $args += @('--kubernetes-version', $env:MINIKUBE_KUBERNETES_VERSION)
}
if ($env:MINIKUBE_PROFILE) {
    $args += @('--profile', $env:MINIKUBE_PROFILE)
}

Write-Host "Starting Minikube with: minikube $($args -join ' ')"
& minikube @args
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Minikube is ready. Verify it with: kubectl get nodes"