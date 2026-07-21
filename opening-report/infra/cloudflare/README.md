# scidb-beta Cloudflare Deployment

This configuration deploys scidb-beta on Cloudflare's edge platform:

| Component | Service | Purpose |
|-----------|---------|---------|
| SPA | Cloudflare Pages | Static React app served from edge |
| API routing/auth | Workers | Request routing, auth, signed URL generation |
| WebSocket sessions | Durable Objects | Per-workspace state, WebSocket connections |
| Database files | R2 | S3-compatible object storage for imports/exports |
| Background jobs | Queues | Job dispatch for imports, reports, maintenance |

## Architecture

```
Browser
  │
  ├── Cloudflare Pages (SPA)
  │
  └── Cloudflare Worker (API routing, auth)
        │
        ├── Durable Objects (workspace sessions, WebSocket)
        │
        ├── R2 (database files, export artifacts)
        │
        ├── Queues (background job dispatch)
        │
        └── Container Host (scidb runtime + Stockfish)
              └── Cloud Run / Fly.io / ECS / dedicated VM
```

> **Important:** Cloudflare Workers should NOT execute the C++/Tcl scidb
> runtime or Stockfish directly. The runtime runs on a container host
> (Cloud Run, Fly.io, ECS, or a dedicated VM). Workers proxy requests to the
> container host and handle auth, routing, and edge-level concerns.

## Prerequisites

1. **Cloudflare account** with Workers, Pages, R2, and Queues enabled.
2. **Wrangler CLI** installed: `npm install -g wrangler`
3. **Container host** running the `runtime_adapter.py` (or native scidb runtime).
4. Authenticated wrangler: `wrangler login`

## Deploy steps

### 1. Deploy the SPA to Cloudflare Pages

```bash
cd ../../  # back to opening-report/
npm run build
npx wrangler pages deploy dist --project-name scidb-beta
```

Or create the project first:

```bash
npx wrangler pages project create scidb-beta --production-branch main
npx wrangler pages deploy dist --project-name scidb-beta
```

### 2. Create R2 bucket

```bash
npx wrangler r2 bucket create scidb-beta-artifacts
```

### 3. Create Queues

```bash
npx wrangler queues create scidb-beta-jobs
npx wrangler queues create scidb-beta-jobs-dlq
```

### 4. Deploy the Worker

Write your `worker.js` entry point (API routing, auth, Durable Object bindings)
and deploy:

```bash
cd infra/cloudflare
npx wrangler deploy
```

### 5. Configure the container host

Set `SCIDB_RUNTIME_HOST` in `wrangler.toml` to the URL of your container host
running the runtime adapter. The Worker proxies API requests that require the
scidb runtime to this host.

```toml
[vars]
SCIDB_RUNTIME_HOST = "https://your-container-host.example.com"
```

## Durable Objects

The `WorkspaceSession` Durable Object manages:

- Per-workspace WebSocket connections
- Short-lived workspace state (active database, current FEN, panel)
- Analysis session coordination

Each workspace gets its own Durable Object instance, providing isolated state
and WebSocket handling at the edge.

## R2 vs S3

R2 is S3-compatible. The `runtime_adapter.py` can use R2 by setting:

```bash
S3_BUCKET=scidb-beta-artifacts
S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
S3_KEY=<r2-access-key>
S3_SECRET=<r2-secret-key>
```

## Queues

Background jobs (imports, reports, maintenance, exports) are dispatched via
Cloudflare Queues. The Worker enqueues jobs; a consumer Worker (or the
container host) processes them.

## Cleanup

```bash
npx wrangler delete
npx wrangler r2 bucket delete scidb-beta-artifacts
npx wrangler queues delete scidb-beta-jobs
npx wrangler pages project delete scidb-beta
```