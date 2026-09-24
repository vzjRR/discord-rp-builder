# Handover — Enclave RP Discord Tooling

This repo (`vzjRR/discord-rp-builder`) is being handed off from Claude Code to
another assistant (Codex). This document is the "read this first" for whoever
picks it up next — what exists, what's actually live vs. just committed, and
where the sharp edges are. It complements `README.md` (which covers the
one-time `build.js` server-structure setup) rather than replacing it.

Written 2026-09-24. Everything under "Confirmed live" was verified during a
live session on the production server; everything under "Not yet verified"
is code that's pushed to `master` but was never confirmed running.

## 1. What this repo actually is

Four independent Node projects for one Discord server ("Enclave RP", a GTA
FiveM roleplay community), plus root-level one-off scripts that build the
server structure itself:

```
discord-rp-builder/
├── build.js, organization.js, export.js   ← one-off scripts (roles/categories), not long-running
├── config/                                ← role & category definitions used by build.js
├── admin-panel/    (enclave-admin-panel)  ← Express web console, the main thing being worked on lately
├── welcome-bot/    (enclave-welcome-bot)  ← join/leave handling, verification, zero-tolerance channel
├── logs-bot/       (enclave-logs-bot)     ← Discord audit/moderation logging to channels + a durable file
└── points-bot/     (enclave-points-bot)   ← auto-counts image posts for a "support points" leaderboard
```

Each has its own `package.json` and runs as its own process/systemd unit —
they are **not** a monorepo runtime, just a monorepo *checkout*. They share
one Discord Application (one `DISCORD_TOKEN`, one `GUILD_ID`).

LSPD (a related but separate Discord server) used to live partly in this
repo; it was split out into `vzjRR/ENCLAVE-LSPD` earlier and is **not** here
anymore. Don't go looking for `lspd-welcome-bot/` — it doesn't exist in this
checkout.

## 2. Live deployment — confirmed vs. unconfirmed

**Server**: Oracle Cloud VM, hostname `enrp`. Access is via the project owner
directly (SSH) — Claude Code in this session never had direct server access;
every server-side fact below came from the owner running commands and
pasting output back.

### Confirmed live (verified this session via `systemctl cat`, `grep`, etc.)

- `admin-panel` is deployed at `/opt/enclave-admin` (with the repo checked out
  there — `admin-panel/` is presumably a subdirectory, matching how `git -C
  /opt/enclave-admin fetch/reset` was used throughout this session).
- systemd unit: `enclave-admin-panel`
- `EnvironmentFile=/etc/enclave-admin.env`
- Deploy pattern used throughout: `git -C /opt/enclave-admin fetch origin
  master --quiet && git -C /opt/enclave-admin reset --hard origin/master
  --quiet && chown -R enclave-admin:enclave-admin /opt/enclave-admin &&
  systemctl restart enclave-admin-panel`. **There is no CI/CD** — every
  deploy this session was this exact manual command run by the owner after
  being told to.
- `/etc/enclave-admin.env` currently has `DISCORD_CLIENT_ID`,
  `DISCORD_CLIENT_SECRET`, and `FIVEM_SERVER_ID` set and confirmed working
  (Discord OAuth login works; FiveM status widget shows real live data).

### ⚠️ Do not trust `deploy/*/*.service` in this repo

`deploy/enclave-panel/enclave-panel.service` (the template checked into this
repo) says `WorkingDirectory=/opt/enclave/admin-panel`,
`EnvironmentFile=/etc/enclave/panel.env`, user `enclave`. **None of that
matches the real live values above.** The templates in `deploy/` have
drifted from what's actually running — same pattern as `config/categories.js`
(see §5). Always verify against the live server (`systemctl cat <unit>`)
before assuming a path from this repo's own docs/templates is correct.

### Not yet verified — welcome-bot / logs-bot live paths

This session never got explicit confirmation of `welcome-bot`'s or
`logs-bot`'s live systemd unit name or install path. Deploy commands were
given with placeholder paths (`/opt/enclave-logs-bot`, etc.) and the owner
was asked to correct them if wrong — no confirmation followed. **Before
deploying anything to those two, run `systemctl list-units | grep -i
enclave` on the server first** to find the real unit names, rather than
guessing from this repo's `deploy/` templates (which, per the above, cannot
be trusted).

### Not yet deployed/tested — most recent feature (verification delay)

The delayed-verification system (§6, most recent commit) was fully written
and pushed, but:
- `node build.js verification-gate` (the one-time Discord permission change
  that actually restricts the pending role's channel visibility) was **never
  run** against the live server as of this handover.
- The feature's toggle defaults to **off**; it was never flipped on and
  never tested end-to-end against real Discord joins.
- The welcome-bot code change that reads the toggle was never confirmed
  deployed (see previous point about unconfirmed welcome-bot deploy path).

**Whoever picks this up: don't assume this feature works until someone runs
the gate command, deploys welcome-bot, flips the toggle on, and tests an
actual join.**

### The Oracle box hosts more than this repo

`grep`-ing the server during this session surfaced several *sibling*
projects living alongside this one under `/opt/`, sharing the **same**
Discord Application (Client ID `1535663542420643880`, so the same
`DISCORD_CLIENT_SECRET` — value intentionally not repeated in this file,
see it in `/etc/enclave.env` or `/etc/enclave-home.env` on the server):

- `/opt/enclave/app`, `/opt/enclave-home/app`, `/opt/enclave-censorship/app`
  — separate Node apps, not part of this git repo at all.
- `/opt/enclave-server-status`, `/opt/enclave-tickets`,
  `/opt/enclave-tickets-demo`, `/opt/lspd-bot/tickets-bot` — more separate
  projects, own `.env` files, own Discord Client IDs (different from the
  main one above in at least the tickets-bot and server-status cases).

None of these are in `vzjRR/discord-rp-builder`. They're mentioned here only
so nobody assumes this repo is the whole story on that server, or edits a
shared secret without realizing three other services depend on the same
value.

## 3. Shared runtime resources between services in *this* repo

All three bots + admin-panel expect a shared writable directory (`/data` by
convention, overridable per-var below) containing:

| File | Written by | Read by | Purpose |
|---|---|---|---|
| `admin.db` (SQLite) | admin-panel | admin-panel | accounts, sessions, audit log, access requests |
| `server-events.db` (SQLite) | welcome-bot (`lib/activityTracker.js`) | welcome-bot, admin-panel (`/status` page) | join/leave history, message-count activity |
| `zero-tolerance.db` (SQLite) | welcome-bot (`lib/zeroTolerance.js`) | welcome-bot | per-user violation counter for the auto-kick/ban channel |
| `verification-delay.db` (SQLite) | welcome-bot (`lib/verificationDelay.js`) | welcome-bot | durable schedule for the pending→citizen role swap |
| `points.db` (SQLite) | points-bot | points-bot, admin-panel (`/points` page) | image-count leaderboard |
| `message-templates.json` | admin-panel (owner edits) | welcome-bot | override for the join-message/DM text |
| `onboarding-message.json` / `revocation-message.json` | admin-panel | admin-panel | DM text for account creation/revocation |
| `verification-delay-settings.json` | admin-panel (toggle) | welcome-bot | on/off switch for §6, checked on every join |

Plus `/var/log/enclave/audit.log` (JSON-lines, append-only) — written by
**both** `logs-bot/lib/logs.js` and `admin-panel/src/audit.js`, independent
of whether the corresponding Discord log channel exists or is reachable.
This is the one durable record that survives Discord channel deletion or the
panel's own "clear audit log" button.

Env vars that point at these (see §4 for the full list): `SQLITE_PATH`,
`EVENTS_DB_PATH`, `ZERO_TOLERANCE_DB_PATH`, `VERIFICATION_DELAY_DB_PATH`,
`POINTS_DB_PATH`, `MESSAGE_TEMPLATES_PATH`, `ONBOARDING_MESSAGE_PATH`,
`REVOCATION_MESSAGE_PATH`, `VERIFICATION_DELAY_SETTINGS_PATH`,
`AUDIT_LOG_FILE_PATH`. Every one of them has a sensible `/data/...` default
if unset — nothing crashes without them, they just default to that path.

One systemd gotcha already hit once this session: `ProtectSystem=strict`
makes the whole filesystem read-only except `ReadWritePaths` explicitly lists
— a hand-typed unit file with the wrong path here caused a real crash-loop
earlier in this project's life. If a bot can't write its DB, check
`ReadWritePaths` in its systemd unit before anything else.

## 4. Environment variables, by service

Root scripts (`build.js` etc.): `DISCORD_TOKEN`, `GUILD_ID`

**welcome-bot** (no `.env.example` file exists for it — this list is
reconstructed from `process.env` references in its source):
`DISCORD_TOKEN`, `GUILD_ID`, `WELCOME_CHANNEL_ID`, `RULES_CHANNEL_ID`,
`TICKET_CHANNEL_ID`, `EVENTS_DB_PATH`, `ZERO_TOLERANCE_DB_PATH`,
`VERIFICATION_DELAY_DB_PATH`, `VERIFICATION_DELAY_SETTINGS_PATH`,
`MESSAGE_TEMPLATES_PATH`, `FONTCONFIG_PATH` (needed for Arabic name
rendering in the generated welcome image — see `lib/composeWelcomeImage.js`),
`PORT` (only if deployed on a PaaS needing a health-check port).

**logs-bot**: `DISCORD_TOKEN`, `GUILD_ID`, `LOG_CHANNEL_ID` (optional —
routes all log types to one channel instead of per-type by name),
`LOG_DISABLE_TYPES` (comma-separated), `AUDIT_LOG_FILE_PATH`.

**points-bot**: `DISCORD_TOKEN`, `IMAGE_POINTS_CHANNEL_ID`, `POINTS_DB_PATH`,
`AUDIT_LOG_FILE_PATH`, `TIMEZONE`, `WEEK_START_DAY`,
`ADJUST_POINTS_ON_MESSAGE_EDIT`.

**admin-panel**: `DISCORD_TOKEN`, `GUILD_ID`, `SQLITE_PATH`,
`AUDIT_LOG_FILE_PATH`, `SESSION_SECRET`, `OWNER_SETUP_PIN`,
`OWNER_SETUP_NAME`, `OWNER_RESET_PIN`, `TEST_MODE_REDIRECT_USER_ID`,
`OWNER_NOTIFY_USER_ID`, `PUBLIC_BASE_URL`, `CLOUDFLARE_SECRET`,
`REQUIRE_CLOUDFLARE`, `PORT`, `MESSAGE_TEMPLATES_PATH`,
`ONBOARDING_MESSAGE_PATH`, `REVOCATION_MESSAGE_PATH`, `POINTS_DB_PATH`,
`FIVEM_SERVER_ID`, `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`.
See `admin-panel/.env.example` for the fully-commented version of this list.

## 5. Things that look authoritative in this repo but are stale

Twice now, a config file that looks like "the source of truth" turned out to
not match the live Discord server or the live deployment:

- **`config/categories.js`** claims (in its own header comment) to match the
  server "as of 2026-08-08", but it doesn't list the channel names actually
  in use (e.g. the zero-tolerance channel, ID `1543257776762003556`, isn't
  in this file at all — it's not under any category on the live server).
  Because of this, `build.js verification-gate` (§6) deliberately reads the
  *live* guild's channel list via the bot API at runtime instead of trusting
  this file.
- **`deploy/enclave-panel/enclave-panel.service`** — see §2, doesn't match
  the real live paths.

Lesson for whoever continues: when a task needs to know "what's actually on
the server," verify against the live Discord/server state (via the bot API
or SSH), don't assume a committed config file is current.

## 6. Recent work this session (most recent first)

1. **Delayed-verification system for new members** (off by default). New
   members get a temporary `⏳ Pending Verification` role instead of
   `👤 Citizen` immediately — 5 minutes for a first-time join, 15 for a
   returning member (detected via a prior `leave` row in
   `server-events.db`, not by any Discord-native flag). Bilingual (AR/EN) DM
   on join and on verification. Scheduling survives bot restarts (SQLite
   table, not bare `setTimeout`). Toggle lives in admin-panel → الرسائل
   الثابتة. Channel visibility restriction is a **separate one-time step**:
   `node build.js verification-gate`, not run yet (see §2).
   Files: `welcome-bot/config/verificationDelay.js`,
   `welcome-bot/lib/verificationDelay.js`, `welcome-bot/lib/welcome.js`
   (gated), `welcome-bot/lib/activityTracker.js` (`hasEverLeft` added),
   `build.js` (`verification-gate` subcommand),
   `admin-panel/src/routes/templates.js` + `public/templates.html` (toggle
   UI).

2. **moderation-log now includes attachment URLs and who deleted a
   message.** Discord's `messageDelete` gateway event never includes the
   executor — only a separate Audit Log entry that can lag behind. The
   handler now waits up to 3s for a matching `guildAuditLogEntryCreate`
   entry (verified against the actual installed discord.js v14.16.3 source,
   not guessed) before sending the log. Self-deletes (Discord records no
   audit entry for those) are now labeled explicitly instead of silently
   blank. File: `logs-bot/events/moderationLog.js`.
   **Known related gap, not fixed**: bulk-deletes (Discord's
   `messageBulkDelete` event) still aren't logged by this file at all — only
   single-message deletes are handled.

3. **Fixed FiveM status showing nothing**: Cfx.re moved their public
   server-list API from `servers-frontend.fivem.net` (now 404s for *every*
   server, confirmed independent of this server specifically) to
   `frontend.cfx-services.net` — found by fetching the actual
   `cfx.re/join/<id>` page and reading which API it calls client-side.
   File: `admin-panel/src/fivem.js`.
   **Known limitation, not a bug**: if `sv_endpointPrivacy` is enabled on
   the FiveM server, the player list in that same API comes back fully
   redacted (`name: "Player"`, `id: 0`) for *every* connected player — this
   is FXServer's own behavior, not something the panel can work around
   without the server owner changing that convar (which also exposes real
   names to *any* third party querying the same public API, not just this
   panel — flagged to the owner as a tradeoff, not resolved either way).

4. **Discord OAuth login**, replacing PIN-only login as the primary flow.
   `src/discordOAuth.js` + `src/routes/discordAuth.js`. Unregistered members
   who log in via Discord get redirected to `/request-access`, which shows
   their *verified* Discord identity (avatar, username, highest role — via
   the bot's own guild-member lookup, not self-reported) and asks only for a
   reason; the owner gets a DM and can one-click-approve from
   `admin-panel`. Approved/manually-created accounts now get an unusable
   random PIN internally (never shown to anyone) since they only ever log in
   via Discord — the PIN column still exists in the DB schema but is
   effectively vestigial for new accounts. The PIN-login form itself was
   later **removed entirely** from `login.html` at the owner's request —
   existing legacy PIN accounts have no UI path to log in anymore unless
   they link their Discord (self-service "ربط الحساب" banner in `app.js` for
   any logged-in admin without `discord_user_id` set).
   Owner-only "log out everyone" button added
   (`POST /api/admins/logout-all`) for exactly this kind of auth migration.

5. **Full visual redesign + rebrand to "Enclave RP BOT"**: light theme
   (white + purple) and a full dark theme (black + gold) with a
   localStorage-persisted toggle, custom hand-drawn nav icons, self-hosted
   IBM Plex Sans Arabic font. Moderation tools were merged from a standalone
   `/moderation` page into a third tab on `/server` (they always needed
   overlapping Discord permissions anyway); `/moderation` now redirects.

Older context (points-bot integration, zero-tolerance auto-kick/ban channel,
durable audit-file mirroring, the LSPD repo split) predates this session's
active work and is visible in `git log` if needed, but is stable/unchanged.

## 7. Open items

- `node build.js verification-gate` needs running on the live server (§2/§6.1).
- Confirm welcome-bot's and logs-bot's actual live deploy paths/unit names
  before pushing more changes to either (§2).
- Bulk-message-delete isn't logged by `logs-bot` (§6.2) — a real gap, not
  urgent unless it matters operationally.
- `sv_endpointPrivacy` player-name redaction (§6.3) is an open product
  decision for the server owner, not a code task.
- Two stale items from a much older backlog, status unclear — verify before
  acting on either: a Railway SSL-cert support ticket (the Railway account
  itself was deleted entirely earlier in this project's life, so this may
  simply be moot now), and a standalone "Enclave RP tickets bot" build (an
  `enclave-tickets` service was separately found already running live on the
  Oracle box — possibly already covers this, was never confirmed either way).

## 8. Git workflow used throughout this project

No CI/CD, no PR-based merging for this owner's normal flow — commits went
straight to `claude/project-setup-deployment-g4jde9`, then fast-forwarded
onto `master`, then both pushed. As of this handover the two branches are
identical (`5fd4a20`). Deploys are manual `git fetch && git reset --hard
origin/master && systemctl restart <unit>` run by the owner over SSH after
being given the exact command — there is no automatic deployment on push.
