# Acceptance validation — 2026-09-23

Implementation and automated integration were validated locally. The deployed validation stack is **linux/amd64**, running through an isolated Colima/Rosetta VM on an Apple Silicon Mac. This is not a deployment to the user's home server and does not establish compatibility with an unobserved physical device.

## Results

| Criterion | Observed evidence | Result |
| --- | --- | --- |
| 1. Startup and persistence | Fresh Compose project/volume migrated and all three services became healthy. Browser login required; wrong passwords and unauthenticated dashboard requests rejected. Stop/start of app, PostgreSQL and renderer retained the draft, publication bytes and paired device token. | Passed in validation deployment |
| 2. Multiple Google calendars | Two deterministic account fixtures; OAuth state success/rejection/single-use; actual Req-based adapter pagination; expanded recurring exception and cancelled-instance fixtures; exclusive all-day end; Warsaw spring/fall DST and midnight boundaries. A later-page HTTP 503 preserved the complete prior snapshot. Recovered sync clears the error. | Passed with fixtures; real consent pending |
| 3. Usable editor and images | Chromium browser adds/configures/moves/resizes/removes blocks, rejects overlaps/out-of-bounds geometry, saves/reopens layout, and renders a preview. Actual one-bit 800×480 PNGs inspected visually, including Polish characters, seven day columns and explicit overflow indicators. | Passed automated and visual checks |
| 4. Publication isolation | Draft changes leave device filename/image unchanged. Revision checks prevent stale saves/publication. Render failure retains both previous configuration and image. Calendar content refresh uses the published layout. Production browser test stops renderer, observes failure, restores renderer and publishes successfully. | Passed |
| 5. BYOS API | Simulated MAC pairs during approved window, gets token and BMP onboarding image, requests display, downloads PNG, submits logs and battery/RSSI headers. Invalid/expired pairing, invalid token and invalid image signature rejected. Before publication setup image is returned. Last successful publication survives renderer failure and service restart. | Passed simulated contract |
| 6. Diagnostics and recovery | ExUnit verifies retained caches and actionable sync/render errors. Browser observes render error and recovers via Publish; battery/Wi-Fi data appears on dashboard. Arbitrary firmware payload strings are excluded from persisted diagnostics; all Phoenix request parameters filtered. | Passed |

## Commands and observed totals

```sh
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
RENDERER_TEST=1 mix test
# 20 tests, 0 failures (includes real Chromium/ImageMagick integration)
npm run build
npm audit --omit=dev
npm --prefix renderer audit --omit=dev
# Both npm audit checks: 0 vulnerabilities

docker --context colima-trmnl-validation compose   --env-file .tmp/compose.env -p trmnl-validation up --build -d --wait
# app, db and renderer healthy; app and renderer images inspected as amd64

BASE_URL=http://localhost:4011 ADMIN_PASSWORD=validation-password-only DEPLOYMENT_TEST=1 DOCKER_TEST_CONTEXT=colima-trmnl-validation COMPOSE_TEST_ENV=.tmp/compose.env COMPOSE_TEST_PROJECT=trmnl-validation npm run test:browser
# 2 browser tests passed, including failure/recovery and complete stack restart
```

The browser password above belongs only to the disposable validation deployment. Its generated database, encryption, signing and renderer secrets are in ignored `.tmp/compose.env`. Do not use these example credentials for deployment.

The initial local ExUnit/browser runs found an Oban migration version mismatch, a reserved LiveView assign name, unnecessary overflow indication, and test timing races. Those were corrected before the successful runs. The amd64 build initially hit a BEAM JIT emulation failure; `+JMsingle true` fixed it. The existing OrbStack VM could not start because its disk is owned by root; it was left untouched. Validation instead used a separate Colima profile without changing the default Docker context.

## Visual artifacts

- [Production dashboard](../artifacts/dashboard.png)
- [Actual preview from production browser](../artifacts/browser-preview.png)
- [Dense calendar rendered locally](../artifacts/calendar-screen.png)
- [Dense calendar rendered in amd64 Docker](../artifacts/calendar-screen-docker.png)
- [Generated setup PNG](../priv/static/setup.png) and [BMP](../priv/static/setup.bmp)

Visual inspection confirmed readable Polish text, black/white pixels, 800×480 dimensions, Monday-first seven-column week, all visible event rows fully inside blocks and overflow markers. The configured 16px week type is dense by necessity; increase block height or reduce the selected calendars to show more events.

## External integration checks still required

1. Configure a real Google Cloud OAuth client and authorize each real account through the documented SSH tunnel. Verify selected calendars and real event changes, recurring exceptions, cancellations and expired/revoked authorization.
2. Deploy `.env` and Compose on the actual amd64 home server, set a device-reachable `PUBLIC_URL`, verify LAN routing/TLS and backup/restore procedures there.
3. Pair the physical TRMNL OG, confirm its firmware supports PNG display downloads, observe setup, first refresh, Polish glyph readability, 15-minute polling, battery/RSSI reporting and last-image retention during network failure.

No real Google account was authorized and no physical TRMNL was observed in this session. Fixture, browser and PNG checks do not replace those integration checks.

## Follow-up: editor responsiveness and missing Google client

Reproduced the reported issues on the running development server with:

```sh
npx playwright test test/browser/responsiveness.spec.js
```

Before the fixes, moving the pointer by 40px left the block at 0px displacement until mouse release; Google authorization was redirected with an empty `client_id` and a callback on port 4000 while the app ran on 4010. The user confirmed that no Google OAuth client had been created. A separate blocked-renderer test also proved that synchronous preview rendering prevented the LiveView from processing editing events.

Changes:

- Dragging and resizing now paint on animation frames in the browser, then send one geometry update at release. Server validation remains authoritative; invalid drops restore the accepted geometry. Escape and pointer cancellation restore the original geometry. Hook listeners are cleaned up on destruction/disconnection.
- Preview and publication run in LiveView background tasks. Editing remains available; a published snapshot is kept separate from later working edits. Rendering failures clear the busy state and permit retries.
- Missing OAuth credentials now show setup guidance without redirecting to Google. The local callback follows the configured port. `scripts/start_dev.py` reads a downloaded Web application client JSON without printing credentials and detects a mismatched callback before launch.
- [Polish Google setup instructions](GOOGLE_SETUP.md) describe the required user-owned Google Cloud configuration. Real OAuth remains pending until the user creates a client and grants consent.

Follow-up checks: 24 ExUnit tests including the real renderer; 4 Python tests covering the credential-file launcher; 3 focused browser regressions covering immediate movement, resize/cancel and the empty-client guard. The full production browser suite passed all 5 tests (54.6s), covering editing, publication, simulated device API, renderer recovery, restart persistence and the new regressions.

## Family content modules — 2026-09-24

Added independent persisted modules for today/tomorrow events, meals, household reminders, countdowns and family notes. Dashboard tabs separate content, layout, and calendar/device settings. Content mutations and their refresh jobs commit together; refreshing uses the published configuration and preserves unfinished layout edits. Removing a block leaves its content available.

`mix precommit` passes (37 tests, two renderer tests excluded). `RENDERER_TEST=1 mix test` passes all 39 tests. New coverage includes CRUD for all modules, validation and concurrent edit rejection, complete/undo, daily/weekly recurrence, Warsaw date boundaries, yearly February 29 anniversaries, chronological order across years, inclusive note windows, escaping, calendar selection, and publication isolation/failure retention.

The browser workflow additionally checks module changes, form resets, completion/undo, all five blocks on one screen, saved content after reconnect, and automatic device image updates while a layout edit remains unpublished. Fixture data is confined to the disposable Compose database.

The complete production browser suite passed **6/6 tests (1.2 minutes)** using the Compose command above, including renderer failure/recovery and full stack restart. The rebuilt amd64 deployment became healthy, the family migration was applied locally and in Compose, and the development health endpoint returned HTTP 200. Both local and Docker-generated family images were inspected.

Validation caught and corrected stale browser field values after form resets, a test race while changing modules, date ordering across years, and preview contention with background content renders. Busy HTTP 503 responses now have bounded retries; a regression verifies both recovery from busy responses and immediate failure for HTTP 500. Visual inspection of the local five-module render confirmed readable Polish text and both days in the today/tomorrow block.

- [Family content dashboard](../artifacts/family-dashboard.png)
- [Five-module monochrome screen](../artifacts/family-screen.png)
- [Local renderer with today and tomorrow fixtures](../artifacts/family-screen-local.png)

## Daily three-task replacement — 2026-09-25

Replaced Today + tomorrow with **3 zadania na dziś**. The module displays today's local tasks only, preserves completed tasks with checkboxes and a completion count, and permits at most three entries per date. Both inserts and moves validate the limit under a transaction lock; completed tasks consume a slot. Calendar events no longer feed this block. Existing content, block geometry and custom titles are preserved; the former default title is upgraded for display.

`mix precommit` passed (39 tests, two real-renderer tests excluded); `RENDERER_TEST=1 mix test` passed all 41 tests. Coverage includes the daily limit, completed slots, editing/moving/deleting, complete/undo from LiveView, Warsaw midnight filtering, and excluding tomorrow/Google events. Pending refresh jobs are coalesced while allowing a follow-up during an executing render; regression coverage verifies both behaviors.

The updated production browser workflow passed (11 seconds), including rejection of a fourth task, task completion, preview/publication and content refresh isolation. The generated Docker image was visually checked with all three tasks and one checked task. The development health endpoint returned HTTP 200.

## UX and LAN deployment preparation — 2026-09-25

`mix precommit` passed with 43 tests and three renderer tests excluded. `RENDERER_TEST=1 mix test` passed all **46 tests**. Three Python preflight tests passed. The full production browser suite passed **7 tests (1.2 minutes)**, including login recovery, keyboard navigation, appearance persistence, stale-preview feedback, and 390px mobile views of all three dashboard tabs.

Actual one-bit 800×480 images of the clock, grouped agenda, month overview, week columns and week rows were generated and visually inspected. Mobile and desktop screenshots were also inspected; the fixed-size editor canvas scrolls within its panel rather than making the whole page overflow.

A separate `trmnl-fresh-ux` Compose project started against a new database volume and all services became healthy; `/health` returned HTTP 200. The backup script created a restricted-permission dump of the disposable validation database, which restored successfully into a separate `trmnl_restore_ux` database (7 family entries and 1 screen). No user database was restored or overwritten. The development server was restarted to load the new clock schedule and retained its existing OAuth configuration.

New deliverables: [UX review](UX_REVIEW.md), [Polish LAN deployment guide](DEPLOY_LAN.md), `scripts/preflight.py`, `scripts/backup.sh`, and `scripts/package_release.py`. The deployment archive uses an explicit file allowlist and excludes `.env`, OAuth downloads, local databases and user artifacts.

The 77-file archive was extracted into a temporary directory, its SHA-256 verified, and its environment generator, preflight and `docker compose config --quiet` all passed. After the final mobile spacing adjustment, the focused UX browser test passed again (5 seconds). The extra fresh-install stack was stopped after verification; its test volume was retained.

Visuals: [desktop](../artifacts/ux-desktop.png), [mobile content](../artifacts/ux-mobile-content.png), [mobile layout](../artifacts/ux-mobile-layout.png), [mobile settings](../artifacts/ux-mobile-settings.png), [month](../artifacts/ux-calendar-month.png), [week rows](../artifacts/ux-calendar-week-rows.png).

## Local services left for inspection

- Validation Compose app: `http://localhost:4011` (password in ignored `.tmp/compose.env`).
- Development app: `http://localhost:4010` (`development-password`).
- Local renderer on `127.0.0.1:3001`; project-local PostgreSQL cluster in `.tmp/postgres` on `127.0.0.1:55432`.
- Isolated Docker context/profile: `colima-trmnl-validation` / `trmnl-validation`.

To stop the validation containers without deleting persisted data:

```sh
docker --context colima-trmnl-validation compose   --env-file .tmp/compose.env -p trmnl-validation down
colima stop trmnl-validation
```

The Homebrew PostgreSQL 17, ImageMagick and Colima packages were installed to enable local verification. No existing Docker data was deleted or its ownership changed. `AGENTS.md` remains unchanged.
