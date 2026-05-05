#!/bin/bash
# Add new HDD to Longhorn as a storage disk
# This script configures Longhorn to use /mnt/hdd for volume storage

set -e

echo "=== Adding /mnt/hdd to Longhorn Storage ==="

# Check if HDD is mounted
if ! mount | grep -q "/mnt/hdd"; then
    echo "ERROR: /mnt/hdd is not mounted!"
    echo "Please mount the HDD first: sudo mount /dev/sdb1 /mnt/hdd"
    exit 1
fi

echo "✓ HDD is mounted at /mnt/hdd"

# Check available space
df -h /mnt/hdd | grep -v Filesystem

# Create longhorn directory on HDD
echo "Creating /mnt/hdd/longhorn directory..."
sudo mkdir -p /mnt/hdd/longhorn
sudo chown -R root:root /mnt/hdd/longhorn
sudo chmod 755 /mnt/hdd/longhorn

echo "✓ Directory created"

# Add disk to Longhorn using kubectl
echo "Adding disk to Longhorn node configuration..."

NODE_NAME="denise-home-k3s"

# Get current disk config
kubectl get nodes.longhorn.io $NODE_NAME -n longhorn-system -o yaml > /tmp/longhorn-node.yaml

# Add new disk to the config (we'll use a patch)
cat > /tmp/longhorn-disk-patch.yaml <<EOF
spec:
  disks:
    default-disk-7282931c5629d568:
      allowScheduling: true
      diskDriver: ""
      diskType: filesystem
      evictionRequested: false
      path: /var/lib/longhorn/
      storageReserved: 74464559923
      tags: []
    hdd-disk-7-3tb:
      allowScheduling: true
      diskDriver: ""
      diskType: filesystem
      evictionRequested: false
      path: /mnt/hdd/longhorn
      storageReserved: 247390662656  # 230GB reserve (keep 10% free)
      tags: ["hdd", "high-capacity"]
EOF

# Apply the patch
kubectl patch nodes.longhorn.io $NODE_NAME -n longhorn-system --patch-file /tmp/longhorn-disk-patch.yaml --type merge

echo "✓ Disk added to Longhorn"

# Verify
echo ""
echo "=== Verification ==="
kubectl get nodes.longhorn.io $NODE_NAME -n longhorn-system -o jsonpath='{.spec.disks}' | jq 'keys'

echo ""
echo "=== Longhorn Node Status ==="
kubectl get nodes.longhorn.io $NODE_NAME -n longhorn-system -o wide

echo ""
echo "✓ Complete! Longhorn will now use /mnt/hdd/longhorn for new volumes."
echo "  You can verify in Longhorn UI at http://longhorn.denise.home"
