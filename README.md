# pnpr on Cloudflare Containers

Example repository for running [`pnpr`](https://pnpm.io/pnpr/), the pnpm-compatible npm registry server, on Cloudflare Containers.

This sample uses:

- Cloudflare Workers as the public edge entrypoint.
- Cloudflare Containers running the official `ghcr.io/pnpm/pnpr` image.
- Cloudflare R2 through pnpr's S3-compatible storage backend for durable hosted package data.
- A single named container instance by default, with user/auth support disabled in the deployable config.

## Architecture

```text
pnpm/npm/yarn client
  -> Cloudflare Worker
  -> Durable Object-backed Container instance
  -> pnpr on port 7677
  -> R2 for hosted packages
  -> npmjs/private upstreams for proxied packages
```

The container filesystem is scratch. This sample does not configure a durable volume. Durable hosted package data belongs in R2. Local paths in `pnpr.yaml` are only for cache and upload staging.

Cloudflare Containers are managed through Durable Objects, but that does not automatically mount Durable Object storage into the Linux filesystem. A file such as `/pnpr/storage/tokens.db` would live on container-local disk. It is not shared across instances and should not be treated as a backup target.

## Files

- `src/index.ts` routes every request to the named pnpr container instance.
- `Dockerfile` pins the official pnpr image and starts it with `--public-url` from runtime env.
- `pnpr.yaml` is the default deployable pnpr config.
- `wrangler.jsonc` configures the Worker, Container, Durable Object migration, vars, and required secrets.
- `.dev.vars.example` documents local development values.
- `examples/pnpr.libsql.yaml` shows shared auth for multiple replicas.
- `examples/pnpr.private-upstream.yaml` shows private upstream routing.

## Required Cloudflare Setup

1. Create the R2 buckets:

```bash
# Production bucket used by wrangler.jsonc.
npx wrangler r2 bucket create pnpr-packages

# Optional local/dev bucket if you use .dev.vars.example as-is.
npx wrangler r2 bucket create pnpr-packages-dev

# Confirm the buckets exist.
npx wrangler r2 bucket list
npx wrangler r2 bucket info pnpr-packages
```

Use `pnpr-packages` as `PNPR_R2_BUCKET`. Use `pnpr-packages-dev` as `PNPR_R2_BUCKET` in `.dev.vars` if you want local development to write to a separate bucket.

2. Create an R2 API token with object read/write access to the bucket.

3. Set required Worker secrets.

If you already created these in the Cloudflare dashboard under the Worker environment variables/secrets UI, you do not need to run `wrangler secret put` again. To create them from the CLI:

```bash
npx wrangler secret put PNPR_PUBLIC_URL
npx wrangler secret put PNPR_SECRET
npx wrangler secret put PNPR_R2_ACCOUNT_ID
npx wrangler secret put PNPR_R2_BUCKET
npx wrangler secret put PNPR_R2_ACCESS_KEY_ID
npx wrangler secret put PNPR_R2_SECRET_ACCESS_KEY
```

Verify the secret names exist:

```bash
npx wrangler secret list
```

Suggested values:

```text
PNPR_PUBLIC_URL=https://pnpr.clickmax.co
PNPR_R2_ACCOUNT_ID=<cloudflare-account-id>
PNPR_R2_BUCKET=pnpr-packages
```

R2 object prefixes are hardcoded by this sample: hosted packages use `packages/`, and proxied upstream cache uses `cache/`.

Use a stable `PNPR_SECRET` of at least 16 bytes. Changing it invalidates private cache namespaces.

## Deploy

Docker must be running locally because Wrangler builds and pushes the container image during deploy.

The Dockerfile pins `PNPR_VERSION` to an exact pnpr image tag. Do not use `ghcr.io/pnpm/pnpr:latest` until pnpr has a stable release: pnpm's Docker docs say `latest` is not updated for prereleases.

Wrangler builds the image for Cloudflare Containers during `wrangler deploy`. If you build manually, target `linux/amd64` because that is what Cloudflare Containers run:

```bash
docker buildx build --platform linux/amd64 -t pnpr-cloudflare-containers .
```

```bash
pnpm install
pnpm run cf-typegen
pnpm run deploy
```

After first deploy, Containers can take a few minutes to become ready.

Check status:

```bash
npx wrangler containers list
npx wrangler containers images list
```

Health check:

```bash
curl https://pnpr-cloudflare-containers.<your-workers-subdomain>.workers.dev/-/ping
```

## Use As Registry

Point pnpm at the Worker URL:

```bash
pnpm config set registry https://pnpr-cloudflare-containers.<your-workers-subdomain>.workers.dev/
```

Use it as a public npm proxy/resolver:

```bash
pnpm add react
```

By default, this sample proxies `https://registry.npmjs.org/` through pnpr and keeps the pnpr resolver enabled. Private hosted scopes are commented in `pnpr.yaml` so you can add them back deliberately.

## Environment Reference

These values are consumed by `pnpr.yaml` through pnpr's `${ENV_VAR}` substitution.

| Name                        | Required                              | Secret | Purpose                                                                         |
| --------------------------- | ------------------------------------- | ------ | ------------------------------------------------------------------------------- |
| `PNPR_PUBLIC_URL`           | yes                                   | yes    | Public Worker URL used to rewrite tarball URLs. Must match the URL clients use. |
| `PNPR_SECRET`               | yes                                   | yes    | HMAC key for private cache namespaces. Keep stable across deploys.              |
| `PNPR_R2_ACCOUNT_ID`        | yes                                   | yes    | Cloudflare account ID used in the R2 S3 endpoint.                               |
| `PNPR_R2_BUCKET`            | yes                                   | yes    | R2 bucket for hosted package data and upstream cache.                           |
| `PNPR_R2_ACCESS_KEY_ID`     | yes                                   | yes    | R2 S3 access key ID.                                                            |
| `PNPR_R2_SECRET_ACCESS_KEY` | yes                                   | yes    | R2 S3 secret access key.                                                        |
| `PNPR_LIBSQL_URL`           | only with `examples/pnpr.libsql.yaml` | yes    | Shared libsql/Turso auth database URL.                                          |
| `PNPR_LIBSQL_TOKEN`         | only with `examples/pnpr.libsql.yaml` | yes    | Shared libsql/Turso auth token.                                                 |
| `PNPR_CORP_REGISTRY_URL`    | only with private upstream example    | no     | Private upstream npm registry URL.                                              |
| `PNPR_CORP_NPM_TOKEN`       | only with private upstream example    | yes    | Server-owned bearer token for the private upstream.                             |
| `RUST_LOG`                  | no                                    | no     | Overrides `log.level`; useful values: `info`, `debug`, `pnpr=debug`.            |

## pnpr Config Notes

### Storage

`pnpr.yaml` sets both local paths and an `s3:` block:

```yaml
storage: /pnpr/storage
cache: /mnt/r2/cache
s3:
  bucket: ${PNPR_R2_BUCKET}
  region: auto
  endpoint: https://${PNPR_R2_ACCOUNT_ID}.r2.cloudflarestorage.com
  prefix: packages
```

With `s3:` enabled, hosted packages live in R2 under `packages/`. Proxied upstream packages from npmjs are cached through an R2 FUSE mount under `cache/`.

That means a request such as `GET /typescript` resolves through the `npmjs` upstream, then pnpr writes its upstream cache files under the R2 `cache/` prefix. This uses filesystem semantics through FUSE, so expect object-storage latency rather than local SSD speed.

### Registry Routing

The default registry is a router:

```yaml
registries:
  npmjs:
    type: upstream
    url: https://registry.npmjs.org/
    public: true
  main:
    type: router
    sources: [npmjs]
defaultRegistry: main
```

To add a private hosted scope, uncomment the `local` hosted registry recipe in `pnpr.yaml`, change `@mycompany/*` to your scope, and update `main.sources` to `[local, npmjs]`. pnpr does not infer provenance: a package resolves to the first concrete registry whose `packages:` map claims it. A private scope will not fall through to npmjs, which is the dependency-confusion protection.

### Auth And Users

User support is commented out in the default config. For the public npmjs proxy/resolver use case, no users or tokens are needed.

Do not use local htpasswd plus SQLite token DB for production Cloudflare Containers unless you explicitly accept single-instance ephemeral auth state:

```yaml
# auth:
#   htpasswd:
#     file: /pnpr/storage/htpasswd
#     max_users: -1
#   tokens:
#     file: /pnpr/storage/tokens.db
```

Those files would be on container-local disk. They are not shared across replicas, and backing up `tokens.db` from a running container is not a reliable operational model. If you need users, login, publish tokens, or multiple replicas, use a shared auth backend such as libsql/Turso. See `examples/pnpr.libsql.yaml`.

### Resolver

The pnpr install accelerator is enabled:

```yaml
resolver:
  enabled: true
```

The registry surface and resolver surface can be run together, registry-only, or resolver-only in pnpr, but this sample exposes both.

## Scaling Notes

The default uses one named container instance:

```ts
getContainer(c.env.PNPR_CONTAINER, 'registry');
```

Do not simply increase `max_instances` for write-heavy production usage without understanding pnpr's current concurrency model. The pnpr source currently serializes package writes within one process, but its own comment notes that cross-replica writes sharing one hosted store need conditional object writes to prevent lost updates. R2 gives durable data, not cross-process packument write serialization.

If you need more read capacity, safer options are:

1. Keep one writer registry and add resolver-only/read-only tiers separately.
2. Use shared SQL auth and multiple replicas only after validating publish/unpublish concurrency for your workload.
3. Put Cloudflare cache in front of packument/tarball reads where appropriate.

## Rust Worker Feasibility

pnpr is written in Rust, but it is not currently a Cloudflare Rust Worker.

Cloudflare Rust Workers compile to `wasm32-unknown-unknown` and run through `workers-rs`. pnpr currently uses an Axum/Tokio server, binds a TCP listener, uses `reqwest`, local filesystem storage/cache/journals, htpasswd + SQLite auth, blocking bcrypt/file work, and native process assumptions. Those are correct for a container, but not compatible with Workers Wasm as-is.

A true Rust Worker port would be a separate project:

- Replace `axum::serve`/TCP listener with a `workers-rs` fetch handler.
- Replace local filesystem cache and journals with R2, Durable Object storage, KV, D1, or no persistent cache.
- Replace `reqwest`/native networking with Worker `fetch` bindings or a Wasm-compatible HTTP client.
- Replace local SQLite/htpasswd auth with D1, KV, Durable Object storage, or remote SQL over Workers-supported APIs.
- Audit every dependency for `wasm32-unknown-unknown` support and bundle size/startup cost.

So the practical deployment path today is Cloudflare Containers. A Rust Worker port is possible only as a non-trivial upstream refactor or new adapter layer.

## Local Development

Copy `.dev.vars.example` to `.dev.vars` and fill values. Do not commit `.dev.vars`.

```bash
pnpm run dev
```

Local development still needs Docker for the container. If you want to use real R2 from local development, use real R2 S3 credentials in `.dev.vars`.

## References

- pnpr Docker image: <https://github.com/pnpm/pnpm/tree/main/pnpr/docker>
- pnpr configuration: <https://pnpm.io/pnpr/configuration>
- pnpr storage backends: <https://pnpm.io/pnpr/storage>
- pnpr auth backends: <https://pnpm.io/pnpr/auth-backends>
- Cloudflare Containers: <https://developers.cloudflare.com/containers/get-started/>
- Cloudflare Rust Workers: <https://developers.cloudflare.com/workers/languages/rust/>
