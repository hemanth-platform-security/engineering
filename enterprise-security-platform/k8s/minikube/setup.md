# Minikube Setup on Windows with Git Bash

## Overview

This guide documents the setup of a local Kubernetes environment using **Minikube on Windows**, with **Git Bash** as the primary shell.

The environment is intended for Kubernetes, HashiCorp Vault, Platform Security, ServiceAccount JWT, Vault Agent, and Kubernetes authentication labs.

---

## Architecture

```text
Windows 11
   │
   ├── Git Bash
   │      │
   │      ├── kubectl
   │      └── minikube
   │
   └── Minikube
          │
          └── Kubernetes
                 │
                 ├── kube-apiserver
                 ├── kubelet
                 ├── etcd
                 ├── CoreDNS
                 └── ServiceAccounts
```

---

# 1. Prerequisites

The following components are required:

* Windows 10/11
* Git for Windows / Git Bash
* Docker Desktop
* kubectl
* Minikube

Recommended:

* 4+ CPU cores
* 8+ GB RAM
* 20+ GB available disk space
* Hardware virtualization enabled

---

# 2. Verify Git Bash

Open **Git Bash** and run:

```bash
uname -a
```

Verify Git:

```bash
git --version
```

Example:

```text
git version 2.x.x
```

---

# 3. Verify Docker

Check Docker:

```bash
docker version
```

Check Docker daemon:

```bash
docker info
```

Docker Desktop must be running.

If Docker is not running, Minikube using the Docker driver will fail to start.

---

# 4. Install kubectl

Verify whether kubectl is already installed:

```bash
kubectl version --client
```

Expected:

```text
Client Version: ...
```

Verify the executable:

```bash
which kubectl
```

Example:

```text
/c/Program Files/Kubernetes/kubectl.exe
```

---

# 5. Install Minikube

Verify:

```bash
minikube version
```

Example:

```text
minikube version: v1.x.x
```

Verify the executable:

```bash
which minikube
```

---

# 6. Configure Docker as Minikube Driver

Docker is a convenient driver on Windows.

Check available drivers:

```bash
minikube drivers
```

Start Minikube with Docker:

```bash
minikube start --driver=docker
```

If Docker is already configured as the default driver:

```bash
minikube start
```

---

# 7. Verify Minikube

Run:

```bash
minikube status
```

Expected:

```text
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
```

---

# 8. Verify Kubernetes Context

Check the current kubectl context:

```bash
kubectl config current-context
```

Expected:

```text
minikube
```

List contexts:

```bash
kubectl config get-contexts
```

Example:

```text
CURRENT   NAME       CLUSTER    AUTHINFO   NAMESPACE
*         minikube   minikube   minikube
```

---

# 9. Verify Kubernetes Cluster

Check the nodes:

```bash
kubectl get nodes
```

Expected:

```text
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   ...   v1.x.x
```

The node must show:

```text
STATUS: Ready
```

---

# 10. Verify Cluster Information

Run:

```bash
kubectl cluster-info
```

Example:

```text
Kubernetes control plane is running at https://...
CoreDNS is running at https://...
```

---

# 11. Verify System Pods

```bash
kubectl get pods -A
```

Typical system components include:

```text
kube-system
├── coredns
├── etcd-minikube
├── kube-apiserver-minikube
├── kube-controller-manager-minikube
├── kube-proxy
└── kube-scheduler-minikube
```

Check specifically:

```bash
kubectl get pods -n kube-system
```

All critical pods should eventually reach:

```text
Running
```

or an appropriate completed/ready state.

---

# 12. Verify Kubernetes API Server

Check the API server pod:

```bash
kubectl get pod kube-apiserver-minikube \
    -n kube-system
```

Expected:

```text
NAME                     READY   STATUS    RESTARTS   AGE
kube-apiserver-minikube  1/1     Running   0          ...
```

Inspect its configuration:

```bash
kubectl -n kube-system get pod kube-apiserver-minikube \
  -o jsonpath='{.spec.containers[0].command}'
```

---

# 13. Kubernetes ServiceAccount Configuration

For ServiceAccount/JWT labs, inspect the API server arguments:

```bash
kubectl -n kube-system get pod kube-apiserver-minikube \
  -o jsonpath='{.spec.containers[0].command}' | \
  tr ',' '\n' | \
  grep service-account
```

Typical output:

```text
--service-account-issuer=https://kubernetes.default.svc.cluster.local
--service-account-key-file=/var/lib/minikube/certs/sa.pub
--service-account-signing-key-file=/var/lib/minikube/certs/sa.key
```

These parameters are important for Kubernetes ServiceAccount JWT authentication.

---

# 14. Kubernetes Version

Check the client and server versions:

```bash
kubectl version
```

Or:

```bash
kubectl version --output=yaml
```

Check node version:

```bash
kubectl get nodes
```

Example from this lab:

```text
Kubernetes v1.34.0
```

---

# 15. Minikube Profile

List Minikube profiles:

```bash
minikube profile list
```

Example:

```text
| Profile  | Driver | Runtime | IP | Port |
|----------|--------|---------|----|------|
| minikube | docker | docker  | ...| ...  |
```

Check the active profile:

```bash
minikube profile
```

Set it explicitly if required:

```bash
minikube profile minikube
```

---

# 16. Minikube SSH

Connect to the Minikube node:

```bash
minikube ssh
```

Inside the node:

```bash
uname -a
```

Exit:

```bash
exit
```

---

# 17. Inspect Kubernetes Certificates

Minikube stores Kubernetes certificates inside the node.

For example:

```text
/var/lib/minikube/certs/
```

List them:

```bash
minikube ssh
```

Then:

```bash
sudo ls -la /var/lib/minikube/certs/
```

Important ServiceAccount files:

```text
sa.pub
sa.key
```

These correspond to:

```text
sa.key
   └── ServiceAccount JWT signing key

sa.pub
   └── ServiceAccount JWT verification key
```

### Security warning

Never copy or commit:

```text
sa.key
```

The private signing key must remain protected.

---

# 18. Git Bash Path Conversion

Git Bash uses MSYS path conversion.

This can cause problems when passing Linux paths to commands such as:

```bash
minikube ssh
```

For example:

```bash
minikube ssh -- cat /var/lib/minikube/certs/sa.pub
```

may incorrectly transform the Linux path into something similar to:

```text
C:/Program Files/Git/var/lib/minikube/certs/sa.pub
```

This results in:

```text
cat: 'C:/Program': No such file or directory
```

---

# 19. Disable Git Bash Path Conversion

Use:

```bash
MSYS_NO_PATHCONV=1
```

Example:

```bash
MSYS_NO_PATHCONV=1 minikube ssh -- \
    sudo cat /var/lib/minikube/certs/sa.pub
```

This preserves the Linux path.

---

# 20. Copy a Minikube File to Windows

For example, copy the Kubernetes ServiceAccount public key:

```bash
MSYS_NO_PATHCONV=1 minikube ssh -- \
    sudo cat /var/lib/minikube/certs/sa.pub > k8s-sa.pub
```

Verify:

```bash
cat k8s-sa.pub
```

Expected:

```text
-----BEGIN PUBLIC KEY-----
...
-----END PUBLIC KEY-----
```

Validate:

```bash
openssl pkey \
    -pubin \
    -in k8s-sa.pub \
    -text \
    -noout
```

---

# 21. Create a Test Namespace

Create a dedicated namespace for labs:

```bash
kubectl create namespace vault-lab
```

Verify:

```bash
kubectl get namespace vault-lab
```

---

# 22. Create a Test ServiceAccount

```bash
kubectl create serviceaccount vault-jwt-test \
    -n vault-lab
```

Verify:

```bash
kubectl get serviceaccount \
    vault-jwt-test \
    -n vault-lab
```

---

# 23. Generate a ServiceAccount JWT

Kubernetes provides short-lived ServiceAccount tokens using:

```bash
kubectl create token
```

Example:

```bash
kubectl create token vault-jwt-test \
    -n vault-lab
```

Store a token temporarily:

```bash
TOKEN=$(kubectl create token vault-jwt-test \
    -n vault-lab)
```

Check the token length without displaying it:

```bash
echo "${#TOKEN}"
```

---

# 24. Inspect JWT Claims

The JWT payload can be decoded for lab/debugging purposes:

```bash
python -c "import base64,json; p='$TOKEN'.split('.')[1]; p += '='*(-len(p)%4); print(json.dumps(json.loads(base64.urlsafe_b64decode(p)),indent=2))"
```

Important claims include:

```text
iss
aud
sub
exp
iat
nbf
```

Typical ServiceAccount identity:

```text
sub:
system:serviceaccount:vault-lab:vault-jwt-test
```

---

# 25. Stop Minikube

To stop the cluster without deleting it:

```bash
minikube stop
```

Verify:

```bash
minikube status
```

The host may be stopped while the cluster data remains intact.

---

# 26. Start Minikube Again

```bash
minikube start
```

Verify:

```bash
minikube status
```

Then:

```bash
kubectl get nodes
```

---

# 27. Restart Troubleshooting

If Minikube reports:

```text
host: Running
kubelet: Running
apiserver: Stopped
```

do not immediately delete the cluster.

First try:

```bash
minikube stop
minikube start
```

Then:

```bash
minikube status
kubectl get nodes
```

---

# 28. Minikube Logs

Check for detected problems:

```bash
minikube logs --problems
```

Get complete logs:

```bash
minikube logs
```

Save logs:

```bash
minikube logs > minikube.log
```

Search for common errors:

```bash
grep -Ei \
    'error|failed|apiserver|etcd|kubelet' \
    minikube.log
```

---

# 29. Kubernetes API Troubleshooting

Check API server pod:

```bash
kubectl get pod \
    kube-apiserver-minikube \
    -n kube-system
```

Check logs:

```bash
kubectl logs \
    kube-apiserver-minikube \
    -n kube-system
```

Check node:

```bash
kubectl get nodes
```

Check cluster information:

```bash
kubectl cluster-info
```

---

# 30. Reset Minikube

Only use this if the existing cluster is no longer required.

```bash
minikube delete
```

Then recreate:

```bash
minikube start --driver=docker
```

### Warning

`minikube delete` removes the Minikube cluster and its workloads.

Do not use it as the first troubleshooting step.

---

# 31. Recommended Project Structure

For a Kubernetes/Vault engineering repository:

```text
principal-engineer/
│
├── README.md
│
├── infrastructure/
│   └── minikube/
│       └── README.md
│
├── labs/
│   │
│   ├── 01-kubernetes-jwt-vault/
│   │   └── README.md
│   │
│   ├── 02-vault-agent/
│   │   └── README.md
│   │
│   ├── 03-projected-serviceaccount-token/
│   │   └── README.md
│   │
│   └── 04-vault-agent-injector/
│       └── README.md
│
├── kubernetes/
│   ├── namespaces/
│   ├── serviceaccounts/
│   └── deployments/
│
└── scripts/
    ├── minikube-start.sh
    └── minikube-cleanup.sh
```

---

# 32. Useful Daily Commands

### Cluster status

```bash
minikube status
```

### Kubernetes nodes

```bash
kubectl get nodes
```

### All pods

```bash
kubectl get pods -A
```

### Current context

```bash
kubectl config current-context
```

### Cluster information

```bash
kubectl cluster-info
```

### Minikube dashboard

```bash
minikube dashboard
```

### SSH into node

```bash
minikube ssh
```

### Minikube logs

```bash
minikube logs
```

---

# 33. Validation Checklist

Use the following checklist after installing Minikube:

* [ ] Docker Desktop running
* [ ] Git Bash working
* [ ] `kubectl` installed
* [ ] `minikube` installed
* [ ] Docker driver configured
* [ ] Minikube started
* [ ] Minikube API server running
* [ ] Kubernetes node `Ready`
* [ ] kubectl context set to `minikube`
* [ ] CoreDNS running
* [ ] Kubernetes system pods healthy
* [ ] ServiceAccount creation verified
* [ ] ServiceAccount JWT generation verified
* [ ] ServiceAccount issuer identified
* [ ] Git Bash path conversion understood

---

# 34. Final Environment

The completed lab environment looks like:

```text
┌───────────────────────────────────────────────────────────┐
│                     Windows                               │
│                                                           │
│  ┌──────────────────┐       ┌──────────────────────────┐ │
│  │    Git Bash      │       │       Docker Desktop     │ │
│  │                  │       │                          │ │
│  │ kubectl          │──────▶│       Minikube           │ │
│  │ minikube         │       │                          │ │
│  │ vault CLI        │       │  Kubernetes v1.34.x      │ │
│  └──────────────────┘       │                          │ │
│                             │  ┌────────────────────┐  │ │
│                             │  │ kube-apiserver     │  │ │
│                             │  │ kubelet             │  │ │
│                             │  │ etcd                │  │ │
│                             │  │ CoreDNS             │  │ │
│                             │  │ ServiceAccounts     │  │ │
│                             │  └────────────────────┘  │ │
│                             └──────────────────────────┘ │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

---

# 35. Next Labs

Once the Minikube environment is operational, the recommended progression is:

### Lab 01 — ServiceAccount + JWT

```text
ServiceAccount
      ↓
Bound JWT
      ↓
JWT claims
      ↓
JWT verification
```

### Lab 02 — External Vault JWT Authentication

```text
ServiceAccount
      ↓
JWT
      ↓
External Vault
      ↓
JWT Auth
      ↓
Vault Policy
```

### Lab 03 — Vault Agent Auto-Authentication

```text
Pod
 ↓
Projected JWT
 ↓
Vault Agent
 ↓
Vault JWT Auth
 ↓
Vault Token
```

### Lab 04 — Vault Agent Secret Injection

```text
Pod
 │
 ├── Application
 │
 └── Vault Agent
        │
        ▼
      Vault
        │
        ▼
      Secret
```

### Lab 05 — Production-Style Workload Identity

Explore:

* Custom JWT audiences
* Token rotation
* OIDC discovery
* JWKS
* Vault Agent
* Vault Agent Injector
* External Vault
* Kubernetes NetworkPolicy
* TLS
* Vault namespaces
* Enterprise policies
* Sentinel/RGP/EGP
* Audit logging
* High availability

---

# Conclusion

This Minikube environment provides a reproducible local Kubernetes platform for developing and testing **Platform Security, Kubernetes workload identity, HashiCorp Vault, JWT authentication, Vault Agent, and secret-management architectures**.

The environment can be used as the foundation for progressively building production-oriented Vault and Kubernetes security labs.
