# Vault Agent in Minikube — Kubernetes ServiceAccount JWT Authentication

## Overview

This lab demonstrates how to run **HashiCorp Vault Agent inside Minikube** and authenticate it to a **HashiCorp Vault server running externally on the Windows host** using the **Vault JWT authentication method**.

The Kubernetes workload uses a **projected ServiceAccount JWT** as its identity credential.

The authentication flow is:

```text
Kubernetes ServiceAccount
        |
        v
Projected ServiceAccount JWT
        |
        v
Vault Agent in Minikube
        |
        | JWT login
        v
Vault JWT Auth
        |
        | Validate JWT claims/signature
        v
Vault JWT Role
        |
        v
Vault Policy
        |
        v
KV v2 Secret
        |
        v
Vault Agent Template
        |
        v
/vault/secrets/app.txt
```

> **Important:** This lab uses Vault's `auth/jwt` method, not Vault's `auth/kubernetes` method.

---

# 1. Lab Environment

| Component | Configuration |
|---|---|
| Host OS | Windows |
| Kubernetes | Minikube |
| Vault | HashiCorp Vault running on Windows host |
| Vault Agent image | `hashicorp/vault:1.20` |
| Tested Vault version | 1.20.4 |
| Kubernetes namespace | `vault-lab` |
| ServiceAccount | `vault-jwt-test` |
| Vault JWT auth mount | `auth/jwt` |
| Vault JWT role | `vault-jwt-test` |
| Vault policy | `vault-jwt-test` |
| KV mount | `secret/` |
| Secret | `secret/vault-lab/app` |
| Vault from Windows | `http://127.0.0.1:8200` |
| Vault from Minikube | `http://host.minikube.internal:8200` |
| JWT audience | `https://kubernetes.default.svc.cluster.local` |
| JWT subject | `system:serviceaccount:vault-lab:vault-jwt-test` |

---

# 2. Architecture

```text
                         Windows Host
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│                  HashiCorp Vault                            │
│                  127.0.0.1:8200                            │
│                                                             │
│   auth/jwt                                                   │
│      │                                                      │
│      └── role: vault-jwt-test                               │
│             │                                               │
│             └── policy: vault-jwt-test                       │
│                    │                                        │
│                    └── secret/data/vault-lab/app            │
│                                                             │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               │ host.minikube.internal:8200
                               │
┌──────────────────────────────┴──────────────────────────────┐
│                         Minikube                            │
│                                                             │
│  Namespace: vault-lab                                       │
│                                                             │
│  ServiceAccount: vault-jwt-test                             │
│             │                                               │
│             ▼                                               │
│  Projected ServiceAccount JWT                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ aud = https://kubernetes.default.svc.cluster.local   │  │
│  │ sub = system:serviceaccount:vault-lab:vault-jwt-test │  │
│  │ exp = short-lived                                    │  │
│  └───────────────────────────────────────────────────────┘  │
│             │                                               │
│             ▼                                               │
│       Vault Agent                                            │
│             │                                               │
│             │ JWT login                                      │
│             ▼                                               │
│       Vault JWT Auth                                         │
│             │                                               │
│             ▼                                               │
│       Vault Client Token                                     │
│             │                                               │
│             ▼                                               │
│       Vault Agent Template                                   │
│             │                                               │
│             ▼                                               │
│       /vault/secrets/app.txt                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

# 3. Why Use a Projected ServiceAccount JWT?

Kubernetes can make a ServiceAccount token available to a Pod automatically.

However, a projected ServiceAccount token allows the workload to request a token with explicit properties such as:

- Audience
- Expiration
- Intended workload use

For this lab, the projected token is configured with:

```yaml
expirationSeconds: 3600
audience: https://kubernetes.default.svc.cluster.local
```

The token is mounted at:

```text
/var/run/secrets/tokens/vault-token
```

This allows the Vault role to bind authentication to the expected audience and ServiceAccount subject.

The important distinction is:

> The ServiceAccount provides the Kubernetes identity. The projected token is a short-lived JWT representation of that identity.

---

# 4. JWT Claims Used by Vault

The Vault role binds the JWT to:

### Subject

```text
system:serviceaccount:vault-lab:vault-jwt-test
```

This corresponds to:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-jwt-test
  namespace: vault-lab
```

### Audience

```text
https://kubernetes.default.svc.cluster.local
```

The projected token requests the same audience:

```yaml
audience: https://kubernetes.default.svc.cluster.local
```

This gives the Vault role an explicit identity boundary.

---

# 5. Prerequisites

Verify Minikube:

```bash
minikube status
```

Verify Kubernetes:

```bash
kubectl get nodes
```

Verify Vault:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault status
```

---

# 6. Enable Vault JWT Authentication

Check enabled authentication methods:

```bash
vault auth list
```

If JWT authentication is not enabled:

```bash
vault auth enable jwt
```

Expected mount:

```text
jwt/
```

---

# 7. Configure JWT Validation

Vault JWT authentication needs a trusted mechanism to validate the Kubernetes-issued JWT.

Depending on the deployment architecture, Vault can use an OIDC discovery endpoint or configured JWT verification keys.

For this Minikube lab, the Kubernetes ServiceAccount signing public key can be made available to Vault.

The public key generated during the Kubernetes setup is:

```text
k8s-sa.pub
```

A typical JWT auth configuration using a trusted Kubernetes signing key is conceptually:

```bash
vault write auth/jwt/config \
    jwt_validation_pubkeys="$(cat k8s-sa.pub)"
```

The exact issuer configuration must match the issuer in the Kubernetes ServiceAccount JWT.

Inspect the Kubernetes issuer with:

```bash
kubectl get --raw /.well-known/openid-configuration
```

or inspect the API server configuration appropriate to the Minikube version.

> The key requirement is that Vault must trust the issuer and signing key used to create the Kubernetes ServiceAccount JWT.

---

# 8. Create the Vault Policy

Create:

```bash
cat > vault-jwt-test.hcl <<'EOF'
path "secret/data/vault-lab/app" {
  capabilities = ["read"]
}
EOF
```

Write the policy:

```bash
vault policy write vault-jwt-test vault-jwt-test.hcl
```

Verify:

```bash
vault policy read vault-jwt-test
```

Expected:

```hcl
path "secret/data/vault-lab/app" {
  capabilities = ["read"]
}
```

This is deliberately least privilege: the Agent can only read the specified KV v2 secret.

---

# 9. Create the KV v2 Secret

Create the secret:

```bash
vault kv put secret/vault-lab/app \
  username=test \
  password=test
```

Verify:

```bash
vault kv get secret/vault-lab/app
```

Expected:

```text
username    test
password    test
```

---

# 10. Create the Vault JWT Role

Create the role:

```bash
vault write auth/jwt/role/vault-jwt-test \
    role_type="jwt" \
    user_claim="sub" \
    bound_audiences="https://kubernetes.default.svc.cluster.local" \
    bound_subject="system:serviceaccount:vault-lab:vault-jwt-test" \
    policies="vault-jwt-test" \
    ttl="1h"
```

Verify:

```bash
vault read auth/jwt/role/vault-jwt-test
```

The important role configuration is:

```text
role_type       = jwt
user_claim      = sub
bound_audiences = https://kubernetes.default.svc.cluster.local
bound_subject   = system:serviceaccount:vault-lab:vault-jwt-test
policies        = vault-jwt-test
ttl             = 1h
```

---

# 11. Kubernetes Configuration

The complete lab can be deployed using the following YAML.

Save as:

```text
vault-agent-jwt.yaml
```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: vault-lab

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-jwt-test
  namespace: vault-lab

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-agent-config
  namespace: vault-lab
data:
  agent.hcl: |
    pid_file = "/tmp/vault-agent.pid"

    vault {
      address = "http://host.minikube.internal:8200"
    }

    auto_auth {
      method "jwt" {
        mount_path = "auth/jwt"

        config = {
          role = "vault-jwt-test"
          path = "/var/run/secrets/tokens/vault-token"
          remove_jwt_after_reading = false
        }
      }

      sink "file" {
        config = {
          path = "/tmp/vault-token"
        }
      }
    }

    template {
      source      = "/vault/config/app.ctmpl"
      destination = "/vault/secrets/app.txt"
    }

  app.ctmpl: |
    {{- with secret "secret/data/vault-lab/app" -}}
    username={{ .Data.data.username }}
    password={{ .Data.data.password }}
    {{- end }}

---
apiVersion: v1
kind: Pod
metadata:
  name: vault-jwt-test
  namespace: vault-lab
  labels:
    app: vault-jwt-test
spec:
  serviceAccountName: vault-jwt-test

  containers:
    - name: vault-agent
      image: hashicorp/vault:1.20

      command:
        - vault
        - agent
        - -config=/vault/config/agent.hcl

      volumeMounts:
        - name: vault-agent-config
          mountPath: /vault/config
          readOnly: true

        - name: jwt-token
          mountPath: /var/run/secrets/tokens
          readOnly: true

        - name: vault-secrets
          mountPath: /vault/secrets

  volumes:
    - name: vault-agent-config
      configMap:
        name: vault-agent-config

    - name: jwt-token
      projected:
        sources:
          - serviceAccountToken:
              path: vault-token
              expirationSeconds: 3600
              audience: https://kubernetes.default.svc.cluster.local

    - name: vault-secrets
      emptyDir: {}
```

---

# 12. Deploy the Lab

Apply:

```bash
kubectl apply -f vault-agent-jwt.yaml
```

Check:

```bash
kubectl get all -n vault-lab
```

Check the Pod:

```bash
kubectl get pod -n vault-lab
```

Wait for it to start:

```bash
kubectl get pod -n vault-lab -w
```

---

# 13. Verify Minikube → Vault Connectivity

The Vault server runs on the Windows host.

From inside Minikube, use:

```text
http://host.minikube.internal:8200
```

Test:

```bash
kubectl run vault-connectivity-test \
  -n vault-lab \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl \
  -- curl -sS http://host.minikube.internal:8200/v1/sys/health
```

A successful health response confirms network connectivity.

---

# 14. Verify the Projected JWT

Check the mounted token:

```bash
MSYS_NO_PATHCONV=1 kubectl exec \
  -n vault-lab \
  vault-jwt-test \
  -- ls -la /var/run/secrets/tokens
```

Expected:

```text
vault-token
```

The token is located at:

```text
/var/run/secrets/tokens/vault-token
```

Do not commit or expose the token.

For troubleshooting, the JWT can be inspected carefully:

```bash
MSYS_NO_PATHCONV=1 kubectl exec \
  -n vault-lab \
  vault-jwt-test \
  -- cat /var/run/secrets/tokens/vault-token
```

---

# 15. Verify Vault Agent Authentication

View the Agent logs:

```bash
kubectl logs -f -n vault-lab vault-jwt-test
```

The Agent should authenticate using:

```text
auth/jwt
```

with role:

```text
vault-jwt-test
```

The authentication result is a Vault client token.

This Vault client token is different from the Kubernetes ServiceAccount JWT.

---

# 16. Verify the Rendered Secret

Run:

```bash
MSYS_NO_PATHCONV=1 kubectl exec \
  -n vault-lab \
  vault-jwt-test \
  -- cat /vault/secrets/app.txt
```

Expected:

```text
username=test
password=test
```

This confirms the complete authentication and authorization chain.

---

# 17. Authentication Flow in Detail

```text
1. Pod starts
       |
       v
2. Kubernetes associates Pod with
   ServiceAccount vault-jwt-test
       |
       v
3. Kubernetes creates projected JWT
       |
       +-- sub = system:serviceaccount:vault-lab:vault-jwt-test
       |
       +-- aud = https://kubernetes.default.svc.cluster.local
       |
       +-- exp = short-lived
       |
       v
4. Vault Agent reads JWT
       |
       v
5. Agent calls:
   POST /v1/auth/jwt/login
       |
       v
6. Vault validates JWT
       |
       +-- signature
       +-- issuer
       +-- expiration
       +-- audience
       +-- subject
       |
       v
7. Vault matches JWT to role
   vault-jwt-test
       |
       v
8. Vault attaches policy
   vault-jwt-test
       |
       v
9. Vault Agent receives Vault client token
       |
       v
10. Agent reads:
    secret/data/vault-lab/app
       |
       v
11. Template renders:
    /vault/secrets/app.txt
```

---

# 18. Kubernetes JWT Auth vs Vault Kubernetes Auth

These two authentication methods are related but are not the same.

## Vault Kubernetes Auth

Typical flow:

```text
Pod
 |
 | ServiceAccount JWT
 v
Vault
 |
 | Kubernetes TokenReview
 v
Kubernetes API Server
 |
 | Identity confirmation
 v
Vault
 |
 v
Vault role/policy
```

Vault uses Kubernetes' TokenReview API to validate the ServiceAccount identity.

The commonly used token is:

```text
/var/run/secrets/kubernetes.io/serviceaccount/token
```

---

## Vault JWT Auth

This lab uses:

```text
Pod
 |
 | Projected ServiceAccount JWT
 v
Vault Agent
 |
 | JWT login
 v
Vault JWT Auth
 |
 | JWT validation
 v
Vault role/policy
```

Vault validates the JWT according to its configured issuer/signing-key validation mechanism.

Therefore:

> **Vault JWT Auth does not inherently require the default Kubernetes ServiceAccount token.**

It requires a valid JWT that Vault can validate.

---

# 19. Why Use a Projected JWT?

The projected token allows the Pod to explicitly request:

```yaml
expirationSeconds: 3600
audience: https://kubernetes.default.svc.cluster.local
```

This provides an explicit identity boundary.

The Vault role requires:

```text
bound_audiences =
https://kubernetes.default.svc.cluster.local
```

and:

```text
bound_subject =
system:serviceaccount:vault-lab:vault-jwt-test
```

Therefore both the token and Vault role agree on:

```text
Who?
  ↓
vault-jwt-test ServiceAccount

For what audience?
  ↓
https://kubernetes.default.svc.cluster.local
```

---

# 20. JWT Rotation

Projected ServiceAccount tokens are managed by Kubernetes.

The Pod does not need to be restarted simply because Kubernetes rotates the projected token.

Conceptually:

```text
Initial JWT
     |
     v
Vault Agent authentication
     |
     v
Kubernetes rotates token
     |
     v
Projected volume updated
     |
     v
Agent can use the updated JWT
```

The token requested by this lab has:

```yaml
expirationSeconds: 3600
```

The projected volume is read-only because Kubernetes manages the token file.

---

# 21. `remove_jwt_after_reading`

The Vault Agent configuration contains:

```hcl
config = {
  role = "vault-jwt-test"
  path = "/var/run/secrets/tokens/vault-token"
  remove_jwt_after_reading = false
}
```

This setting is important because the Kubernetes projected token is mounted read-only.

Without it, the Agent may attempt to remove the JWT file and produce an error similar to:

```text
error removing jwt file:
remove /var/run/secrets/tokens/vault-token:
read-only file system
```

The correct configuration location is:

```text
auto_auth
└── method "jwt"
    └── config
        └── remove_jwt_after_reading = false
```

---

# 22. Two Different Tokens

There are two distinct credentials in this architecture.

## Kubernetes ServiceAccount JWT

Path:

```text
/var/run/secrets/tokens/vault-token
```

Issued by:

```text
Kubernetes
```

Purpose:

```text
Authenticate the workload to Vault
```

Identity:

```text
system:serviceaccount:vault-lab:vault-jwt-test
```

---

## Vault Client Token

Path in this lab:

```text
/tmp/vault-token
```

Issued by:

```text
Vault
```

Purpose:

```text
Authenticate subsequent Vault API requests
```

These credentials have different issuers, purposes, and lifecycles.

---

# 23. KV v2 Path Considerations

The logical secret path is:

```text
secret/vault-lab/app
```

The KV v2 API path is:

```text
secret/data/vault-lab/app
```

Therefore the Vault policy uses:

```hcl
path "secret/data/vault-lab/app" {
  capabilities = ["read"]
}
```

The Agent template uses:

```hcl
{{- with secret "secret/data/vault-lab/app" -}}
username={{ .Data.data.username }}
password={{ .Data.data.password }}
{{- end }}
```

The nested `.Data.data` is because KV v2 wraps the actual secret data under `data`.

---

# 24. Least-Privilege Design

The Vault policy grants only:

```hcl
capabilities = ["read"]
```

on:

```text
secret/data/vault-lab/app
```

The Agent cannot automatically:

- Write the secret
- Delete the secret
- List unrelated secrets
- Read other paths

This follows a least-privilege design.

---

# 25. Troubleshooting

## 25.1 Vault role not found

Error:

```text
role "vault-agent" could not be found
```

Verify the Agent configuration:

```bash
kubectl describe configmap vault-agent-config -n vault-lab
```

The role must be:

```hcl
role = "vault-jwt-test"
```

Verify the Vault role:

```bash
vault read auth/jwt/role/vault-jwt-test
```

---

## 25.2 Permission denied

If the Agent receives:

```text
403 permission denied
```

check the policy:

```bash
vault policy read vault-jwt-test
```

For KV v2 it should contain:

```hcl
path "secret/data/vault-lab/app" {
  capabilities = ["read"]
}
```

---

## 25.3 JWT file cannot be deleted

If the Agent logs:

```text
read-only file system
```

verify:

```hcl
remove_jwt_after_reading = false
```

is inside the JWT method's `config`.

---

## 25.4 Vault unreachable

Test:

```bash
kubectl run vault-connectivity-test \
  -n vault-lab \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl \
  -- curl -sS http://host.minikube.internal:8200/v1/sys/health
```

Verify that Vault is reachable from the Minikube environment.

---

## 25.5 Template not rendered

Check Agent logs:

```bash
kubectl logs -n vault-lab vault-jwt-test
```

Check the output directory:

```bash
MSYS_NO_PATHCONV=1 kubectl exec \
  -n vault-lab \
  vault-jwt-test \
  -- ls -la /vault/secrets
```

Then:

```bash
MSYS_NO_PATHCONV=1 kubectl exec \
  -n vault-lab \
  vault-jwt-test \
  -- cat /vault/secrets/app.txt
```

---

# 26. Git Bash Path Conversion

When running `kubectl exec` from Git Bash on Windows, MSYS can convert Linux paths.

Use:

```bash
MSYS_NO_PATHCONV=1
```

Example:

```bash
MSYS_NO_PATHCONV=1 kubectl exec \
  -n vault-lab \
  vault-jwt-test \
  -- cat /vault/secrets/app.txt
```

This prevents Git Bash from converting:

```text
/vault/secrets/app.txt
```

into a Windows path.

---

# 27. Useful Verification Commands

### Vault status

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault status
```

### Auth methods

```bash
vault auth list
```

### JWT role

```bash
vault read auth/jwt/role/vault-jwt-test
```

### Policy

```bash
vault policy read vault-jwt-test
```

### Secret

```bash
vault kv get secret/vault-lab/app
```

### Kubernetes Pod

```bash
kubectl get pod -n vault-lab
```

### Agent logs

```bash
kubectl logs -f -n vault-lab vault-jwt-test
```

### Projected token mount

```bash
MSYS_NO_PATHCONV=1 kubectl exec \
  -n vault-lab \
  vault-jwt-test \
  -- ls -la /var/run/secrets/tokens
```

### Rendered secret

```bash
MSYS_NO_PATHCONV=1 kubectl exec \
  -n vault-lab \
  vault-jwt-test \
  -- cat /vault/secrets/app.txt
```

---

# 28. Cleanup

Delete the Kubernetes resources:

```bash
kubectl delete -f vault-agent-jwt.yaml
```

Delete the Vault policy if it is only used by this lab:

```bash
vault policy delete vault-jwt-test
```

Delete the JWT role:

```bash
vault delete auth/jwt/role/vault-jwt-test
```

Do not disable `auth/jwt` if other workloads use it.

---

# 29. Validation Checklist

- [x] Minikube is running
- [x] Vault is running on Windows host
- [x] Minikube can reach host Vault
- [x] `vault-lab` namespace created
- [x] `vault-jwt-test` ServiceAccount created
- [x] Projected ServiceAccount JWT created
- [x] JWT audience configured
- [x] JWT subject bound to Vault role
- [x] Vault JWT authentication enabled
- [x] JWT validation configured
- [x] `vault-jwt-test` Vault role created
- [x] `vault-jwt-test` policy created
- [x] KV v2 secret created
- [x] Vault Agent authenticates successfully
- [x] Vault client token obtained
- [x] KV v2 secret authorized
- [x] Vault Agent template renders the secret
- [x] `/vault/secrets/app.txt` contains the expected values
- [x] Projected JWT is mounted read-only
- [x] `remove_jwt_after_reading = false`
- [x] Kubernetes manages projected JWT rotation

---

# 30. Final Result

The completed lab establishes:

```text
+-------------------+
| Kubernetes Pod    |
|                   |
| ServiceAccount    |
+---------+---------+
          |
          | Projected JWT
          v
+-------------------+
| Vault Agent       |
|                   |
| JWT Auto Auth     |
+---------+---------+
          |
          | POST auth/jwt/login
          v
+-------------------+
| HashiCorp Vault   |
|                   |
| JWT Auth          |
|       |           |
|       v           |
| JWT Role          |
|       |           |
|       v           |
| Policy            |
|       |           |
|       v           |
| KV v2             |
+---------+---------+
          |
          | Secret
          v
+-------------------+
| Vault Agent       |
| Template          |
+---------+---------+
          |
          v
/vault/secrets/app.txt
```

The key security model is:

```text
Kubernetes ServiceAccount
        +
Short-lived projected JWT
        +
Explicit audience
        +
Explicit subject
        +
Vault JWT validation
        +
Least-privilege Vault policy
        =
Passwordless workload authentication to Vault
```

This provides a foundation for extending the pattern to:

- Multiple application ServiceAccounts
- Namespace-specific Vault roles
- Dynamic Vault policies
- Vault PKI
- Venafi PKI integration
- Database dynamic credentials
- OpenShift workloads
- Enterprise platform-security architecture
