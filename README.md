# k3s-apps

ArgoCD app-of-apps repository for the [k3s-homelab](https://github.com/denisecodes/k3s-homelab) cluster.

## Structure

```
apps/           # ArgoCD Application manifests (one per service)
charts/         # Helm charts (optional, for custom apps)
```

## How it works

ArgoCD watches this repo. Each file under `apps/` is an ArgoCD `Application` manifest that points to a Helm chart or plain manifests. When a change is pushed here, ArgoCD automatically syncs the cluster to match.

## Adding an app

1. Create a new `Application` manifest under `apps/`:
   ```yaml
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
2. Commit and push — ArgoCD will pick it up automatically.
