# Longhorn Deployment

Longhorn provides persistent storage for the K3s cluster via ArgoCD.

## ⚠️ Known Issue: First-Time Installation

The Longhorn Helm chart has a `pre-upgrade` hook that causes issues on **fresh installations** (not upgrades). The hook job fails because it needs a ServiceAccount that doesn't exist yet (chicken-and-egg problem).

### Workaround for First Install

**Option 1: Delete the stuck hook job (Recommended)**

1. ArgoCD will show Longhorn as OutOfSync with message: `waiting for completion of hook batch/Job/longhorn-pre-upgrade`
2. Delete the stuck job:
   ```bash
   kubectl delete job longhorn-pre-upgrade -n longhorn-system
   ```
3. ArgoCD will proceed with the installation
4. Wait for Longhorn pods to be ready (~2-3 minutes)

**Option 2: Manual Helm install first**

If the above doesn't work, install Longhorn manually without hooks, then let ArgoCD adopt it:

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update

helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.11.1 \
  --set defaultSettings.defaultStorageClass=longhorn \
  --set persistence.defaultClassReplicaCount=1 \
  --set service.ui.type=ClusterIP \
  --set metrics.serviceMonitor.enabled=false \
  --no-hooks

# Then apply the ArgoCD Application
kubectl apply -f apps/longhorn/application.yaml
```

### After First Install

Once Longhorn is installed, **subsequent syncs work fine** because the hook runs against an existing installation. You can enable automated sync if desired:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

## Automated Testing

The `test-application.yaml` deploys automated storage tests that verify:
- PVC provisioning
- Volume mounting  
- Read/write operations
- Data persistence

Check test results:
```bash
kubectl logs -n longhorn-system job/longhorn-test-job
```

## Configuration

Current settings (defined in `application.yaml`):
- **Version**: 1.11.1 (compatible with K3s v1.33.10+k3s1)
- **Default StorageClass**: `longhorn`
- **Replica Count**: 1 (suitable for single-node homelab)
- **UI Type**: ClusterIP (access via port-forward)
- **Monitoring**: Disabled

## Accessing Longhorn UI

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

Then open: http://localhost:8080

## Verification

```bash
# Check Longhorn pods
kubectl get pods -n longhorn-system

# Check StorageClass
kubectl get storageclass longhorn

# Check test results
kubectl logs -n longhorn-system job/longhorn-test-job
```
