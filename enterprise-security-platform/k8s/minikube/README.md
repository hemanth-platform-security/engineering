# Minikube Development Cluster

Use Minikube for a lightweight local Kubernetes cluster instead of running a full OpenShift development cluster.

## Prerequisites

- Docker Desktop, Hyper-V, or another supported Minikube driver
- `minikube` in PATH ([installation guide](https://minikube.sigs.k8s.io/docs/start/))
- `kubectl` in PATH

## Quick start

PowerShell:

```powershell
cd k8s/minikube
$env:MINIKUBE_CPUS = '2'
$env:MINIKUBE_MEMORY = '4096'
.\deploy-minikube.ps1
kubectl get nodes
```

Bash:

```bash
cd k8s/minikube
export MINIKUBE_CPUS=2
export MINIKUBE_MEMORY=4096
./deploy-minikube.sh
kubectl get nodes
```

The scripts also support `MINIKUBE_DRIVER`, `MINIKUBE_DISK_SIZE`, `MINIKUBE_KUBERNETES_VERSION`, and `MINIKUBE_PROFILE`. Values are passed directly to `minikube start`.

To stop the cluster without deleting it, run `minikube stop`. To remove it completely, run `minikube delete`.