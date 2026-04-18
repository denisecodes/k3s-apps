# k3s-apps

ArgoCD app-of-apps repository for the [k3s-homelab](https://github.com/denisecodes/k3s-homelab) cluster.

## Structure

```
apps/
├── argocd/
│   └── README.md               # ArgoCD documentation
├── longhorn/
│   ├── application.yaml        # Longhorn storage (multiple sources pattern)
│   ├── values.yaml             # Longhorn Helm chart overrides
│   ├── tests/                  # Manual storage tests
│   │   ├── job.yaml            # Test Job
│   │   ├── pvc.yaml            # Test PVC
│   │   └── README.md           # Test documentation
│   └── README.md               # Longhorn documentation
├── nextcloud/
│   ├── application.yaml        # Nextcloud (multiple sources pattern)
│   ├── values.yaml             # Nextcloud Helm chart overrides
│   ├── sealed-secret.yaml      # Encrypted credentials
│   └── README.md               # Nextcloud documentation
├── sealed-secrets/
│   ├── application.yaml        # Sealed Secrets controller
│   └── README.md               # Sealed Secrets guide
└── traefik/
    ├── application.yaml        # Traefik ingress controller
    ├── ingressroutes-application.yaml  # ArgoCD app for IngressRoutes
    ├── ingressroutes/          # All Traefik IngressRoute manifests
    │   ├── argocd.yaml         # ArgoCD UI routing
    │   ├── longhorn.yaml       # Longhorn UI routing
    │   ├── nextcloud.yaml      # Nextcloud routing
    │   ├── traefik.yaml        # Traefik Dashboard routing
    │   └── README.md           # IngressRoute documentation
    └── README.md               # Traefik documentation
```

## How it works

ArgoCD watches this repo. Each Application manifest under `apps/` (organized by service in subdirectories) points to a Helm chart or plain manifests. When a change is pushed here, ArgoCD automatically syncs the cluster to match.

### ArgoCD Multiple Sources Pattern

Applications using **remote Helm charts** (like Longhorn and Nextcloud) use ArgoCD's multiple sources pattern to combine the official Helm chart with Git-based configuration:

```yaml
spec:
  sources:
    # Source 1: Official Helm chart repository
    - repoURL: https://charts.example.io
      chart: my-chart
      targetRevision: 1.0.0
      helm:
        valueFiles:
          - $values/apps/my-app/values.yaml
    # Source 2: This Git repository for values.yaml
    - repoURL: https://github.com/denisecodes/k3s-apps
      targetRevision: main
      ref: values
```

**Benefits:**
- Use official remote Helm charts (always up-to-date)
- Keep configuration in Git (version control, GitOps)
- Easy to customize without modifying Application manifests
- Clear separation between chart source and configuration

See `apps/longhorn/` and `apps/nextcloud/` for examples.

### App-of-Apps Directory Exclusions

The `argocd-apps` Application (App of Apps) recursively scans the `apps/` directory but **excludes** certain patterns to prevent resource conflicts and unwanted deployments:

```yaml
directory:
  recurse: true
  exclude: "{**/ingressroutes/**,**/tests/**}"
```

**Excluded directories:**
- `**/ingressroutes/**` - Managed by dedicated `traefik-ingressroutes` Application
- `**/tests/**` - Manual test resources (not for automatic deployment)

This ensures:
- No `SharedResourceWarning` errors from multiple Applications managing the same resources
- Test resources are only deployed on-demand for verification
- Clear ownership boundaries between Applications

See the [k3s-homelab ArgoCD documentation](https://github.com/denisecodes/k3s-homelab/blob/main/docs/argocd.md#directory-exclusions-and-why-theyre-needed) for more details.

## Adding an app

1. Create a new directory under `apps/` for your service:
   ```bash
   mkdir apps/my-app
   ```

2. Create an `Application` manifest in that directory:
   ```yaml
   # apps/my-app/application.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: my-app
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: https://github.com/denisecodes/k3s-apps
       targetRevision: HEAD
       path: charts/my-app
     destination:
       server: https://kubernetes.default.svc
       namespace: my-app
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
   ```

3. Commit and push — ArgoCD will pick it up automatically.

## Sealed Secrets

The Sealed Secrets controller is installed via ArgoCD and runs in the `kube-system` namespace. It encrypts secrets so they can be safely stored in Git.

For detailed instructions on using Sealed Secrets, see the [Sealed Secrets Guide](apps/sealed-secrets/README.md).

### Backup the controller private key

**CRITICAL:** After the Sealed Secrets controller is deployed, immediately back up the controller's private key. If this key is lost, all existing SealedSecrets become unrecoverable.

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml
```

Store this file in a secure location (e.g., password manager, encrypted backup). **Never commit this file to Git.**

### Restoring the key

If you need to restore the controller key (e.g., after a cluster rebuild):

```bash
kubectl apply -f sealed-secrets-key-backup.yaml
kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets
```
