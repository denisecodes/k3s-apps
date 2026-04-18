# Sealed Secrets

Sealed Secrets allows you to encrypt Kubernetes secrets so they can be safely stored in Git. The controller running in your cluster decrypts them automatically.

## Files

- **`application.yaml`**: ArgoCD Application manifest that deploys the Sealed Secrets controller to `kube-system` namespace

## How It Works

1. You encrypt secrets using the `kubeseal` CLI with the controller's public certificate
2. Commit the encrypted SealedSecret to Git (safe - only the controller can decrypt)
3. ArgoCD applies the SealedSecret to the cluster
4. The controller automatically decrypts it into a regular Kubernetes Secret

## Installing kubeseal CLI

**macOS:**
```bash
brew install kubeseal
```

**Linux:**
```bash
KUBESEAL_VERSION='0.24.0'
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Quick Start

**1. Create a plaintext secret (dry-run only - not applied to cluster):**
```bash
kubectl create secret generic <secret-name> \
  --namespace=<namespace> \
  --from-literal=<key>=<value> \
  --dry-run=client -o yaml > secret.yaml
```

**2. Encrypt the secret:**
```bash
kubeseal --format=yaml --fetch-cert < secret.yaml > sealed-secret.yaml
```

The `--fetch-cert` flag automatically retrieves the controller's public certificate from your cluster.

**3. Commit the encrypted secret to Git:**
```bash
cp sealed-secret.yaml apps/<app-name>/sealed-secret.yaml
git add apps/<app-name>/sealed-secret.yaml
git commit -m "chore: add sealed secret for <app-name>"
```

**4. Delete the plaintext file:**
```bash
rm secret.yaml
```

**Never commit `secret.yaml` to Git - it contains plaintext credentials!**

## Updating Secrets

To rotate or update credentials:

1. Create a new plaintext secret with updated values
2. Re-encrypt with `kubeseal`
3. Replace the existing `sealed-secret.yaml` in Git
4. Commit and push - ArgoCD will sync automatically
5. Delete the plaintext file
6. Restart pods to pick up new credentials: `kubectl rollout restart deployment/<name> -n <namespace>`

## Security

### Backup the Controller Key

**CRITICAL:** If the controller's private key is lost, all SealedSecrets become unrecoverable.

Backup the key immediately after deployment:
```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml
```

Store this file securely:
- Password manager (1Password, Bitwarden)
- Encrypted USB drive
- Secure offline storage

**Never commit the backup file to Git!**

### Restoring the Key

If you need to restore the controller key (e.g., after cluster rebuild):
```bash
kubectl apply -f sealed-secrets-key-backup.yaml
kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### Best Practices

- Never commit plaintext secrets to Git
- Use strong random passwords: `openssl rand -base64 32`
- Add to `.gitignore`: `*-secret.yaml` (but allow `sealed-secret.yaml`)
- Rotate credentials regularly (e.g., every 90 days)
- Limit access to the controller key backup

## Verification

**Check the controller is running:**
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

**Verify a SealedSecret was decrypted:**
```bash
# Check the SealedSecret exists
kubectl get sealedsecret <name> -n <namespace>

# Check the decrypted Secret was created
kubectl get secret <name> -n <namespace>

# Retrieve a specific value
kubectl get secret <name> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d
```

## Examples

See these applications for sealed-secrets usage:
- [Nextcloud](../nextcloud/sealed-secret.yaml) - Admin, PostgreSQL, and Redis credentials

## Documentation

- [Official Sealed Secrets Docs](https://github.com/bitnami-labs/sealed-secrets)
- [Bitnami Sealed Secrets Helm Chart](https://github.com/bitnami-labs/sealed-secrets/tree/main/helm/sealed-secrets)
