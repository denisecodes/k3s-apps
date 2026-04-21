# Beets Music Tagger

Runs [beets](https://beets.io/) as a one-shot Kubernetes Job to auto-tag music stored on the `jellyfin-media-music` PVC. It fetches metadata, album art, and genres from MusicBrainz/Last.fm and writes tags directly to the files in place — no files are moved or copied.

## How it works

- **ConfigMap** (`configmap.yaml`) — beets config with plugins: `fetchart`, `embedart`, `lastgenre`
- **Job** (`job.yaml`) — mounts the music PVC read-write alongside the config, runs `beet import /media/music`, then prints the full import log before exiting
- **ArgoCD Application** (`application.yaml`) — manually synced; the Job has an ArgoCD `Sync` hook with `BeforeHookCreation` delete policy, so every sync deletes the old Job and creates a fresh one
- The Job has `ttlSecondsAfterFinished: 3600`, so the pod is automatically cleaned up 1 hour after completion

## First-time setup

The `beets-tagger` Application is already registered in the cluster as part of the app-of-apps. No `kubectl apply` needed — it will appear in ArgoCD automatically once the branch is merged to main.

## Running the tagger

Every time you want to tag your music library:

**1. If you've made config changes** — commit and push, then in ArgoCD hit **Refresh** on the `beets-tagger` app to pull in the latest manifests.

**2. Sync the app** — in the ArgoCD UI, click **Sync** on `beets-tagger` with the **Replace** and **Retry** options enabled. This deletes any previous Job and creates a fresh one which runs immediately.

Alternatively via CLI:

```bash
argocd app sync beets-tagger --replace --retry-limit 2
```

**3. Watch the logs:**

```bash
kubectl logs -n jellyfin job/beets-tagger-job -f
```

The full import log is printed at the end of the output. `kubectl logs` works on completed pods, so you can always retrieve it after the job finishes.

The Job cleans itself up automatically after 1 hour. You can also delete it manually:

```bash
kubectl delete job -n jellyfin beets-tagger-job
```

## ReadWriteOnce caveat

The `jellyfin-media-music` PVC uses `ReadWriteOnce` (Longhorn). This means it can only be mounted on one node at a time. If the beets Job schedules on a different node than the Jellyfin pod, it will fail to mount the PVC and stay in `Pending`.

To avoid this, scale Jellyfin down before syncing, then back up after:

```bash
kubectl scale deploy -n jellyfin jellyfin --replicas=0
argocd app sync beets-tagger --replace --retry-limit 2
kubectl logs -n jellyfin job/beets-tagger-job -f
kubectl scale deploy -n jellyfin jellyfin --replicas=1
```

## Modifying beets config

Edit `configmap.yaml`, commit and push, then follow the **Running the tagger** steps above.

