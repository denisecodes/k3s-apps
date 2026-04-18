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
- References `values.yaml` for Helm chart overrides
- Deploys to `nextcloud` namespace
- Auto-sync and self-heal enabled
- Creates namespace automatically

### 2. Helm Values Override (`values.yaml`)
Configuration for:
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
