# Traefik IngressRoutes

This directory contains all Traefik IngressRoute manifests for the cluster. IngressRoutes are managed by ArgoCD via the `traefik-ingressroutes` application and automatically deployed to their respective namespaces.

## Current Routes

| Route | Namespace | Service | URL |
|-------|-----------|---------|-----|
| `argocd.yaml` | `argocd` | argocd-server | http://argocd.denise.home |
| `longhorn.yaml` | `longhorn-system` | longhorn-frontend | http://longhorn.denise.home |
| `traefik.yaml` | `traefik` | api@internal | http://traefik.denise.home |

## Adding a New IngressRoute

1. **Create a new YAML file** in this directory (e.g., `my-app.yaml`):

```yaml
---
# Traefik IngressRoute for My App
# Access My App via: http://my-app.denise.home

apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  namespace: my-app  # Namespace where your app service lives
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  entryPoints:
    - web  # HTTP entry point (port 80)
  routes:
    - match: Host(`my-app.denise.home`)
      kind: Rule
      services:
        - name: my-app-service  # Your service name
          port: 80              # Your service port
```

2. **Commit and push** to Git:
```bash
git add apps/traefik/ingressroutes/my-app.yaml
git commit -m "Add IngressRoute for my-app"
git push
```

3. **Wait for ArgoCD** to sync (automatic within 3 minutes)

4. **Verify** the IngressRoute was created:
```bash
kubectl get ingressroute -n my-app
```

## HTTPS/TLS Routes

To add HTTPS with TLS certificates, use the `websecure` entrypoint:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app-https
  namespace: my-app
spec:
  entryPoints:
    - websecure  # HTTPS entry point (port 443)
  routes:
    - match: Host(`my-app.denise.home`)
      kind: Rule
      services:
        - name: my-app-service
          port: 80
  tls:
    secretName: my-app-tls  # K8s secret containing TLS cert
```

## Management

**Managed by ArgoCD**: All IngressRoutes in this directory are automatically deployed by the `traefik-ingressroutes` ArgoCD Application.

**Auto-sync enabled**: Changes pushed to Git are automatically applied to the cluster.

**Self-healing**: Manual changes to IngressRoutes in the cluster will be reverted to match Git.

## Troubleshooting

### IngressRoute not working

1. **Check IngressRoute exists**:
   ```bash
   kubectl get ingressroute -n <namespace>
   ```

2. **Check ArgoCD sync status**:
   ```bash
   kubectl get application traefik-ingressroutes -n argocd -o yaml
   ```

3. **Check Traefik logs**:
   ```bash
   kubectl logs -n traefik deployment/traefik
   ```

4. **Verify DNS resolution**:
   ```bash
   nslookup my-app.denise.home
   ```

5. **Check Traefik dashboard** for route status:
   ```
   http://traefik.denise.home
   ```

### Route conflicts

If multiple IngressRoutes match the same host, Traefik will use the first one it encounters. Ensure each IngressRoute has a unique host.

## References

- [Traefik IngressRoute Documentation](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/)
- [DNS Configuration](https://github.com/denisecodes/k3s-homelab/blob/main/docs/dns.md)
