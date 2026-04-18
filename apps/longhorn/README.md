# Longhorn Deployment

Longhorn provides persistent storage for the K3s cluster via ArgoCD.

## Files

- **`application.yaml`**: ArgoCD Application manifest using multiple sources pattern
- **`values.yaml`**: Helm chart configuration overrides (stored in Git)
- **`tests/application.yaml`**: ArgoCD Application manifest for automated storage tests
- **`tests/`**: Test resources and scripts

## Installation

The Longhorn application uses ArgoCD's **multiple sources pattern** to combine the official Helm chart with Git-based configuration:

1. **Helm chart source**: Official Longhorn repository (`https://charts.longhorn.io`)
2. **Values source**: This Git repository (`apps/longhorn/values.yaml`)

This pattern allows us to:
- Use the official remote Helm chart (always up-to-date)
- Keep configuration in Git (version control, GitOps)
- Easily customize settings without modifying the Application manifest

**Note**: Automated sync is **enabled** in `application.yaml` with prune and selfHeal, so Longhorn will automatically stay in sync with Git changes.

### First-Time Installation Notes

⚠️ **If you're setting up on a new cluster**: The automated sync is already enabled. If you encounter any sync issues during first install, you can temporarily disable auto-sync by commenting out the `automated:` section in `application.yaml`, perform the initial sync manually, then re-enable auto-sync.

However, with `preUpgradeChecker.jobEnabled: false`, fresh installations should work smoothly without issues.

## Automated Testing

The `tests/application.yaml` manifest deploys automated storage tests that verify:
- PVC provisioning
- Volume mounting  
- Read/write operations
- Data persistence

To deploy the test application:
```bash
kubectl apply -f apps/longhorn/tests/application.yaml
```

Check test results:
```bash
kubectl logs -n longhorn-system job/longhorn-test-job
```

## Configuration

Configuration is managed in `values.yaml` with the following settings:

- **Version**: 1.11.1 (compatible with K3s v1.33.10+k3s1)
- **Pre-upgrade Checker**: Disabled (recommended for GitOps deployments)
- **Default StorageClass**: `longhorn`
- **Replica Count**: 1 (suitable for single-node homelab, increase for production)
- **UI Type**: ClusterIP (access via Traefik IngressRoute)
- **Monitoring**: Disabled (can be enabled when Prometheus is deployed)

### Customizing Configuration

To modify Longhorn settings:

1. Edit `apps/longhorn/values.yaml`
2. Commit and push changes
3. ArgoCD will automatically detect and apply the changes

**Example**: To increase replica count for production:

```yaml
persistence:
  defaultClassReplicaCount: 3  # Change from 1 to 3
```

For all available configuration options, see the [Longhorn Helm Chart documentation](https://github.com/longhorn/charts).

## Accessing Longhorn UI

### Via Traefik Ingress (Recommended)

Once DNS is configured, access Longhorn at:

```
http://longhorn.denise.home
```

**Prerequisites:**
- Traefik is running with LoadBalancer service
- dnsmasq is configured to resolve `*.denise.home` to Traefik LoadBalancer IP
  - See [k3s-homelab/docs/dns.md](https://github.com/denisecodes/k3s-homelab/blob/main/docs/dns.md) for setup instructions
- IngressRoute is deployed (managed by ArgoCD via `apps/traefik/ingressroutes/longhorn.yaml`)

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
