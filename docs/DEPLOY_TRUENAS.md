# TrueNAS deployment with GitHub Container Registry

For TrueNAS SCALE 24.10+ on amd64, install all three services as one custom YAML app. The Phoenix app and renderer come from GHCR; PostgreSQL uses its official image. No source checkout or build tools are needed on TrueNAS.

## Publish the images

Commit and push `.github/workflows/publish-images.yml` together with the application source to `main`. GitHub Actions runs **Publish container images**, using the repository's `GITHUB_TOKEN` with package write permission. Wait for both matrix jobs to finish successfully.

The workflow publishes:

- `ghcr.io/iskandiar/trmnl-creator-elixir:latest`
- `ghcr.io/iskandiar/trmnl-creator-elixir-renderer:latest`

Both also receive `sha-<full commit SHA>` tags. Pushing a Git tag such as `v0.1.0` publishes that exact tag for both images. `latest` follows the default branch; use a matching SHA or version tag for a repeatable deployment. Forks publish under their own repository name and must adjust the Compose image names.

New GHCR packages are private by default. For unauthenticated pulls, open each package's **Package settings → Change visibility → Public**, if you intend to distribute the images publicly. Otherwise configure GHCR registry credentials in TrueNAS with a GitHub personal access token (classic) that has `read:packages` and access to both packages. Repository visibility alone does not make packages public.

## Prepare your installation on your computer

Create the Generic/POSIX dataset `storage/apps/trmnl-db` in TrueNAS. The supplied configuration mounts `/mnt/storage/apps/trmnl-db` at PostgreSQL's `/var/lib/postgresql/data` and refuses to silently create a missing host directory. Keep the PostgreSQL container's default user/entrypoint so it can initialize ownership on this fresh dataset. Do not add an overriding `user:` setting.

From your local repository checkout (with Python 3 and Docker Compose installed):

```sh
python3 scripts/generate_env.py
```

Run this only for a fresh installation. If `.env` already exists, reuse it. Set `PUBLIC_URL` in `.env` to the TrueNAS address, for example `http://192.168.1.50:4000`. Google credentials can remain empty for initial setup. The Compose template uses `latest` and `pull_policy: always` for both GHCR images. For a pinned deployment, edit both image tags in the YAML to the same published version or `sha-<full commit SHA>`.

Validate and render a self-contained configuration:

```sh
python3 scripts/preflight.py .env
mkdir -p .tmp
umask 077
docker compose --env-file .env -f compose.truenas.yaml config > .tmp/truenas.yaml
```

This resolves the environment variables locally; it does not start containers. The rendered file contains your secrets. Keep it private, together with `.env`, and do not commit it. Both locations are gitignored. Preserve `TOKEN_ENCRYPTION_KEY` with database backups: changing it makes saved Google credentials unreadable.

## Install in TrueNAS

1. Open **Apps → Discover Apps → ⋮ → Install via YAML**.
2. Name the app `trmnl` and paste the contents of `.tmp/truenas.yaml`.
3. Install and wait for all services to become healthy.
4. Open `PUBLIC_URL` and log in with the generated `ADMIN_PASSWORD` from `.env`.

Only port 4000 is exposed. The database and renderer communicate over the internal Compose network. Keep the generated health checks and dependencies. The app image's default command runs pending Ecto migrations before starting Phoenix; a migration failure prevents startup. Do not override that command in TrueNAS.

If installation fails, inspect the app and database container logs in TrueNAS. Permission errors on the database mount need to be resolved on the dedicated dataset before PostgreSQL can initialize. A registry authorization error means the packages are private or the configured credentials lack access.

## Update without losing data

1. Back up the database before upgrading. From the database container shell, `pg_dump -U trmnl -d trmnl -Fc -f /var/lib/postgresql/data/pre-update.dump` creates a dump in the mounted dataset. Copy that file to a separate backup location before continuing; a file on the same dataset is not an independent backup.
2. Publish the next release and wait for both image builds to succeed.
3. In the existing TrueNAS app, use the update/pull-latest-image action, or redeploy the app. Both GHCR services use `latest` with `pull_policy: always`, so Compose pulls them when deploying.
4. Check health and migration logs.

The pull policy does not poll GitHub or trigger a deployment when a commit arrives. Fully unattended updates require a separate deployment trigger.

Keep the database mount, database credentials, encryption key and other secrets unchanged. PostgreSQL reuses its existing data; Ecto applies only pending migrations. Updates do not run seeds or reset the database. A migration can still intentionally change or remove data, so review release changes and retain backups. Reverting an image does not undo schema migrations.

Keep `postgres:17-bookworm` during app updates. A PostgreSQL major-version upgrade requires a separate database upgrade procedure.

References: [GitHub image publishing](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images), [GHCR access and visibility](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry), [TrueNAS custom apps](https://apps.truenas.com/managing-apps/installing-custom-apps/).
