# Nextcloud Deployment

This directory contains the ArgoCD Application manifest and configuration for deploying Nextcloud as a self-hosted cloud storage solution.

## Overview

**Nextcloud** is a self-hosted file sync and sharing platform (alternative to Google Drive, Dropbox, etc.) with support for:
- File storage and sharing
- Calendar and contacts sync
- Collaborative editing
- Mobile apps (iOS/Android)
- Desktop sync clients

## Deployment Details

- **Chart:** nextcloud/nextcloud v9.0.5
- **App Version:** Nextcloud v33.0.2
- **Repository:** https://nextcloud.github.io/helm/
- **Namespace:** `nextcloud`
- **Access URL:** http://nextcloud.denise.home

## Components

### 1. Nextcloud Application (`application.yaml`)
ArgoCD Application manifest that:
- Uses **multiple sources pattern** to combine remote Helm chart with Git-based values
- Deploys to `nextcloud` namespace
- Auto-sync and self-heal enabled
- Creates namespace automatically

**ArgoCD Multiple Sources Pattern:**
The Application uses two sources:
1. **Helm chart source**: Official Nextcloud Helm repository (`https://nextcloud.github.io/helm/`)
2. **Values source**: This Git repository for `values.yaml`

This pattern allows us to:
- Use the official remote Helm chart (always up-to-date)
- Keep configuration in Git (version control, GitOps)
- Reference values with `$values/apps/nextcloud/values.yaml`

### 2. Helm Values (`values.yaml`)
Contains all Nextcloud configuration overrides, stored in Git for version control.

Configuration includes:
- **Nextcloud**: Admin user, domain, trusted domains, PHP limits
- **PostgreSQL**: Database backend with 8Gi storage
- **Redis**: Caching and file locking with 1Gi storage
- **Persistence**: 50Gi Longhorn PVC for Nextcloud data
- **Resources**: CPU/memory requests and limits
- **Probes**: Liveness, readiness, and startup configurations

### 3. Sealed Secret (`sealed-secret.yaml`)
Encrypted credentials for:
- Admin username and password
- PostgreSQL database password
- Redis password

## Creating and Updating Sealed Secrets

This section explains how to create and manage SealedSecrets for Nextcloud using the `kubeseal` command-line tool.

### Overview

**What are Sealed Secrets?**

Sealed Secrets allow you to safely store encrypted Kubernetes secrets in Git. The Sealed Secrets controller (deployed in your cluster) can decrypt these secrets, but only the controller has the private key. This means:

- You can commit encrypted secrets to public/private Git repositories
- Even if someone gains access to your Git repo, they cannot decrypt the secrets
- The secrets are automatically decrypted by the controller when applied to the cluster
- ArgoCD can manage sealed secrets just like any other Kubernetes resource

**Why use Sealed Secrets?**

For Nextcloud, we need to store sensitive credentials:
- Admin username and password
- PostgreSQL database password
- Redis password

Without Sealed Secrets, you'd need to manually create these secrets in the cluster or store plaintext passwords in Git (security risk). Sealed Secrets solve this by encrypting the secrets before committing them.

**Prerequisites:**
- `kubeseal` CLI installed (see next section)
- Sealed Secrets controller running in your cluster (deployed via ArgoCD at `apps/sealed-secrets/`)
- `kubectl` configured to access your cluster

### Installing kubeseal CLI

The `kubeseal` CLI encrypts your plaintext Kubernetes secrets into SealedSecret resources.

**macOS (Homebrew):**
```bash
brew install kubeseal
```

**Linux:**
```bash
# Download the latest release
KUBESEAL_VERSION='0.24.0'
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"

# Extract and install
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Clean up
rm kubeseal kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz
```

**Verify installation:**
```bash
kubeseal --version
```

### Creating Sealed Secrets (Initial Setup)

Follow these steps to create a new SealedSecret for Nextcloud credentials.

#### Step 1: Create a plaintext Kubernetes secret (dry-run)

First, create a regular Kubernetes secret manifest **without applying it to the cluster**. This is done locally using `--dry-run=client` to prevent the plaintext secret from being stored in the cluster.

```bash
kubectl create secret generic nextcloud-credentials \
  --namespace=nextcloud \
  --from-literal=admin-username=denise \
  --from-literal=admin-password=your-secure-password-here \
  --from-literal=postgresql-password=your-db-password-here \
  --from-literal=redis-password=your-redis-password-here \
  --dry-run=client -o yaml > nextcloud-secret.yaml
```

**What this does:**
- Creates a Kubernetes Secret manifest in YAML format
- `--dry-run=client`: Generates the manifest locally without sending it to the cluster
- `-o yaml`: Outputs in YAML format
- The file `nextcloud-secret.yaml` contains your **plaintext passwords** (do not commit this!)

**Important:** Use strong, randomly generated passwords. Generate secure passwords with:
```bash
openssl rand -base64 32
```

#### Step 2: Encrypt with kubeseal

Now encrypt the plaintext secret using `kubeseal`:

```bash
kubeseal --format=yaml --fetch-cert < nextcloud-secret.yaml > sealed-secret.yaml
```

**What this does:**
- Reads the plaintext secret from `nextcloud-secret.yaml`
- `--fetch-cert`: Automatically fetches the Sealed Secrets controller's public certificate from your cluster
- Encrypts the secret data using the controller's public key
- Outputs the encrypted SealedSecret to `sealed-secret.yaml`

**How `--fetch-cert` works:**
- Connects to your Kubernetes cluster using your current `kubectl` context
- Retrieves the public certificate from the Sealed Secrets controller
- Uses this certificate to encrypt your secret
- Only the controller (with the private key) can decrypt it

#### Step 3: Review the generated sealed-secret.yaml

Open `sealed-secret.yaml` and verify it looks similar to this:

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: nextcloud-credentials
  namespace: nextcloud
spec:
  encryptedData:
    admin-username: AgB3+6zwYw/08wIjjEKKSd21XPE...
    admin-password: AgAGxTf3anzw0jzOR3zbt1AckDB...
    postgresql-password: AgBUr0vJyiH16dGvH3Y7+8ptr...
    redis-password: AgAxyKUSwL5l7oZda85HUr6PqS...
  template:
    metadata:
      name: nextcloud-credentials
      namespace: nextcloud
    type: Opaque
```

**Key observations:**
- All password values are now encrypted (long base64 strings starting with "Ag...")
- This file is **safe to commit to Git**
- The controller will decrypt this into a regular Kubernetes Secret when applied

#### Step 4: Commit to Git

Move the sealed secret to your GitOps repository and commit it:

```bash
# Copy to the Nextcloud app directory
cp sealed-secret.yaml apps/nextcloud/sealed-secret.yaml

# Add to Git
git add apps/nextcloud/sealed-secret.yaml
git commit -m "chore: add Nextcloud sealed secrets for credentials"
git push
```

**ArgoCD behavior:**
- ArgoCD will detect the new `sealed-secret.yaml` file
- It will apply the SealedSecret resource to the cluster
- The Sealed Secrets controller will automatically decrypt it into a regular Secret named `nextcloud-credentials`
- Nextcloud pods can then use this Secret via environment variables or volume mounts

#### Step 5: Clean up plaintext files

**Critical security step:** Delete the plaintext secret file immediately:

```bash
rm nextcloud-secret.yaml
```

**Never commit `nextcloud-secret.yaml` to Git!** It contains your plaintext passwords and should only exist temporarily during the encryption process.

### Updating Existing Secrets

You may need to update sealed secrets when:
- Rotating passwords for security compliance
- Changing admin credentials
- Updating database or Redis passwords
- Adding new secret keys

**Process to update:**

1. **Create a new plaintext secret** with updated values:
   ```bash
   kubectl create secret generic nextcloud-credentials \
     --namespace=nextcloud \
     --from-literal=admin-username=denise \
     --from-literal=admin-password=new-password-here \
     --from-literal=postgresql-password=new-db-password \
     --from-literal=redis-password=new-redis-password \
     --dry-run=client -o yaml > nextcloud-secret.yaml
   ```

2. **Re-encrypt with kubeseal**:
   ```bash
   kubeseal --format=yaml --fetch-cert < nextcloud-secret.yaml > sealed-secret.yaml
   ```

3. **Replace the existing sealed secret**:
   ```bash
   cp sealed-secret.yaml apps/nextcloud/sealed-secret.yaml
   ```

4. **Commit and push**:
   ```bash
   git add apps/nextcloud/sealed-secret.yaml
   git commit -m "chore: rotate Nextcloud credentials"
   git push
   ```

5. **Clean up plaintext file**:
   ```bash
   rm nextcloud-secret.yaml
   ```

6. **ArgoCD will automatically sync** and the controller will decrypt the new secret

7. **Restart Nextcloud pods** to pick up the new credentials:
   ```bash
   kubectl rollout restart deployment/nextcloud -n nextcloud
   ```

**Note:** Changing database or Redis passwords requires updating the database/Redis pods as well. Coordinate password changes carefully to avoid downtime.

### Security Best Practices

**1. Never commit plaintext secrets to Git**
- Always use `--dry-run=client` when creating secrets
- Delete `nextcloud-secret.yaml` immediately after encryption
- Use `.gitignore` to prevent accidental commits:
  ```bash
  echo "*-secret.yaml" >> .gitignore
  echo "!sealed-secret.yaml" >> .gitignore
  ```

**2. Use strong, randomly generated passwords**
- Generate passwords with `openssl rand -base64 32`
- Avoid predictable passwords or personal information
- Use unique passwords for each service (admin, PostgreSQL, Redis)

**3. Backup the Sealed Secrets controller key**

**CRITICAL:** The Sealed Secrets controller's private key is required to decrypt all SealedSecrets. If this key is lost, all your encrypted secrets become unrecoverable.

Backup the controller key immediately after deployment:
```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml
```

Store this backup in a secure location:
- Password manager (1Password, Bitwarden, etc.)
- Encrypted USB drive
- Secure cloud storage (encrypted)

**Never commit `sealed-secrets-key-backup.yaml` to Git!**

For detailed information on backing up and restoring the controller key, see the [main repository README](../../README.md#sealed-secrets).

**4. Rotate credentials regularly**
- Set a schedule for rotating passwords (e.g., every 90 days)
- Rotate immediately if credentials are compromised
- Document rotation procedures for your team

**5. Limit access to the controller key**
- Only trusted administrators should have access to the key backup
- Use Kubernetes RBAC to restrict access to the Sealed Secrets controller
- Monitor controller logs for suspicious activity

### Verification

After creating or updating a SealedSecret, verify it was decrypted successfully:

**1. Check the SealedSecret resource exists:**
```bash
kubectl get sealedsecret nextcloud-credentials -n nextcloud
```

Expected output:
```
NAME                     STATUS   SYNCED   AGE
nextcloud-credentials             True     5m
```

**2. Verify the decrypted Secret was created:**
```bash
kubectl get secret nextcloud-credentials -n nextcloud
```

Expected output:
```
NAME                     TYPE     DATA   AGE
nextcloud-credentials    Opaque   4      5m
```

**3. Check the Secret contains all expected keys:**
```bash
kubectl get secret nextcloud-credentials -n nextcloud -o jsonpath='{.data}' | jq 'keys'
```

Expected output:
```json
[
  "admin-password",
  "admin-username",
  "postgresql-password",
  "redis-password"
]
```

**4. Retrieve a specific password (for verification):**
```bash
kubectl get secret nextcloud-credentials -n nextcloud -o jsonpath='{.data.admin-password}' | base64 -d
```

This will output the decrypted admin password. Verify it matches what you encrypted.

**5. Check Sealed Secrets controller logs (if issues occur):**
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets --tail=50
```

Look for errors like:
- `unable to decrypt`: Controller key mismatch or corrupted SealedSecret
- `certificate verify failed`: Certificate fetch issues

**Troubleshooting:**

| Issue | Solution |
|-------|----------|
| SealedSecret exists but Secret not created | Check controller logs for decryption errors |
| `kubeseal --fetch-cert` fails | Verify `kubectl` context is correct and controller is running |
| Secret created but wrong values | Re-encrypt the secret and verify the plaintext source |
| Pods can't read Secret | Check RBAC permissions and Secret mount configuration |

### 4. Traefik IngressRoute
Located at `apps/traefik/ingressroutes/nextcloud.yaml`:
- HTTP route to `nextcloud.denise.home`
- Port 8080 (Nextcloud service port)

## Storage Configuration

### Initial Deployment (SSD/NVMe via Longhorn)

| Component | Storage | StorageClass | Purpose |
|-----------|---------|--------------|---------|
| Nextcloud Data | 50Gi | longhorn | User files, uploads |
| PostgreSQL | 8Gi | longhorn | Database |
| Redis | 1Gi | longhorn | Cache |
| **Total** | **~59Gi** | | |

**⚠️ Important**: Keep data usage light on SSD until HDD is installed.

### Future: HDD Migration (Post F-6)

When the 3.5" HDD is installed and mounted:
1. Configure HDD as external storage in Nextcloud
2. Migrate user data from Longhorn to HDD
3. Reserve SSD for database and cache only
4. Update `values.yaml` to use HDD StorageClass

## Access & Login

### URL
```
http://nextcloud.denise.home
```

### Credentials
- **Username:** `denise`
- **Password:** Stored in `nextcloud-credentials` SealedSecret

To retrieve the password:
```bash
kubectl get secret nextcloud-credentials -n nextcloud -o jsonpath='{.data.admin-password}' | base64 -d
```

**⚠️ Security Recommendation:** Enable Two-Factor Authentication (2FA) after initial setup:
1. Login to Nextcloud UI
2. Go to Settings → Security
3. Install "Two-Factor TOTP Provider" app
4. Configure 2FA with authenticator app (Google Authenticator, Authy, etc.)

For additional security hardening options (SSO, RBAC, audit logging), see [issue #20](https://github.com/denisecodes/k3s-apps/issues/20).

## Configuration

### PHP Upload Limits
```yaml
upload_max_filesize: 8G
post_max_size: 8G
max_input_time: 3600s
max_execution_time: 3600s
```

Conservative limits to prevent SSD fill. Adjust in `values.yaml` as needed.

### Resource Limits
```yaml
requests:
  cpu: 100m
  memory: 512Mi
limits:
  cpu: 2000m
  memory: 2Gi
```

### Database
- **Type:** PostgreSQL (Bitnami)
- **Username:** `nextcloud`
- **Database:** `nextcloud`
- **Password:** Stored in sealed secret

### Caching
- **Type:** Redis (Bitnami)
- **Purpose:** File locking, session storage, caching
- **Auth:** Enabled with password from sealed secret

## Post-Deployment Testing

After ArgoCD syncs the Application:

### 1. Verify Pods
```bash
kubectl get pods -n nextcloud
```

Expected:
- `nextcloud-<hash>` - Running
- `nextcloud-postgresql-0` - Running
- `nextcloud-redis-master-0` - Running

### 2. Check PVCs
```bash
kubectl get pvc -n nextcloud
```

Expected 3 PVCs bound to Longhorn volumes.

### 3. Access UI
Open http://nextcloud.denise.home in browser.

### 4. Test Upload/Download
1. Login with `denise` credentials
2. Upload a test file
3. Download to verify
4. Delete test file

### 5. Verify Storage
```bash
kubectl exec -it deployment/nextcloud -n nextcloud -- df -h /var/www/html/data
```

## Troubleshooting

### Application Not Syncing
```bash
kubectl get application nextcloud -n argocd -o yaml
```

Check `.status.conditions` for errors.

### Pods Not Starting
```bash
kubectl describe pod -n nextcloud <pod-name>
kubectl logs -n nextcloud <pod-name>
```

Common issues:
- PVC not binding (check Longhorn)
- Secret not found (check sealed-secret.yaml deployed)
- Image pull errors (check network/registry)

### Database Connection Issues
```bash
kubectl logs -n nextcloud deployment/nextcloud | grep -i database
kubectl logs -n nextcloud statefulset/nextcloud-postgresql
```

Verify PostgreSQL is ready before Nextcloud starts.

### Cannot Access via Browser

1. **Check DNS**:
   ```bash
   nslookup nextcloud.denise.home
   ```
   Should resolve to Traefik LoadBalancer IP (192.168.50.113)

2. **Check IngressRoute**:
   ```bash
   kubectl get ingressroute nextcloud -n nextcloud
   ```

3. **Check Traefik**:
   ```bash
   kubectl logs -n traefik deployment/traefik | grep nextcloud
   ```

4. **Check Traefik Dashboard**:
   http://traefik.denise.home → Look for `nextcloud.denise.home` route

### Storage Full
```bash
kubectl exec -it deployment/nextcloud -n nextcloud -- du -sh /var/www/html/data
```

If approaching 50Gi, either:
- Clean up unnecessary files
- Expand PVC size in `values.yaml`
- Migrate to HDD storage (recommended)

## Maintenance

### Updating Nextcloud

To update to a newer chart version:

1. Edit `application.yaml`:
   ```yaml
   targetRevision: 9.1.0  # New version
   ```

2. Commit and push - ArgoCD will sync automatically

3. Monitor the upgrade:
   ```bash
   kubectl get pods -n nextcloud -w
   ```

### Backup Strategy

**Database Backup:**
```bash
kubectl exec -it nextcloud-postgresql-0 -n nextcloud -- pg_dump -U nextcloud nextcloud > nextcloud-db-backup.sql
```

**File Backup:**
- Copy PVC data to external storage
- Or use Longhorn's backup feature to S3

### Scaling

Nextcloud deployment is set to 1 replica. For high availability:
1. Change `replicaCount` in `values.yaml`
2. Configure shared storage (NFS/S3)
3. Update `persistence.accessMode` to `ReadWriteMany`

## Future Enhancements

- [ ] Add HTTPS with cert-manager (when F-5 is deployed)
- [ ] Migrate to HDD storage (when F-6 is completed)
- [ ] Configure S3-compatible backup (Longhorn to external storage)
- [ ] Install additional Nextcloud apps (Calendar, Contacts, Talk)
- [ ] Set up automated database backups
- [ ] Enable external storage mounts

## Security Notes

- **HTTP Only**: Currently accessible via HTTP on local network only
- **HTTPS**: Will be added when cert-manager (F-5) is deployed
- **Passwords**: All stored as encrypted SealedSecrets
- **Network**: Not exposed to internet (local network only)
- **Updates**: Monitor for security updates via chart versions

## References

- [Nextcloud Documentation](https://docs.nextcloud.com/)
- [Nextcloud Helm Chart](https://github.com/nextcloud/helm)
- [Issue k3s-homelab#33](https://github.com/denisecodes/k3s-homelab/issues/33)
- [k3s-apps Repository](https://github.com/denisecodes/k3s-apps)
