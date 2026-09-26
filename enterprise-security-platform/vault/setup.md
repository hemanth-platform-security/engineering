# Kubernetes ServiceAccount JWT Authentication with External HashiCorp Vault

## Overview

This lab demonstrates passwordless authentication from a Kubernetes workload identity to an external HashiCorp Vault server using Kubernetes ServiceAccount JSON Web Tokens (JWT).

The implementation uses:

* Kubernetes / Minikube
* Kubernetes ServiceAccount
* Bound ServiceAccount JWT
* Kubernetes ServiceAccount signing key
* HashiCorp Vault JWT authentication method
* Vault JWT role
* Vault policies
* KV v2 secrets engine

The key design objective is to authenticate a Kubernetes workload to Vault **without using a Kubernetes username/password or a static Vault token**.

---

## Architecture

```text
                         Minikube
                    Kubernetes Cluster
                           │
                           │
                 ┌─────────▼─────────┐
                 │   ServiceAccount  │
                 │                   │
                 │ vault-jwt-test    │
                 │ namespace:        │
                 │ vault-lab         │
                 └─────────┬─────────┘
                           │
                           │ kubectl create token
                           ▼
                    ServiceAccount JWT
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
             iss          aud          sub
              │            │            │
              │            │            │
              └────────────┼────────────┘
                           │
                           ▼
                  External HashiCorp Vault
                           │
                    JWT Auth Method
                           │
                    JWT Verification
                           │
                    k8s-sa.pub
                           │
                           ▼
                     JWT Role
                           │
                           ▼
                    Vault Policy
                           │
                           ▼
                  KV v2 Secret Access
```

---

# 1. Environment

## Kubernetes

Minikube was used as the Kubernetes environment.

Example cluster:

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

Kubernetes version used during the lab:

```text
v1.34.0
```

Verify:

```bash
kubectl get nodes
```

Expected:

```text
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   ...   v1.34.0
```

---

# 2. Kubernetes ServiceAccount

Create the namespace:

```bash
kubectl create namespace vault-lab
```

Create the ServiceAccount:

```bash
kubectl create serviceaccount vault-jwt-test \
    -n vault-lab
```

Verify:

```bash
kubectl get serviceaccount vault-jwt-test -n vault-lab
```

---

# 3. Kubernetes ServiceAccount Token

Generate a bound ServiceAccount token:

```bash
TOKEN=$(kubectl create token vault-jwt-test -n vault-lab)
```

The token can be inspected by decoding the JWT payload.

Example:

```bash
python -c "import base64,json; p='$TOKEN'.split('.')[1]; p += '='*(-len(p)%4); print(json.dumps(json.loads(base64.urlsafe_b64decode(p)),indent=2))"
```

The token used in this lab contained the following important claims:

```json
{
  "aud": [
    "https://kubernetes.default.svc.cluster.local"
  ],
  "iss": "https://kubernetes.default.svc.cluster.local",
  "sub": "system:serviceaccount:vault-lab:vault-jwt-test",
  "kubernetes.io": {
    "namespace": "vault-lab",
    "serviceaccount": {
      "name": "vault-jwt-test"
    }
  }
}
```

### Important JWT claims

| Claim | Value                                            |
| ----- | ------------------------------------------------ |
| `iss` | `https://kubernetes.default.svc.cluster.local`   |
| `aud` | `https://kubernetes.default.svc.cluster.local`   |
| `sub` | `system:serviceaccount:vault-lab:vault-jwt-test` |

---

# 4. Kubernetes ServiceAccount Signing Configuration

The Kubernetes API server was inspected to determine how ServiceAccount tokens are signed.

```bash
kubectl -n kube-system get pod kube-apiserver-minikube \
  -o jsonpath='{.spec.containers[0].command}' | \
  tr ',' '\n' | \
  grep -E 'service-account|issuer|jwks|api-audience'
```

The relevant configuration was:

```text
--service-account-issuer=https://kubernetes.default.svc.cluster.local
--service-account-key-file=/var/lib/minikube/certs/sa.pub
--service-account-signing-key-file=/var/lib/minikube/certs/sa.key
```

Therefore:

```text
sa.key
  │
  └── JWT signing key

sa.pub
  │
  └── JWT verification key
```

The private key must never be copied out of the Kubernetes environment.

---

# 5. JWKS Discovery Investigation

The standard JWKS endpoint was tested:

```bash
kubectl get --raw /openid/v1/jwks
```

The Minikube API server returned:

```text
Error from server (NotFound): the server could not find the requested resource
```

OIDC discovery was also tested:

```bash
kubectl get --raw /.well-known/openid-configuration
```

This also returned `NotFound`.

Therefore, for this lab, Vault was configured with the Kubernetes ServiceAccount **public signing key directly** rather than relying on Kubernetes JWKS discovery.

> Note: This is suitable for the lab. A production implementation should account for signing-key rotation and establish a reliable mechanism for distributing current verification keys.

---

# 6. Extract Kubernetes Public Signing Key

The public key is stored inside the Minikube node:

```text
/var/lib/minikube/certs/sa.pub
```

Because Git Bash performs Windows path conversion, use:

```bash
MSYS_NO_PATHCONV=1 minikube ssh -- \
  sudo cat /var/lib/minikube/certs/sa.pub
```

To save the public key locally:

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

Validate the key:

```bash
openssl pkey -pubin \
  -in k8s-sa.pub \
  -text \
  -noout
```

### Security

The following file contains a public key and can be distributed:

```text
k8s-sa.pub
```

The following file contains the private signing key and must **never** be copied or committed:

```text
/var/lib/minikube/certs/sa.key
```

---

# 7. Enable Vault JWT Authentication

Check authentication methods:

```bash
vault auth list
```

Enable JWT authentication if it isn't already enabled:

```bash
vault auth enable jwt
```

---

# 8. Configure Vault JWT Authentication

Configure Vault with the Kubernetes ServiceAccount public key:

```bash
vault write auth/jwt/config \
    jwt_validation_pubkeys="$(cat k8s-sa.pub)" \
    bound_issuer="https://kubernetes.default.svc.cluster.local"
```

Verify:

```bash
vault read auth/jwt/config
```

The important configuration is:

```text
bound_issuer =
https://kubernetes.default.svc.cluster.local
```

Vault now has the public key required to validate JWT signatures generated by the Kubernetes API server.

---

# 9. Create Vault Policy

Create a least-privilege policy:

```bash
vault policy write vault-jwt-test - <<'EOF'
path "secret/data/vault-jwt-test/*" {
  capabilities = ["read"]
}
EOF
```

Verify:

```bash
vault policy read vault-jwt-test
```

The policy grants:

```text
read
```

only to:

```text
secret/data/vault-jwt-test/*
```

---

# 10. Configure KV v2

Check mounted secrets engines:

```bash
vault secrets list
```

If `secret/` does not exist:

```bash
vault secrets enable -path=secret kv-v2
```

Create a test secret:

```bash
vault kv put secret/vault-jwt-test/demo \
    username="vault-user" \
    password="test-password"
```

Verify:

```bash
vault kv get secret/vault-jwt-test/demo
```

---

# 11. Create Vault JWT Role

The Vault role is bound to the exact Kubernetes ServiceAccount identity.

```bash
vault write auth/jwt/role/vault-jwt-test \
    role_type="jwt" \
    user_claim="sub" \
    bound_audiences="https://kubernetes.default.svc.cluster.local" \
    bound_subject="system:serviceaccount:vault-lab:vault-jwt-test" \
    policies="vault-jwt-test" \
    ttl="1h"
```

The important security bindings are:

### Issuer

```text
https://kubernetes.default.svc.cluster.local
```

### Audience

```text
https://kubernetes.default.svc.cluster.local
```

### Subject

```text
system:serviceaccount:vault-lab:vault-jwt-test
```

This prevents an arbitrary JWT from being used to authenticate to this Vault role.

---

# 12. Authenticate to Vault

Generate a fresh Kubernetes ServiceAccount token:

```bash
TOKEN=$(kubectl create token vault-jwt-test -n vault-lab)
```

Authenticate to Vault:

```bash
vault write auth/jwt/login \
    role="vault-jwt-test" \
    jwt="$TOKEN"
```

Successful authentication returns a Vault client token.

A token can also be captured directly:

```bash
VAULT_TOKEN=$(vault write -field=token auth/jwt/login \
    role="vault-jwt-test" \
    jwt="$TOKEN")
```

---

# 13. Test Secret Access

Use the generated Vault token:

```bash
VAULT_TOKEN="$VAULT_TOKEN" \
vault kv get secret/vault-jwt-test/demo
```

Expected result:

```text
username    vault-user
password    test-password
```

This demonstrates:

```text
Kubernetes ServiceAccount
        ↓
Bound JWT
        ↓
Vault JWT Authentication
        ↓
Vault Role
        ↓
Vault Policy
        ↓
Secret Access
```

No Vault username/password was used.

No static Vault token was embedded into the workload.

---

# 14. Test Authorization Boundaries

Create a secret outside the permitted path:

```bash
vault kv put secret/other-secret/test \
    value="should-not-be-readable"
```

Attempt to read it with the JWT-derived Vault token:

```bash
VAULT_TOKEN="$VAULT_TOKEN" \
vault kv get secret/other-secret/test
```

The request should be denied.

This verifies that authentication and authorization are separate controls:

```text
Authentication
    ↓
"Who are you?"
    ↓
Kubernetes ServiceAccount JWT

Authorization
    ↓
"What are you allowed to access?"
    ↓
Vault Policy
```

---

# 15. Security Model

The authentication chain is:

```text
                 Kubernetes
                     │
                     │
             ServiceAccount
                     │
                     ▼
               JWT creation
                     │
                     │
             signed using
                     │
                     ▼
                   sa.key
                     │
                     │
                     ▼
                JWT token
                     │
                     │
                     ▼
                  Vault
                     │
             signature verification
                     │
                     │ using
                     ▼
                  sa.pub
                     │
                     ▼
                JWT validation
                     │
                     ▼
                Vault JWT Role
                     │
                     ▼
                Vault Policy
                     │
                     ▼
                 Secret
```

---

# 16. Why This Is Passwordless Authentication

The workload does not need:

* Kubernetes username/password
* Vault username/password
* Long-lived Vault token
* Static Vault credential
* Hard-coded secret for authentication

Instead:

```text
Workload Identity
       ↓
Short-lived Kubernetes JWT
       ↓
Vault JWT validation
       ↓
Short-lived Vault token
       ↓
Authorized secret access
```

---

# 17. Key Engineering Observations

### 17.1 `iss` must match

Vault validates the JWT issuer:

```text
iss =
https://kubernetes.default.svc.cluster.local
```

### 17.2 `aud` must match

The Vault JWT role requires:

```text
aud =
https://kubernetes.default.svc.cluster.local
```

This prevents a token intended for another audience from being accepted by the Vault role.

### 17.3 `sub` provides workload identity

The role is restricted to:

```text
system:serviceaccount:vault-lab:vault-jwt-test
```

Therefore the Vault role is bound to a specific Kubernetes ServiceAccount.

### 17.4 Public/private key separation

```text
Kubernetes:
    sa.key  → sign

Vault:
    sa.pub  → verify
```

Vault never needs the Kubernetes private signing key.

---

# 18. Production Considerations

This lab uses a static public-key configuration:

```text
jwt_validation_pubkeys
```

This is useful for understanding the underlying cryptographic trust model, but production environments should consider:

### Key rotation

Kubernetes ServiceAccount signing keys may rotate.

A static public key configured in Vault must therefore be managed carefully.

### JWKS

A production architecture can use a reachable OIDC/JWKS endpoint where supported:

```text
Kubernetes
    │
    ▼
OIDC / JWKS
    │
    ▼
Vault
```

Vault can then retrieve the public signing keys rather than requiring manual key distribution.

### Network reachability

If Vault runs outside Kubernetes, ensure the selected issuer/JWKS endpoint is reachable from Vault.

### Audience restriction

Use a dedicated audience for Vault where the architecture supports it:

```text
aud = vault
```

This provides stronger token-use restriction than accepting a generic Kubernetes audience.

### Least privilege

Bind Vault roles to:

* specific ServiceAccounts
* specific audiences
* specific policies
* short token TTLs

### Token lifetime

Prefer short-lived Kubernetes ServiceAccount tokens:

```bash
kubectl create token ...
```

rather than long-lived static credentials.

---

# 19. Troubleshooting

## Minikube API server stopped

Check:

```bash
minikube status
```

Expected:

```text
host: Running
kubelet: Running
apiserver: Running
```

Restart if necessary:

```bash
minikube stop
minikube start
```

---

## Check Kubernetes API connectivity

```bash
kubectl get nodes
```

Expected:

```text
minikube   Ready   control-plane
```

---

## Inspect ServiceAccount token

```bash
TOKEN=$(kubectl create token vault-jwt-test -n vault-lab)
```

Decode the JWT payload and verify:

```text
iss
aud
sub
```

---

## Inspect API-server ServiceAccount configuration

```bash
kubectl -n kube-system get pod kube-apiserver-minikube \
  -o jsonpath='{.spec.containers[0].command}' | \
  tr ',' '\n' | \
  grep service-account
```

Expected:

```text
--service-account-issuer=...
--service-account-key-file=...
--service-account-signing-key-file=...
```

---

## Git Bash path conversion

When accessing paths inside Minikube from Git Bash, use:

```bash
MSYS_NO_PATHCONV=1
```

Example:

```bash
MSYS_NO_PATHCONV=1 minikube ssh -- \
  sudo cat /var/lib/minikube/certs/sa.pub
```

---

# 20. Engineering Outcome

The lab successfully demonstrated:

* [x] Kubernetes ServiceAccount creation
* [x] Bound ServiceAccount JWT generation
* [x] JWT claim inspection
* [x] Kubernetes JWT issuer identification
* [x] Kubernetes signing-key identification
* [x] Public signing-key extraction
* [x] Vault JWT authentication configuration
* [x] Vault JWT role configuration
* [x] Subject and audience restrictions
* [x] Vault policy creation
* [x] Passwordless Vault authentication
* [x] Secret retrieval using the JWT-derived Vault token
* [x] Authorization boundary validation

## Final Result

A Kubernetes workload identity can authenticate to an external HashiCorp Vault instance without requiring a static Vault credential:

```text
Kubernetes ServiceAccount
        │
        ▼
Short-lived JWT
        │
        ▼
HashiCorp Vault JWT Auth
        │
        ▼
JWT Signature + Issuer + Audience + Subject Validation
        │
        ▼
Vault Role
        │
        ▼
Vault Policy
        │
        ▼
Secret
```

---

# Next Engineering Lab

Recommended next step:

**Vault Agent + Kubernetes ServiceAccount JWT**

Extend this implementation from manual CLI authentication to workload automation:

```text
Kubernetes Pod
      │
      ▼
ServiceAccount
      │
      ▼
Projected JWT
      │
      ▼
Vault Agent
      │
      ▼
Vault JWT Authentication
      │
      ▼
Vault Token
      │
      ▼
Secret Injection
      │
      ▼
Application
```

The next iteration should also investigate:

1. Projected ServiceAccount tokens
2. Custom JWT audience
3. Vault Agent auto-auth
4. Vault Agent templates
5. Secret injection
6. Token renewal
7. JWT/key rotation
8. External Vault connectivity
9. Kubernetes OIDC/JWKS integration
10. Comparison with Vault Kubernetes Auth
