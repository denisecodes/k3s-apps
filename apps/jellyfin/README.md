# Jellyfin - 4K Media Server

## Overview

Jellyfin is a free, open-source media server for managing and streaming your media library. This deployment is configured for 4K video transcoding using Intel Quick Sync hardware acceleration.

**Current Status:** Testing deployment on Longhorn storage  
**Future Plan:** Migrate to HDD storage after F-6 (HDD mount) is complete

## Architecture

- **Helm Chart:** jellyfin/jellyfin v3.2.0 (Official)
- **Application:** Jellyfin v10.11.8
- **Namespace:** `jellyfin`
- **Storage:** Longhorn (testing), HDD (future)
- **Ingress:** Traefik IngressRoute
- **Hardware Acceleration:** Intel Quick Sync (UHD 630)

## Dependencies

| Dependency | Status | Description |
|------------|--------|-------------|
| F-1: Sealed Secrets | ✅ Deployed | Credential encryption |
| F-2: Longhorn | ✅ Deployed | Storage provisioner |
| F-3/F-4: Traefik + DNS | ✅ Deployed | Ingress and routing |
| F-6: HDD Mount | ⏳ Not yet installed | Required for production media library |

## Storage Configuration

### Current (Testing on Longhorn)

| Volume | PVC Name | Size | Mount Path | Purpose |
|--------|----------|------|------------|---------|
| Config | `jellyfin-config` | 10Gi | `/config` | Database, settings, metadata |
| Cache | `jellyfin-cache` | 50Gi | `/cache` | Transcoding temp files |
| Movies | `jellyfin-media-movies` | 20Gi | `/media/movies` | Movie library (testing) |
| TV Shows | `jellyfin-media-tv` | 10Gi | `/media/tv` | TV show library (testing) |
| Music | `jellyfin-media-music` | 5Gi | `/media/music` | Music library (testing) |

**Total Storage:** 105Gi on Longhorn

### Future (Production on HDD - Post F-6)

After HDD is installed, media volumes will be migrated to HDD while config/cache remain on Longhorn for performance.

## Hardware Transcoding

### Intel Quick Sync Configuration

Jellyfin is configured to use Intel Quick Sync Video for hardware-accelerated transcoding:

- **GPU:** Intel UHD Graphics 630
- **Device:** `/dev/dri` mounted in pod
- **Capability:** `SYS_ADMIN` for device access
- **Supported Codecs:** H.264, HEVC (H.265), VP9

### Resource Allocation

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 4 cores
    memory: 8Gi
```

## Deployment

### ArgoCD Application

This application is deployed automatically by ArgoCD using the **multiple sources pattern**:

1. **Helm Chart Source:** Official Jellyfin chart from `https://jellyfin.github.io/jellyfin-helm/`
2. **Git Source:** Values and manifests from this repository

ArgoCD monitors this directory and automatically syncs changes with:
- **Prune:** Enabled (removes deleted resources)
- **Self-Heal:** Enabled (reverts manual changes)

### Files

```
apps/jellyfin/
├── application.yaml           # ArgoCD Application definition
├── values.yaml               # Helm chart values override
├── sealed-secret.yaml        # Admin password (encrypted)
├── pvcs/
│   ├── media-movies.yaml    # 20Gi PVC for movies
│   ├── media-tv.yaml        # 10Gi PVC for TV shows
│   └── media-music.yaml     # 5Gi PVC for music
└── README.md                 # This file

apps/traefik/ingressroutes/
└── jellyfin.yaml             # HTTP routing configuration
```

## Post-Deployment Setup

### ⚠️ IMPORTANT: Manual First-Time Setup Required

Jellyfin does not support automated admin user creation. You must complete the setup wizard manually after deployment.

### Step-by-Step Setup

#### 1. Wait for Pod to Start

```bash
kubectl get pods -n jellyfin
kubectl logs -n jellyfin -l app.kubernetes.io/name=jellyfin -f
```

#### 2. Access Jellyfin Web UI

Navigate to: **http://jellyfin.denise.home**

The first-time setup wizard will appear automatically.

#### 3. Create Admin User

- **Username:** `denise`
- **Password:** Retrieve from SealedSecret:

```bash
kubectl get secret jellyfin-credentials -n jellyfin -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

#### 4. Configure Media Libraries

Add the following library paths in Jellyfin:

| Library Type | Display Name | Path |
|--------------|--------------|------|
| Movies | Movies | `/media/movies` |
| TV Shows | TV Shows | `/media/tv` |
| Music | Music | `/media/music` |

**Important:** Keep library sizes small (< 35Gi total) until HDD is installed.

#### 5. Enable Hardware Transcoding

1. Navigate to **Dashboard → Playback**
2. Under **Transcoding**, find **Hardware Acceleration**
3. Select **Intel Quick Sync Video**
4. Click **Save**

#### 6. Verify Hardware Acceleration

**Check if /dev/dri is mounted:**
```bash
kubectl exec -n jellyfin -it $(kubectl get pod -n jellyfin -l app.kubernetes.io/name=jellyfin -o jsonpath='{.items[0].metadata.name}') -- ls -la /dev/dri
```

Expected output:
```
drwxr-xr-x    2 root     root           80 Jan  1 00:00 .
drwxr-xr-x   15 root     root         3660 Jan  1 00:00 ..
crw-rw----    1 root     video     226,   0 Jan  1 00:00 card0
crw-rw----    1 root     render    226, 128 Jan  1 00:00 renderD128
```

**Test transcoding with a sample video:**
1. Upload a small 4K test video to `/media/movies`
2. Play the video and check transcoding logs:
   ```bash
   kubectl logs -n jellyfin -l app.kubernetes.io/name=jellyfin | grep -i transcode
   ```
3. Look for `vaapi` or `qsv` (Quick Sync) in the logs
4. Monitor CPU vs GPU usage - GPU should be utilized for transcoding

## Verification Checklist

After deployment, verify the following:

### Pod Health
```bash
# Check pod status
kubectl get pods -n jellyfin

# Check pod details
kubectl describe pod -n jellyfin -l app.kubernetes.io/name=jellyfin

# View logs
kubectl logs -n jellyfin -l app.kubernetes.io/name=jellyfin -f
```

### Volume Mounts
```bash
# Check mounted filesystems
kubectl exec -n jellyfin -it $(kubectl get pod -n jellyfin -l app.kubernetes.io/name=jellyfin -o jsonpath='{.items[0].metadata.name}') -- df -h
```

Expected mounts:
- `/config` (10Gi)
- `/cache` (50Gi)
- `/media/movies` (20Gi)
- `/media/tv` (10Gi)
- `/media/music` (5Gi)

### Service and Ingress
```bash
# Check service
kubectl get svc -n jellyfin

# Check IngressRoute
kubectl get ingressroute -n jellyfin
```

### Hardware Access
```bash
# Verify /dev/dri device
kubectl exec -n jellyfin -it $(kubectl get pod -n jellyfin -l app.kubernetes.io/name=jellyfin -o jsonpath='{.items[0].metadata.name}') -- ls -la /dev/dri
```

## Accessing Jellyfin

- **URL:** http://jellyfin.denise.home
- **Admin User:** `denise`
- **Password:** Stored in SealedSecret `jellyfin-credentials`

## HDD Migration (Post-F-6)

When the HDD is installed (F-6 complete), follow these steps to migrate media storage:

### 1. Update values.yaml

Replace the PVC-based media volumes with HDD hostPath volumes:

**Before (Longhorn PVCs):**
```yaml
volumes:
  - name: media-movies
    persistentVolumeClaim:
      claimName: jellyfin-media-movies
  - name: media-tv
    persistentVolumeClaim:
      claimName: jellyfin-media-tv
  - name: media-music
    persistentVolumeClaim:
      claimName: jellyfin-media-music
```

**After (HDD hostPath):**
```yaml
volumes:
  - name: media-movies
    hostPath:
      path: /mnt/hdd/media/movies
      type: Directory
  - name: media-tv
    hostPath:
      path: /mnt/hdd/media/tv
      type: Directory
  - name: media-music
    hostPath:
      path: /mnt/hdd/media/music
      type: Directory
```

### 2. Optional: Backup Test Media

If you want to keep test videos:
```bash
# Copy from PVC to local
kubectl cp jellyfin/<pod-name>:/media/movies ./movies-backup
kubectl cp jellyfin/<pod-name>:/media/tv ./tv-backup
kubectl cp jellyfin/<pod-name>:/media/music ./music-backup
```

### 3. Delete PVC Manifests

```bash
# Remove PVC manifests from Git
rm apps/jellyfin/pvcs/media-*.yaml

# Update directory structure in README if needed
```

### 4. Commit and Push

```bash
git add apps/jellyfin/
git commit -m "feat: migrate Jellyfin media storage to HDD"
git push
```

### 5. ArgoCD Auto-Sync

ArgoCD will detect the changes and:
1. Delete old PVCs (due to prune policy)
2. Restart Jellyfin pod with HDD-mounted volumes
3. Jellyfin will detect new media paths

### 6. Optional: Restore Test Media

If you backed up test media:
```bash
# Copy back to HDD (via pod or direct HDD mount)
kubectl cp ./movies-backup jellyfin/<pod-name>:/media/movies
```

### 7. Re-scan Libraries

In Jellyfin Dashboard:
1. Go to **Dashboard → Libraries**
2. For each library, click **Scan Library**
3. Or add new media directly to HDD paths

## Troubleshooting

### Pod Won't Start

**Symptoms:** Pod in `Pending` or `CrashLoopBackOff` state

**Solutions:**
```bash
# Check pod events
kubectl describe pod -n jellyfin -l app.kubernetes.io/name=jellyfin

# Check PVC status
kubectl get pvc -n jellyfin

# Ensure Longhorn is healthy
kubectl get pods -n longhorn-system
```

### /dev/dri Not Accessible

**Symptoms:** Hardware transcoding not available, CPU-only transcoding

**Solutions:**
```bash
# Verify device exists on host
ls -la /dev/dri

# Check pod security context
kubectl get pod -n jellyfin -l app.kubernetes.io/name=jellyfin -o yaml | grep -A 10 securityContext

# Ensure video group is accessible (group 44)
kubectl exec -n jellyfin -it $(kubectl get pod -n jellyfin -l app.kubernetes.io/name=jellyfin -o jsonpath='{.items[0].metadata.name}') -- id
```

### Transcoding Uses CPU Instead of GPU

**Symptoms:** High CPU usage during playback, slow transcoding

**Solutions:**
1. Verify hardware acceleration is enabled in Jellyfin settings
2. Check transcoding logs for errors:
   ```bash
   kubectl logs -n jellyfin -l app.kubernetes.io/name=jellyfin | grep -i vaapi
   ```
3. Ensure Intel Quick Sync is selected (not VAAPI generic)
4. Test with different video codecs (H.264 vs HEVC)

### Can't Access Web UI

**Symptoms:** `http://jellyfin.denise.home` not loading

**Solutions:**
```bash
# Check service
kubectl get svc -n jellyfin

# Check IngressRoute
kubectl get ingressroute -n jellyfin -o yaml

# Check Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik

# Test direct pod access
kubectl port-forward -n jellyfin svc/jellyfin 8096:8096
# Then access http://localhost:8096
```

### Library Not Scanning

**Symptoms:** Media files not appearing in library

**Solutions:**
1. Verify volume mounts: `kubectl exec -n jellyfin ... -- ls -la /media/movies`
2. Check file permissions on PVC
3. Manually trigger scan: Dashboard → Libraries → Scan Library
4. Check Jellyfin logs for errors:
   ```bash
   kubectl logs -n jellyfin -l app.kubernetes.io/name=jellyfin | grep -i scan
   ```

### Out of Storage

**Symptoms:** Transcoding fails, cache full errors

**Solutions:**
```bash
# Check PVC usage
kubectl exec -n jellyfin -it $(kubectl get pod -n jellyfin -l app.kubernetes.io/name=jellyfin -o jsonpath='{.items[0].metadata.name}') -- df -h

# Increase cache PVC size in values.yaml
# (Longhorn supports volume expansion)

# Clean transcoding cache in Jellyfin:
# Dashboard → Scheduled Tasks → Clean Transcode Cache → Run
```

## Maintenance

### Updating Jellyfin Version

To update to a newer Jellyfin version:

1. Check available chart versions:
   ```bash
   helm search repo jellyfin/jellyfin --versions
   ```

2. Update `application.yaml`:
   ```yaml
   targetRevision: 3.x.x  # New version
   ```

3. Commit and push - ArgoCD will sync automatically

### Adjusting Storage Sizes

To increase PVC sizes (Longhorn supports expansion):

1. Update `values.yaml`:
   ```yaml
   persistence:
     cache:
       size: 100Gi  # Increased from 50Gi
   ```

2. Or update PVC manifests:
   ```yaml
   resources:
     requests:
       storage: 30Gi  # Increased from 20Gi
   ```

3. Commit and push - Longhorn will expand volumes automatically

### Monitoring Resource Usage

```bash
# Check pod resource usage
kubectl top pod -n jellyfin

# Check detailed metrics
kubectl get pod -n jellyfin -l app.kubernetes.io/name=jellyfin -o yaml | grep -A 10 resources

# Monitor during transcoding
watch kubectl top pod -n jellyfin
```

## References

- **Official Jellyfin Helm Chart:** https://github.com/jellyfin/jellyfin-helm
- **Jellyfin Documentation:** https://jellyfin.org/docs/
- **Intel Quick Sync Guide:** https://jellyfin.org/docs/general/administration/hardware-acceleration/intel
- **Issue:** k3s-homelab#34 (A-4: Deploy Jellyfin via ArgoCD)
- **Nextcloud Deployment Pattern:** k3s-apps PRs #22, #23
- **ArgoCD Multiple Sources:** https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/
