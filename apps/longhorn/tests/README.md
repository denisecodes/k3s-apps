# Longhorn Test Resources

This directory contains automated test resources to verify Longhorn persistent storage is working correctly.

## How It Works

The test runs **automatically** via ArgoCD after Longhorn is deployed:

1. **PVC Creation** - ArgoCD creates a 1Gi PersistentVolumeClaim using the `longhorn` StorageClass
2. **Automated Test Job** - A Kubernetes Job (PostSync hook) runs comprehensive storage tests
3. **Verification** - The job tests read/write operations, data persistence, and multi-file handling
4. **Auto-cleanup** - Test resources are automatically cleaned up before re-runs

## What Gets Tested

The automated test job verifies:
- ✅ PVC is provisioned successfully by Longhorn
- ✅ Volume is mounted correctly in the pod
- ✅ Write operations work
- ✅ Read operations work
- ✅ Data persists on the volume
- ✅ Multiple files can be created and accessed

## Checking Test Results

After ArgoCD syncs Longhorn, check the test job status:

```bash
# Check job status (should show Completed)
kubectl get job longhorn-test-job -n longhorn-system

# View test logs (detailed test output)
kubectl logs -n longhorn-system job/longhorn-test-job

# Check PVC status (should be Bound)
kubectl get pvc longhorn-test-pvc -n longhorn-system
```

### Expected Output

Successful test output looks like:

```
================================================
Longhorn Storage Provisioning Test
================================================

Test 1: Writing to persistent volume...
✓ Write successful

Test 2: Reading from persistent volume...
Content: Longhorn storage test - [timestamp]
✓ Read successful

Test 3: Verifying data persistence...
✓ File exists on volume

Test 4: Writing multiple files...
✓ Multiple files created

Test 5: Verifying all files...
Found 4 files
✓ All files present

================================================
✓ All Longhorn storage tests passed!
================================================

Summary:
  - PVC provisioned successfully
  - Volume mounted correctly
  - Read/write operations working
  - Data persistence verified

Longhorn is ready for production workloads!
```

## Troubleshooting

### Job fails or is pending

Check if Longhorn is fully deployed:

```bash
# Check Longhorn pods
kubectl get pods -n longhorn-system

# Check StorageClass
kubectl get storageclass longhorn

# Describe the PVC to see events
kubectl describe pvc longhorn-test-pvc -n longhorn-system
```

### PVC stuck in Pending

Longhorn may still be initializing. Wait a few minutes and check:

```bash
# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager

# Check if nodes are ready
kubectl get nodes -n longhorn-system
```

## Why longhorn-system Namespace?

Test resources are created in the `longhorn-system` namespace (same as Longhorn itself) to:
- ✅ Keep test resources organized with Longhorn components
- ✅ Avoid cluttering the `default` namespace
- ✅ Make it easy to see all Longhorn-related resources in one place
- ✅ Simplify cleanup (delete entire namespace if needed)

## Manual Testing (Optional)

If you want to test manually instead of the automated test:

```bash
# Apply test resources manually
kubectl apply -f apps/longhorn/tests/test-pvc-pod.yaml

# Check the test job status
kubectl get job longhorn-test-job -n longhorn-system

# View test logs to track results
kubectl logs -n longhorn-system job/longhorn-test-job

# Delete test resources when done
kubectl delete -f apps/longhorn/tests/test-pvc-pod.yaml
```

## Verification via Longhorn UI

Access the Longhorn UI to see volumes and replicas:

```bash
# Port-forward to Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Open browser to http://localhost:8080
```

You should see:
- The test volume created
- Volume health status (green)
- Replica placement on your node(s)
- Storage usage statistics

## Notes

- **Tests run automatically** via ArgoCD PostSync hooks - no manual intervention needed
- **Tests re-run on every ArgoCD sync** to continuously verify Longhorn health
- **BeforeHookCreation policy** ensures old test resources are cleaned up before new ones
- **Test data is ephemeral** - gets recreated on each sync
