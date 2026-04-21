# Beets Music Tagger

Runs [beets](https://beets.io/) as a one-shot Kubernetes Job to auto-tag music stored on the `jellyfin-media-music` PVC. It fetches metadata, album art, and genres from MusicBrainz/Last.fm and writes tags directly to the files in place — no files are moved or copied.

## How it works

- **ConfigMap** (`configmap.yaml`) — beets config with plugins: `fetchart`, `embedart`, `lastgenre`
- **Job** (`job.yaml`) — mounts the music PVC read-write alongside the config, runs `beet import -q /media/music`, then exits
- **ArgoCD Application** (`application.yaml`) — manually synced; `Replace: true` forces the Job to be deleted and recreated on every sync so it actually re-runs
- The Job has `ttlSecondsAfterFinished: 3600`, so the pod is automatically cleaned up 1 hour after completion

## First-time setup

Apply the ArgoCD Application to register it (one time only):

```bash
kubectl apply -f apps/beets/application.yaml
```

## Running the tagger

Every time you want to re-tag your music library:

**1. Sync the app** — this deletes any previous Job and creates a fresh one:

```bash
argocd app sync beets-tagger
```

**2. Watch live logs:**

```bash
kubectl logs -n jellyfin job/beets-tagger-job -f
```

**3. Check the import log for what was tagged, skipped, or failed:**

```bash
kubectl exec -n jellyfin job/beets-tagger-job -- cat /config/import.log
```

The Job cleans itself up automatically after 1 hour. You can also delete it manually:

```bash
kubectl delete job -n jellyfin beets-tagger-job
```

## ReadWriteOnce caveat

The `jellyfin-media-music` PVC uses `ReadWriteOnce` (Longhorn). This means it can only be mounted on one node at a time. If the beets Job schedules on a different node than the Jellyfin pod, it will fail to mount the PVC and stay in `Pending`.

To avoid this, scale Jellyfin down before syncing, then back up after:

```bash
kubectl scale deploy -n jellyfin jellyfin --replicas=0
argocd app sync beets-tagger
kubectl logs -n jellyfin job/beets-tagger-job -f
kubectl scale deploy -n jellyfin jellyfin --replicas=1
```

## Modifying beets config

Edit `configmap.yaml` in this directory, commit and push, then re-sync:

```bash
argocd app sync beets-tagger
```

ArgoCD will update the ConfigMap and recreate the Job with the new config.
