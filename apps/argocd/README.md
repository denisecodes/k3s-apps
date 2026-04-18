# ArgoCD Resources

This directory contains additional ArgoCD resources and configuration.

## IngressRoute

The `ingressroute.yaml` configures Traefik to route traffic to the ArgoCD UI.

## Accessing ArgoCD UI

### Via Traefik Ingress (Recommended)

Once DNS is configured (see issue #74), access ArgoCD at:

```
http://argocd.home.lan
```

**Prerequisites:**
- Traefik is running with LoadBalancer service
- dnsmasq is configured to resolve `*.home.lan` to Traefik LoadBalancer IP
- IngressRoute is deployed (included in `ingressroute.yaml`)

### Via Port-Forward (Fallback)

If DNS is not yet configured, use port-forwarding:

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

Then open: https://localhost:8080

**Note:** You'll need to accept the self-signed certificate warning in your browser.

### Via NodePort (Alternative)

ArgoCD is also exposed via NodePort on ports 30080 (HTTP) and 30443 (HTTPS):

```
http://<node-ip>:30080
https://<node-ip>:30443
```

## Default Credentials

Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Username:** `admin`

**Security Note:** Change the default password after first login and consider deleting the initial admin secret.

## Common Operations

### Check ArgoCD Status

```bash
# Check all ArgoCD pods
kubectl get pods -n argocd

# Check ArgoCD applications
kubectl get applications -n argocd

# Check specific application details
kubectl get application <app-name> -n argocd -o yaml
```

### Sync an Application

```bash
# Via kubectl (if argocd CLI not installed)
kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"}}}'

# Or access via UI and click "Sync"
```

### View Application Logs

```bash
# View ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server

# View application controller logs
kubectl logs -n argocd statefulset/argocd-application-controller
```

## Configuration

ArgoCD is managed via Ansible playbooks in the main `k3s-homelab` repository. See:
- Installation: `argocd/playbooks/argocd-setup.yml`
- Documentation: `docs/argocd.md`

## Application Structure

This repository uses the App of Apps pattern:
- `argocd-apps` is the parent application that manages all other applications
- Child applications: traefik, sealed-secrets, longhorn, longhorn-test
- All applications use automated sync with prune and selfHeal enabled

## Troubleshooting

### Application Won't Sync

1. Check application status:
   ```bash
   kubectl describe application <app-name> -n argocd
   ```

2. Look for sync errors in conditions:
   ```bash
   kubectl get application <app-name> -n argocd -o jsonpath='{.status.conditions}'
   ```

3. Check ArgoCD logs:
   ```bash
   kubectl logs -n argocd deployment/argocd-server -f
   ```

### SharedResourceWarning

If multiple applications try to manage the same resources, you'll see SharedResourceWarning. Solutions:
- Add `argocd.argoproj.io/instance: <app-name>` annotation to resources
- Use exclude patterns in parent application
- Ensure resources are only defined in one application

### Out of Sync Despite Auto-Sync

If an application shows OutOfSync despite having auto-sync enabled:
- Check if there are manual changes in the cluster that differ from Git
- Self-heal should revert these changes automatically
- If not, try manually syncing once to reset the state
