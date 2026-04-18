# Longhorn Deployment

Longhorn provides persistent storage for the K3s cluster via ArgoCD.

## Installation

The Longhorn application is configured with `preUpgradeChecker.jobEnabled: false` to avoid the pre-upgrade hook issue that affects fresh installations. This allows ArgoCD to install Longhorn smoothly without manual intervention.

**Note**: Automated sync is **enabled** in `application.yaml` with prune and selfHeal, so Longhorn will automatically stay in sync with Git changes.

### First-Time Installation Notes

⚠️ **If you're setting up on a new cluster**: The automated sync is already enabled. If you encounter any sync issues during first install, you can temporarily disable auto-sync by commenting out the `automated:` section in `application.yaml`, perform the initial sync manually, then re-enable auto-sync.

However, with `preUpgradeChecker.jobEnabled: false`, fresh installations should work smoothly without issues.

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

### Via Traefik Ingress (Recommended)

Once DNS is configured, access Longhorn at:

```
http://longhorn.home.lan
```

**Prerequisites:**
- Traefik is running with LoadBalancer service
- dnsmasq is configured to resolve `*.home.lan` to Traefik LoadBalancer IP
  - See [k3s-homelab/docs/dns.md](https://github.com/denisecodes/k3s-homelab/blob/main/docs/dns.md) for setup instructions
- IngressRoute is deployed (included in `ingressroute.yaml`)

### Via Port-Forward (Fallback)

If DNS is not yet configured, use port-forwarding:

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
