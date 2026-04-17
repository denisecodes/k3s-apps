# cert-manager Configuration

This directory contains cert-manager ClusterIssuers deployed via ArgoCD with automated email configuration via SealedSecrets.

## How It Works

1. **ClusterIssuers** are deployed with a placeholder email
2. **SealedSecret** (encrypted) contains your real email - safe to commit to public repo
3. **Kubernetes Job** (ArgoCD PostSync hook) automatically patches the ClusterIssuers with your email from the SealedSecret
4. **No manual kubectl commands needed** - everything is GitOps!

## One-Time Setup: Create Your Email SealedSecret

### Prerequisites

- Sealed Secrets controller must be running (already installed via ArgoCD)
- `kubeseal` CLI installed on your local machine

### Install kubeseal CLI

```bash
# macOS
brew install kubeseal

# Linux
KUBESEAL_VERSION='0.27.2'
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### Create Your SealedSecret

```bash
# 1. Make sure you're in the k3s-apps repo directory
cd /path/to/k3s-apps

# 2. Create the secret locally (REPLACE with your actual email!)
kubectl create secret generic letsencrypt-email \
  --from-literal=email=your-actual-email@example.com \
  --namespace=cert-manager \
  --dry-run=client -o yaml > /tmp/email-secret.yaml

# 3. Seal it (encrypt it using your cluster's public key)
kubeseal --format=yaml \
  < /tmp/email-secret.yaml \
  > manifests/cert-manager/email-sealedsecret.yaml

# 4. Clean up the unencrypted secret
rm /tmp/email-secret.yaml

# 5. Verify the sealed secret was created
cat manifests/cert-manager/email-sealedsecret.yaml
# You should see: kind: SealedSecret with encrypted data

# 6. Commit and push (the encrypted secret is safe to commit!)
git add manifests/cert-manager/email-sealedsecret.yaml
git commit -m "Add encrypted email for cert-manager"
git push
```

### What Happens After Push

1. ArgoCD detects the change and syncs
2. Sealed Secrets controller decrypts the SealedSecret → creates a regular Secret named `letsencrypt-email`
3. ClusterIssuers are deployed with placeholder email
4. ArgoCD PostSync hook triggers the patch Job
5. Job reads email from the decrypted secret and patches both ClusterIssuers
6. Done! Your ClusterIssuers now have your real email

## Files in This Directory

- `clusterissuer-staging.yaml` - Let's Encrypt staging ClusterIssuer (for testing)
- `clusterissuer-production.yaml` - Let's Encrypt production ClusterIssuer
- `email-sealedsecret.yaml` - **YOU CREATE THIS** - Your encrypted email (placeholder until you create it)
- `patch-job.yaml` - Kubernetes Job that patches ClusterIssuers with email from SealedSecret (runs automatically via ArgoCD PostSync hook)

## Verification

```bash
# Check that your SealedSecret was decrypted
kubectl get secret letsencrypt-email -n cert-manager

# Verify the email is set correctly in ClusterIssuers (should show your real email, not placeholder)
kubectl get clusterissuer letsencrypt-staging -o jsonpath='{.spec.acme.email}'
kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.spec.acme.email}'

# Check the patch job ran successfully
kubectl get jobs -n cert-manager
kubectl logs -n cert-manager job/patch-clusterissuer-email
```

## Why SealedSecrets?

- ✅ Already installed in your cluster
- ✅ Encrypted secrets safe to commit to public repos
- ✅ GitOps native - everything in Git
- ✅ No external dependencies (no cloud provider needed)
- ✅ Perfect for homelab use cases

## Troubleshooting

### Job fails with "secret not found"

The Sealed Secrets controller hasn't decrypted your SealedSecret yet. Wait a few seconds and the job will retry.

```bash
# Check if the secret exists
kubectl get secret letsencrypt-email -n cert-manager

# Check SealedSecret status
kubectl get sealedsecret -n cert-manager
kubectl describe sealedsecret letsencrypt-email -n cert-manager
```

### ClusterIssuer still shows placeholder email

Check the patch job logs:

```bash
kubectl logs -n cert-manager job/patch-clusterissuer-email
```

### Need to update your email?

1. Create a new SealedSecret with the updated email (follow steps above)
2. Commit and push
3. ArgoCD will sync and the job will run again, updating the ClusterIssuers
