# Adding a New HDD to Longhorn

This guide documents the exact steps to add a new hard drive to your k3s cluster and configure it for Longhorn storage.

## Prerequisites

- Physical HDD installed and detected by the node
- Access to the master node (or node where the drive is installed)

## Steps

### 1. Identify and Format the New Drive

```bash
# List block devices to find your new drive (e.g., /dev/sdb or /dev/sdb1)
lsblk
lsblk -f
```

### 2. Create GPT Partition Table and Partition

```bash
# Run fdisk on the new drive (e.g., /dev/sdb - NOT the partition)
sudo fdisk /dev/sdb

# Inside fdisk, run these commands:
# g  - create a new GPT partition table
# n  - create a new partition
#    - accept default partition number (Enter)
#    - accept default first sector (Enter)
#    - accept default last sector (Enter) to use whole disk
# w  - write changes and exit
```

This creates `/dev/sdb1` partition.

### 3. Format the Partition with ext4

```bash
# Format the new partition (NOT the whole disk)
sudo mkfs.ext4 /dev/sdb1
```

### 3. Get the UUID for fstab

```bash
# Get UUID for persistent mounting
sudo blkid /dev/sdb1
```

### 4. Create Mount Point and Mount

```bash
# Create mount directory
sudo mkdir -p /mnt/hdd

# Mount the drive
sudo mount /dev/sdb1 /mnt/hdd

# Verify mount
df -h
```

### 5. Add to fstab for Persistence Across Reboots

```bash
# Add to fstab using UUID (replace with your actual UUID from blkid output)
echo "UUID=ef255403-6a65-4a41-820d-09fcda970666 /mnt/hdd ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Reload systemd to recognize changes
sudo systemctl daemon-reload

# Test fstab entry (unmount and remount all)
sudo umount /mnt/hdd && sudo mount -a

# Verify
df -h /mnt/hdd
```

### 6. Create Longhorn Directory

```bash
# Create the longhorn subdirectory
sudo mkdir -p /mnt/hdd/longhorn

# Set permissions
sudo chmod 755 /mnt/hdd/longhorn

# Verify
df -h /mnt/hdd
```

### 7. Add Disk to Longhorn

```bash
# Edit the Longhorn node resource
kubectl edit nodes.longhorn.io denise-home-k3s -n longhorn-system
```

In the editor, add the disk under `spec.disks:`:

```yaml
spec:
  disks:
    hdd-disk-7-3tb:          # Choose a descriptive name
      path: /mnt/hdd/longhorn
      type: filesystem
      storageReserved: 247390662656  # ~230GB in bytes (adjust based on your capacity)
      allowScheduling: true
      tags:
        - hdd
        - high-capacity
```

**Save and exit** (`:wq` in vi/vim or `Ctrl+X` then `Y` in nano).

### 8. Verify Disk is Ready

```bash
# Check the disks on the node
kubectl get nodes.longhorn.io denise-home-k3s -n longhorn-system -o jsonpath='{.spec.disks}' | jq 'keys'

# Or check via Longhorn UI:
# Navigate to Node tab → Click the node → Verify disk shows:
#   - Status: Scheduled
#   - Conditions: Ready
```

## Storage Reserved Calculation

The `storageReserved` value is in bytes and should be ~10% of your total capacity:

| Disk Size | Reserved (10%) | Bytes |
|-----------|-----------------|-------|
| 1TB       | 100GB           | 107374182400 |
| 2TB       | 200GB           | 214748364800 |
| 3TB       | 300GB           | 322122547200 |
| 4TB       | 400GB           | 429496729600 |

Your current setting: `247390662656` bytes ≈ 230GB (custom amount for your 3TB drive).

## Verification

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
- Check available space: `df -h /mnt/hdd`
- Verify `storageReserved` isn't too high (leaving no room for volumes)
- Check Longhorn conditions: `kubectl describe node.longhorn.io <node> -n longhorn-system`

### PVC Stuck in "Pending"
- Verify the disk is ready in Longhorn UI (Node tab)
- Check if Longhorn has enough free space for the requested size
- Review events: `kubectl get events -n longhorn-system --sort-by='.lastTimestamp'`

### Expansion Fails with "Insufficient Physical Space"
This happens when Longhorn's minimum free space requirement isn't met:
```
error: disk does not have sufficient physical space for expansion:
physical free space would drop below minimal
```

**Fix:**
1. Increase `storageReserved` to leave more free space
2. Or expand the physical disk capacity
3. The Longhorn minimum is calculated as: `max(10% of disk, 10GB)` approximately

## Notes

- **Tags**: Add tags like `hdd`, `high-capacity` to disks for scheduling rules in Longhorn
- **Replica Count**: For single-node setups, keep replica count at 1 (no duplication)
- **Filesystem vs Block**: Use `filesystem` type for most use cases (allows expansion)
- **Multiple Disks**: Longhorn can use multiple disks on the same node - add each as a separate disk entry
- **Commands you ran** (from history):
  ```bash
  lsblk
  lsblk -f
  sudo mkfs.ext4 /dev/sdb1
  sudo mkdir -p /mnt/hdd
  sudo mount /dev/sdb1 /mnt/hdd
  df -h
  sudo blkid /dev/sdb1
  sudo nano /etc/fstab
  sudo mkdir -p /mnt/hdd/longhorn
  sudo chmod 755 /mnt/hdd/longhorn
  kubectl edit nodes.longhorn.io denise-home-k3s -n longhorn-system
  kubectl get nodes.longhorn.io denise-home-k3s -n longhorn-system -o jsonpath='{.spec.disks}'
  ```
