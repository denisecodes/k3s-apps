# Jellyfin Storage Migration Guide

This guide explains how to migrate Jellyfin data from old PVCs to new larger PVCs using Longhorn and rsync.

## Overview

**Storage expansion:**
- **Movies**: 20Gi → 1.5TB (75x expansion)
- **TV Shows**: 30Gi → 2.0TB (67x expansion)
- **Cache**: 50Gi → 500Gi (10x expansion) - *automatically rebuilt, no manual migration needed*
- **Music**: Removed (consolidated to Navidrome)

**Estimated downtime**: 30-45 minutes (Jellyfin only; other services remain online)

## Prerequisites

1. New PVCs will be automatically created by ArgoCD when changes are synced:
   ```bash
   # Verify all PVCs are bound once ArgoCD syncs
   kubectl get pvc -n jellyfin
   # Output should show:
   # - jellyfin-media-movies (20Gi - old)
   # - jellyfin-media-movies-new (1.5Ti - new)
   # - jellyfin-media-tv (30Gi - old)
   # - jellyfin-media-tv-new (2Ti - new)
   # - jellyfin-cache-new (500Gi - new)
   # - jellyfin-cache (50Gi - old, will be replaced by new one)
   ```

2. Longhorn volumes should be healthy:
   ```bash
   # Check Longhorn UI at http://longhorn.denise.home
   # All volumes should show healthy status
   ```

3. Current Jellyfin should be running normally with data in old volumes

## Migration Steps

### Step 1: Scale Down Jellyfin

```bash
kubectl scale deployment jellyfin -n jellyfin --replicas=0

# Verify pod is terminated
kubectl get pods -n jellyfin
```

### Step 2: Create Migration Pod

Apply the migration pod that will handle rsync operations:

```bash
kubectl apply -f apps/jellyfin/migration-pod.yaml -n jellyfin

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=jellyfin-migration -n jellyfin --timeout=300s
```

### Step 3: Execute Data Migration

The migration pod runs rsync operations for movies and TV shows. Execute via kubectl exec:

```bash
# Get the migration pod name
POD=$(kubectl get pod -l app=jellyfin-migration -n jellyfin -o jsonpath='{.items[0].metadata.name}')

# Migrate Movies (20Gi → 1.5TB)
echo "=== Migrating Movies (20Gi → 1.5TB) ==="
kubectl exec -it $POD -n jellyfin -- rsync -avz --delete /old-data/movies/ /new-data/movies/
# Expected time: 5-10 minutes depending on storage speed

# Migrate TV Shows (30Gi → 2TB)
echo "=== Migrating TV Shows (30Gi → 2TB) ==="
kubectl exec -it $POD -n jellyfin -- rsync -avz --delete /old-data/tv/ /new-data/tv/
# Expected time: 10-15 minutes
```

**Note on Cache**: The cache contains temporary transcoding files and can be safely discarded. The new cache volume will be automatically populated by Jellyfin as needed.

### Step 4: Verify Migration Integrity

```bash
# Get the migration pod name (if needed again)
POD=$(kubectl get pod -l app=jellyfin-migration -n jellyfin -o jsonpath='{.items[0].metadata.name}')

# Verify file counts match between old and new volumes
echo "=== Verifying Movies ==="
kubectl exec $POD -n jellyfin -- bash -c 'echo "Old:"; find /old-data/movies -type f | wc -l; echo "New:"; find /new-data/movies -type f | wc -l'

echo "=== Verifying TV Shows ==="
kubectl exec $POD -n jellyfin -- bash -c 'echo "Old:"; find /old-data/tv -type f | wc -l; echo "New:"; find /new-data/tv -type f | wc -l'
```

### Step 5: Update Jellyfin Deployment

Once verified, update values.yaml to point to new PVCs:

```yaml
# In apps/jellyfin/values.yaml
volumes:
  - name: media-movies
    persistentVolumeClaim:
      claimName: jellyfin-media-movies-new  # Changed to -new
  - name: media-tv
    persistentVolumeClaim:
      claimName: jellyfin-media-tv-new  # Changed to -new
```

Then sync with ArgoCD:

```bash
argocd app sync jellyfin

# Wait for deployment to be ready
kubectl rollout status deployment/jellyfin -n jellyfin --timeout=5m
```

### Step 6: Verify Jellyfin is Running

```bash
# Check that Jellyfin pod is running
kubectl get pods -n jellyfin

# Check Jellyfin logs for any errors
kubectl logs -f deployment/jellyfin -n jellyfin

# Test access at http://jellyfin.denise.home
```

### Step 7: Delete Migration Pod

Once verification is complete:

```bash
kubectl delete pod -l app=jellyfin-migration -n jellyfin
```

### Step 8: Delete Old PVCs (After Verification)

Once you've verified Jellyfin is working correctly with new storage (wait at least 24-48 hours):

```bash
# Delete old PVC YAML files from Git
git rm apps/jellyfin/pvcs/media-movies.yaml
git rm apps/jellyfin/pvcs/media-tv.yaml

# Commit the removal
git commit -m "chore: remove old Jellyfin media PVCs after successful migration"

# The old PVs will be retained until manually deleted
# After a safe period, delete the PVs:
kubectl delete pv <old-movie-pv-name> <old-tv-pv-name>
```

## Rollback Procedure

If migration fails or issues occur:

1. Stop Jellyfin:
   ```bash
   kubectl scale deployment jellyfin -n jellyfin --replicas=0
   ```

2. Revert values.yaml to point to old PVCs:
   ```yaml
   volumes:
     - name: media-movies
       persistentVolumeClaim:
         claimName: jellyfin-media-movies  # Revert to old
     - name: media-tv
       persistentVolumeClaim:
         claimName: jellyfin-media-tv  # Revert to old
   ```

3. Scale Jellyfin back up:
   ```bash
   kubectl scale deployment jellyfin -n jellyfin --replicas=1
   ```

## Troubleshooting

### Migration Pod Not Starting
- Check if PVCs are available: `kubectl get pvc -n jellyfin`
- Check pod logs: `kubectl logs -n jellyfin jellyfin-migration`
- Verify Longhorn is running: `kubectl get pods -n longhorn-system`

### Rsync Hangs or is Very Slow
- Check Longhorn I/O performance in Longhorn UI
- Check node disk I/O: `iostat -xm 1`
- Consider running migrations during off-peak hours

### Files Not Synced
- Re-run rsync command—it's safe to run multiple times
- Check disk space on target: `df -h /new-data/`
- Check file permissions: `ls -la /old-data/ vs /new-data/`

### Jellyfin Can't Find Media After Migration
- Verify PVC names in values.yaml match deployed volumes
- Check Jellyfin logs for mount errors
- Manually verify files exist in container:
  ```bash
  kubectl exec deployment/jellyfin -n jellyfin -- ls -la /media/movies
  kubectl exec deployment/jellyfin -n jellyfin -- ls -la /media/tv
  ```

### Cache PVC Issues
- The new cache PVC will be created by Helm when values.yaml is updated
- Old cache can be safely deleted after migration (contains only temporary files)
- Jellyfin will rebuild cache as streams are played

## Monitoring During Migration

While rsync is running, monitor progress:

```bash
# Monitor Longhorn metrics
# Visit http://longhorn.denise.home and check replica sync progress

# Monitor PVC usage
watch -n 5 'kubectl get pvc -n jellyfin'
```

## Post-Migration Validation

After Jellyfin comes back online:

1. ✅ Wait for library scan (5-10 minutes for large libraries)
2. ✅ Test streaming a movie and TV show
3. ✅ Verify hardware transcoding works (Intel GPU acceleration)
4. ✅ Check cache is being used (should grow over time)
5. ✅ Monitor disk usage: `kubectl exec deployment/jellyfin -n jellyfin -- df -h /media`
6. ✅ Verify no errors in Jellyfin logs: `kubectl logs deployment/jellyfin -n jellyfin | grep -i error`

## Notes

- **Single node limitation**: With ReadWriteOnce access mode, PVCs can only be mounted on one node
- **Replica count**: Longhorn replica count = 1 (no duplication on single HDD, recommended for homelab)
- **Cache clearing**: Old cache volume can be safely deleted after successful migration
- **Monitoring enabled**: Longhorn ServiceMonitor is now enabled for Prometheus metrics
- **Future**: Plan for backup solution (Velero/restic) in separate issue #65


