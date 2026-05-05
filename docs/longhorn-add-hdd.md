# Adding a New HDD to Longhorn

This guide documents the steps required to add a new hard drive to your k3s cluster and configure it for use with Longhorn storage.

## Prerequisites

- Physical HDD installed and detected by the node (`lsblk` to verify)
- Node has the `node.longhorn.io/create-default-disk` annotation set to "true" (or manual disk addition)

## Steps

### 1. Format and Mount the New Drive

```bash
# List block devices to find your new drive (e.g., /dev/sdb)
lsblk

# Create a filesystem (ext4 recommended for Longhorn)
sudo mkfs.ext4 /dev/sdb

# Create mount point
sudo mkdir -p /mnt/hdd/longhorn

# Mount the drive
sudo mount /dev/sdb /mnt/hdd/longhorn

# Add to /etc/fstab for persistence across reboots
echo '/dev/sdb /mnt/hdd/longhorn ext4 defaults 0 2' | sudo tee -a /etc/fstab

# Verify mount
df -h | grep longhorn
```

### 2. Set Storage Reserved (Important)

Longhorn needs free space on the filesystem for overhead. Set `Storage Reserved` to prevent Longhorn from filling the disk completely.

**Recommended reservation:**
- For filesystems: ~10% of total capacity, or minimum 20-50GB
- Formula: `Storage Reserved = Total Capacity × 0.10`

Example for a 3TB drive:
```
Storage Reserved = 3TB × 0.10 ≈ 300GB
Storage Reserved (bytes) = 300 × 1024^3 ≈ 322122547200
```

**To set via Longhorn UI:**
1. Navigate to **Node** tab
2. Click the node with the new drive
3. Click **Edit** on the disk
4. Set **Storage Reserved** to appropriate value in bytes
5. Click **Save**

**To set via kubectl:**
```bash
# Get the node name
kubectl get nodes

# Edit the node annotations
kubectl annotate node <node-name> \
  longhorn.io/storage-reserved-<disk-path>=<bytes> \
  --overwrite
```

### 3. Add Disk to Longhorn

**Via Longhorn UI:**
1. Navigate to **Node** tab
2. Click the node where the drive is mounted
3. Click **Edit** next to the node
4. Click **Add Disk**
5. Set:
   - **Name**: e.g., `hdd-disk-7-3tb`
   - **Path**: `/mnt/hdd/longhorn`
   - **Disk Type**: `filesystem`
   - **Storage Reserved**: (calculated above)
6. Click **Save**

**Via kubectl (manual):**
```bash
# Edit the node resource
kubectl edit node.longhorn.io <node-name> -n longhorn-system

# Add disk under spec.disks:
spec:
  disks:
    hdd-disk-7-3tb:
      path: /mnt/hdd/longhorn
      type: filesystem
      storageReserved: 322122547200  # 300GB in bytes
      allowScheduling: true
```

### 4. Verify Disk is Ready

```bash
# Check Longhorn UI
# Navigate to Node tab - disk should show:
# - Status: Scheduled
# - Conditions: Ready

# Or check via kubectl
kubectl get node.longhorn.io -n longhorn-system <node-name> -o yaml | grep -A 10 "disks:"
```

### 5. Test PVC Creation

```bash
# Create a test PVC to verify the new disk is usable
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

# Check if PVC binds successfully
kubectl get pvc test-pvc

# Clean up
kubectl delete pvc test-pvc
```

## Troubleshooting

### Disk Shows "Unschedulable"
- Check available space: `df -h /mnt/hdd/longhorn`
- Verify `Storage Reserved` isn't too high (leaving no room for volumes)
- Check Longhorn conditions: `kubectl describe node.longhorn.io <node> -n longhorn-system`

### PVC Stuck in "Pending"
- Verify the disk is ready in Longhorn UI
- Check if Longhorn has enough free space for the requested size
- Review events: `kubectl get events -n longhorn-system --sort-by='.lastTimestamp'`

### Expansion Fails with "Insufficient Physical Space"
This happens when Longhorn's minimum free space requirement isn't met:
```
error: disk does not have sufficient physical space for expansion:
physical free space would drop below minimal
```

**Fix:**
1. Increase `Storage Reserved` to leave more free space
2. Or expand the physical disk capacity
3. The Longhorn minimum is calculated as: `max(10% of disk, 10GB)` approximately

## Notes

- **Tags**: Add tags like `hdd`, `high-capacity` to disks for scheduling rules
- **Replica Count**: For single-node setups, keep replica count at 1 (no duplication)
- **Filesystem vs Block**: Use `filesystem` type for most use cases (allows expansion)
- **Multiple Disks**: Longhorn can use multiple disks on the same node - add each as a separate disk entry
