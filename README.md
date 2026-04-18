# k3s-apps

ArgoCD app-of-apps repository for the [k3s-homelab](https://github.com/denisecodes/k3s-homelab) cluster.

## Structure

```
apps/
├── sealed-secrets/
│   └── application.yaml        # Sealed Secrets controller
├── traefik/
│   ├── application.yaml        # Traefik ingress controller
│   ├── ingressroutes-application.yaml  # ArgoCD app for IngressRoutes
│   └── ingressroutes/          # All Traefik IngressRoute manifests
│       ├── argocd.yaml         # ArgoCD UI routing
│       ├── longhorn.yaml       # Longhorn UI routing
│       ├── traefik.yaml        # Traefik Dashboard routing
│       └── README.md           # IngressRoute documentation
├── longhorn/
│   ├── application.yaml        # Longhorn storage
│   ├── test-application.yaml   # Automated storage test
│   └── tests/
│       ├── test-pvc-pod.yaml   # Test Job + PVC
│       └── README.md           # Test documentation
└── argocd/
    └── README.md               # ArgoCD documentation
```

## How it works

ArgoCD watches this repo. Each Application manifest under `apps/` (organized by service in subdirectories) points to a Helm chart or plain manifests. When a change is pushed here, ArgoCD automatically syncs the cluster to match.

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
