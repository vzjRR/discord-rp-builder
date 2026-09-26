# Handover — Enclave RP Discord Tooling

This repo (`vzjRR/discord-rp-builder`) is being handed off from Claude Code to
another assistant (Codex). This document is the "read this first" for whoever
picks it up next — what exists, what's actually live vs. just committed, and
where the sharp edges are. It complements `README.md` (which covers the
one-time `build.js` server-structure setup) rather than replacing it.

Originally written 2026-09-24, rewritten 2026-09-26 after a live session that
resolved most of the "not yet verified" items from the first version and did
a full visual restyle of every live Discord channel/category. Everything
under "Confirmed live" was verified this session or the previous one directly
against the production server; everything under "Not yet verified" is code
pushed to `master` but never confirmed running.

## 1. What this repo actually is

Four independent Node projects for one Discord server ("Enclave RP", a GTA
FiveM roleplay community), plus root-level one-off scripts that build/modify
the server structure itself:

```
discord-rp-builder/
├── build.js, organization.js, export.js   ← one-off scripts (roles/categories/rename), not long-running
├── config/                                ← role & category definitions used by build.js (known stale, see §5)
├── admin-panel/    (enclave-admin-panel)  ← Express web console, the main thing being worked on lately
├── welcome-bot/    (enclave-admin-bot)    ← join/leave handling, verification, zero-tolerance channel
├── logs-bot/       (enclave-logs-bot)     ← Discord audit/moderation logging to channels + a durable file
└── points-bot/     (enclave-points-bot)   ← auto-counts image posts for a "support points" leaderboard
```

Each subfolder has its own `package.json`/`node_modules` and runs as its own
systemd unit, but — confirmed this session — **all four run from one single
shared checkout**: `/opt/enclave-admin` (see §2). It's a monorepo checkout,
not a monorepo runtime.

The root itself (`build.js`, `organization.js`, `export.js`) is a *fifth*,
separate Node "project" with its own `package.json` (`discord.js` + `dotenv`)
that nothing installs automatically — see the `npm install` gotcha in §2.

LSPD (a related but separate Discord server) used to live partly in this
repo; it was split out into `vzjRR/ENCLAVE-LSPD` earlier and is **not** here
anymore. Don't go looking for `lspd-welcome-bot/` — it doesn't exist in this
checkout.

## 2. Live deployment — confirmed vs. unconfirmed

**Server**: Oracle Cloud VM, hostname `enrp`. Access is via the project owner
directly (SSH) — Claude Code never had direct server access; every
server-side fact below came from the owner running commands and pasting
output back.

### Confirmed live (this session — `systemctl list-units`, `systemctl cat`, live testing)

All four services in this repo share **one checkout**, `/opt/enclave-admin`:

| systemd unit | WorkingDirectory | EnvironmentFile |
|---|---|---|
| `enclave-admin-panel` | `/opt/enclave-admin/admin-panel` | `/etc/enclave-admin.env` |
| `enclave-admin-bot` (welcome-bot) | `/opt/enclave-admin/welcome-bot` | `/etc/enclave-admin-bot.env` |
| `enclave-logs-bot` | `/opt/enclave-admin/logs-bot` | **none found** — see open items §7 |
| `enclave-points-bot` | `/opt/enclave-admin/points-bot` | `/etc/enclave-points-bot.env` |

Deploy pattern used throughout both sessions:
```
git -C /opt/enclave-admin fetch origin master --quiet
git -C /opt/enclave-admin reset --hard origin/master --quiet
sudo chown -R enclave-admin:enclave-admin /opt/enclave-admin
sudo systemctl restart <unit>
```
**There is no CI/CD** — every deploy is this exact manual sequence, run by
the owner over SSH after being given the command.

**Real shared data directory: `/opt/enclave-admin/data`** (confirmed via
`ReadWritePaths` in the `enclave-admin-panel`/`enclave-admin-bot` units) —
**not** `/data` as the code's own fallback defaults assume. This only works
because every path-related env var in `/etc/enclave-admin.env` /
`/etc/enclave-admin-bot.env` explicitly overrides the default to the real
path — if you ever add a new DB/JSON file without an explicit env var
pointing at `/opt/enclave-admin/data/...`, it will silently try to write to
`/data` and fail (or worse, succeed somewhere unexpected on a differently
configured box). See §3 for the full path table.

**Gotcha hit this session**: the repo root (`build.js`, `organization.js`,
`export.js`) has never had `npm install` run against it on the live server —
only the subfolders (`admin-panel/`, `welcome-bot/`, `logs-bot/`,
`points-bot/`) get their dependencies installed as part of normal deploys.
Running any root script (`node build.js ...`, `node export.js`) for the
first time on a fresh checkout needs:
```
cd /opt/enclave-admin && npm install --omit=dev
```
first, or it fails with `Cannot find module 'discord.js'`.

### ⚠️ Do not trust `deploy/*/*.service` in this repo

`deploy/enclave-panel/enclave-panel.service` (the template checked into this
repo) says `WorkingDirectory=/opt/enclave/admin-panel`,
`EnvironmentFile=/etc/enclave/panel.env`, user `enclave`. **None of that
matches the real live values above.** Always verify against the live server
(`systemctl cat <unit>`) before assuming a path from this repo's own
docs/templates is correct.

### Full list of `enclave-*` systemd units on the box (confirmed this session)

```
enclave-admin-bot            (this repo — welcome-bot)
enclave-admin-panel          (this repo)
enclave-logs-bot              (this repo)
enclave-points-bot            (this repo)
enclave-censorship            (separate app: /opt/enclave-censorship/app/server)
enclave-home                  (separate app: /opt/enclave-home/app — enclaverp.cc homepage)
enclave-server-status         (separate app: /opt/enclave-server-status, own .env in WorkingDirectory)
enclave-tickets               (separate app: /opt/enclave-tickets, own .env in WorkingDirectory)
enclave                       (separate app: /opt/enclave/app — "Enclave RP Store")
```
Only the first four are this repo. The rest are sibling projects on the same
box — see the note below. `enclave-tickets-demo` and `lspd-bot/tickets-bot`
were seen in an earlier session's file listing but didn't show up in this
session's `systemctl list-units` pass; may have been removed, or just not
running as a service — not re-verified.

### Not yet deployed/tested — verification-delay feature

The delayed-verification system (§6) was fully written and pushed in the
previous session, but **as of this handover it's still untouched since
then**:
- `node build.js verification-gate` (the one-time Discord permission change
  restricting the pending role's channel visibility) has still **never been
  run** against the live server.
- The feature's toggle still defaults to **off**; never flipped on, never
  tested end-to-end against a real join.

**Whoever picks this up: don't assume this feature works until someone runs
the gate command, flips the toggle on, and tests an actual join.**

### The Oracle box hosts more than this repo

Several *sibling* projects live alongside this one under `/opt/`, sharing
the **same** Discord Application (Client ID `1535663542420643880`, so the
same `DISCORD_CLIENT_SECRET` — value intentionally not repeated in this
file, see it in `/etc/enclave.env` or `/etc/enclave-home.env` on the server):
`/opt/enclave/app`, `/opt/enclave-home/app`, `/opt/enclave-censorship/app`,
`/opt/enclave-server-status`, `/opt/enclave-tickets`. Some (tickets,
server-status) use their **own**, different Discord Client IDs. None of
these are in `vzjRR/discord-rp-builder` — mentioned here only so nobody
assumes this repo is the whole story on that server, or edits a shared
secret without realizing other services depend on the same value.

## 3. Shared runtime resources between services in *this* repo

All three bots + admin-panel expect a shared writable directory — **really
`/opt/enclave-admin/data` on the live server, see §2** — containing:

| File | Written by | Read by | Purpose |
|---|---|---|---|
| `admin.db` (SQLite) | admin-panel | admin-panel | accounts, sessions, audit log, access requests |
| `server-events.db` (SQLite) | welcome-bot (`lib/activityTracker.js`) | welcome-bot, admin-panel (`/status` page) | join/leave history, message-count activity |
| `zero-tolerance.db` (SQLite) | welcome-bot (`lib/zeroTolerance.js`) | welcome-bot | per-user violation counter for the auto-kick/ban channel |
| `verification-delay.db` (SQLite) | welcome-bot (`lib/verificationDelay.js`) | welcome-bot | durable schedule for the pending→citizen role swap |
| `points.db` (SQLite) | points-bot | points-bot, admin-panel (`/points` page) | image-count leaderboard |
| `message-templates.json` | admin-panel (owner edits) | welcome-bot | override for the join-message/DM text |
| `onboarding-message.json` / `revocation-message.json` | admin-panel | admin-panel | DM text for account creation/revocation |
| `verification-delay-settings.json` | admin-panel (toggle) | welcome-bot | on/off switch for the verification-delay feature, checked on every join |

Plus `/var/log/enclave/audit.log` (JSON-lines, append-only) — written by
**both** `logs-bot/lib/logs.js` and `admin-panel/src/audit.js`, independent
of whether the corresponding Discord log channel exists or is reachable.
This is the one durable record that survives Discord channel deletion or the
panel's own "clear audit log" button.

Env vars that point at these (see §4 for the full list): `SQLITE_PATH`,
`EVENTS_DB_PATH`, `ZERO_TOLERANCE_DB_PATH`, `VERIFICATION_DELAY_DB_PATH`,
`POINTS_DB_PATH`, `MESSAGE_TEMPLATES_PATH`, `ONBOARDING_MESSAGE_PATH`,
`REVOCATION_MESSAGE_PATH`, `VERIFICATION_DELAY_SETTINGS_PATH`,
`AUDIT_LOG_FILE_PATH`. Every one of them has a `/data/...` default in code
if unset, but the live server always sets them explicitly to
`/opt/enclave-admin/data/...` — see the §2 gotcha before adding a new one.

One systemd gotcha already hit once in this project's life: `ProtectSystem=strict`
makes the whole filesystem read-only except what `ReadWritePaths` explicitly
lists — a hand-typed unit file with the wrong path here caused a real
crash-loop. If a bot can't write its DB, check `ReadWritePaths` in its
systemd unit before anything else.

## 4. Environment variables, by service

Root scripts (`build.js`, `organization.js`, `export.js`): `DISCORD_TOKEN`,
`GUILD_ID` — loaded via `dotenv` from a `.env` file in the repo root, or
exported manually into the shell first (there's no systemd EnvironmentFile
for these since they're one-off scripts, not services).

**welcome-bot** (no `.env.example` file exists for it — reconstructed from
`process.env` references in its source): `DISCORD_TOKEN`, `GUILD_ID`,
`WELCOME_CHANNEL_ID`, `RULES_CHANNEL_ID`, `TICKET_CHANNEL_ID`,
`EVENTS_DB_PATH`, `ZERO_TOLERANCE_DB_PATH`, `VERIFICATION_DELAY_DB_PATH`,
`VERIFICATION_DELAY_SETTINGS_PATH`, `MESSAGE_TEMPLATES_PATH`,
`FONTCONFIG_PATH` (needed for Arabic name rendering in the generated welcome
image — see `lib/composeWelcomeImage.js`), `PORT` (only if deployed on a PaaS
needing a health-check port).

**logs-bot**: `DISCORD_TOKEN`, `GUILD_ID`, `LOG_CHANNEL_ID` (optional —
routes all log types to one channel instead of per-type by name),
`LOG_DISABLE_TYPES` (comma-separated), `AUDIT_LOG_FILE_PATH`. Its live
`EnvironmentFile` wasn't found this session — see §7.

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

`config/categories.js` is the clearest example, and it's **worse than
previously documented**. A fresh live export this session
(`node export.js` → `server-snapshot.json`) showed the live server has
**35 categories and 108 roles**, while `config/categories.js` only ever
modeled **19** categories. Beyond the count mismatch, most live category and
channel names use stylized Unicode (bold/italic mathematical alphanumeric
characters, e.g. the live `"👑 𝑴𝑨𝑵𝑨𝑮𝑬𝑴𝑬𝑵𝑻"` vs. this file's plain
`"👑 MANAGEMENT"`) that was added by hand at some point and never reflected
back into this file. There are also entire live categories this file has
never heard of at all: gang RP categories (Mafia, Bloods, Vagos, Familya,
Ballas, Crips, MS-13...), a streamers hub, ban-appeal/compensation/inquiries
categories, a `Band` category, an `Expired Tickets` category, and more.

**Because of this, any script that needs to know "what's actually on the
server" reads the *live* guild via the bot API at runtime and never trusts
this file** — both `build.js verification-gate` and the newer
`build.js channel-style` (§6) do this deliberately. `config/categories.js`
is kept in the repo mostly as a record of the *original* intended structure
and for `build.js categories`, which only ever *adds missing* channels by
exact name match — it does not, and cannot, reconcile with the real 35-vs-19
drift described above. Don't trust a category/channel name in this file
literally for anything beyond documentation.

`deploy/enclave-panel/enclave-panel.service` is the other known-stale file
— see §2.

Lesson for whoever continues: when a task needs to know "what's actually on
the server," verify against the live Discord/server state (`node export.js`,
or the bot API directly), don't assume a committed config file is current.

## 6. Recent work (most recent first)

1. **Full visual restyle of every live Discord channel/category** (this
   session, 2026-09-26). The owner wanted every channel/category to look
   like a reference screenshot from an unrelated server — decorative
   bracket/dash styling, but keeping the actual English words unchanged.
   Landed pattern:
   - Text channels: `⌈{emoji}⌋⁞{name}` (no spaces) — e.g.
     `👋・welcome` → `⌈👋⌋⁞welcome`.
   - Categories: `EN│───⌈ {old label} ⌋───` (3 fixed dashes each side) — e.g.
     `🎉 EVENTS` → `EN│───⌈ 🎉 EVENTS ⌋───`.
   - Voice channels are **never touched** — the reference design was
     text-channels only, and live voice-channel names already use spaces
     that don't fit the pattern.

   Implemented as a new `build.js channel-style` subcommand (with a
   `--dry-run` flag that prints every planned change without touching
   Discord — **use it before every live run**, this repo has burned itself
   twice already on stale-config surprises). It reads the *live* guild at
   runtime (see §5), so it naturally covers channels `config/categories.js`
   doesn't even know exist. It's also idempotent and self-correcting: it
   recognizes a category it already restyled (regardless of how many dashes
   it currently has) and recomputes the correct name from the label inside,
   so re-running it after a formula change fixes previously-touched
   categories too — it doesn't just skip them.

   Two real bugs found and fixed via the live `--dry-run` output before
   going live for real, both worth knowing about if this code is touched
   again:
   - The channel-name splitter originally checked separator characters
     (`・` vs `〡`) in a fixed array order rather than by which one actually
     appears first in the string. One live channel used both
     (`⭐〡Server・Status`) and got mis-split until fixed.
   - The very first version used **7 fixed dashes** per side on category
     names. Combined with long English labels (`MINISTRY OF JUSTICE`,
     `POLICE DEPARTMENT`), the resulting name was long enough that
     Discord's own sidebar UI truncated it before the closing `⌋` ever
     rendered — a client-side width limit, not anything the Discord API
     rejects. Settled on 3 fixed dashes after live testing.

   11 channels were left untouched on purpose — they have an emoji glued
   directly onto the text with **no** separator character at all (e.g.
   `☠️𝐌𝐚𝐟𝐢𝐚`, `ticket-2101`, `𝐫𝐞𝐯𝐢𝐞𝐰`), so there's nothing to split on.
   Handling those would need actual emoji-boundary detection, not string
   splitting — not built, not asked for. Full list is in the dry-run output
   history in this session's transcript if it ever comes up again.

   Orphan channels (no parent category) are always excluded, hard-coded, not
   configurable. Announcement-type channels (Discord `ChannelType.
   GuildAnnouncement`, e.g. a couple of "Gangs-Announcement" style channels)
   are restyled alongside regular text channels — the first version of the
   script silently missed these entirely, since it only looked at
   `GuildText`.

   The "Security & Logs" category was **initially excluded** from the
   rename (logs-bot matches its channels by exact name, so renaming it
   without updating `logs-bot/config/logs.js` in lockstep would have broken
   moderation logging) — then the owner explicitly asked for it to be
   *included* after all. It was, and `logs-bot/config/logs.js`,
   `logs-bot/find-deleter.js`, and `config/categories.js`'s `security-logs`
   entry were all updated to the new wrapped names in the same commit. This
   is the one place in `config/categories.js` where the name field is
   trustworthy right now, precisely because logs-bot depends on it — it was
   kept in sync deliberately, unlike the rest of the file (§5).

   **Confirmed live and working** — owner ran it for real on the production
   server, restarted all three bots, confirmed everything looks right in
   Discord ("all okay. done."). 104 channels/categories were renamed; the
   `enclave-logs-bot` and `enclave-admin-bot` services restarted clean with
   no channel-not-found warnings afterward.

   **Known gap, not yet fixed**: `welcome-bot/config/welcome.js`'s
   `channelName`/`rulesChannelName`/`ticketChannelName` fields (used as a
   by-name fallback for the welcome/rules/ticket channel mentions in join
   messages) were **already wrong before this session's restyle work even
   started** — the live channel names use bold Unicode text
   (`✈️・𝗘𝐧𝐜𝐥𝐚𝐯𝐞-𝐚𝐢𝐫𝐩𝐨𝐫𝐭`, `🎫・𝐂𝐫𝐞𝐚𝐭𝐞-𝐓𝐢𝐜𝐤𝐞𝐭`, etc.) that this file never
   matched even in its pre-restyle form. Deliberately **not guessed at**
   this session, to avoid shipping a second wrong guess — these channels
   *were* included in the live rename (so their real current names are now
   wrapped versions of whatever the bold-Unicode live names actually are),
   but `welcome.js` itself was left untouched. See §7 for the exact
   follow-up needed.

   Full backup taken before any of this ran (worth reusing the same pattern
   for any future bulk live-Discord change): whole-checkout tarball, the
   deployed commit hash, a tarball of `/opt/enclave-admin/data`, a tarball of
   every `/etc/enclave*` file, and a `node export.js` JSON snapshot of the
   live channel/category/role structure taken immediately before the rename
   — all under `/root/backups/` on the server, timestamped.

2. **Delayed-verification system for new members** (off by default, still
   untouched since it landed — see §2). New members get a temporary
   `⏳ Pending Verification` role instead of `👤 Citizen` immediately — 5
   minutes for a first-time join, 15 for a returning member (detected via a
   prior `leave` row in `server-events.db`). Bilingual (AR/EN) DM on join and
   on verification. Scheduling survives bot restarts (SQLite table, not bare
   `setTimeout`). Toggle lives in admin-panel → الرسائل الثابتة. Channel
   visibility restriction is a **separate one-time step**:
   `node build.js verification-gate`, still not run.
   Files: `welcome-bot/config/verificationDelay.js`,
   `welcome-bot/lib/verificationDelay.js`, `welcome-bot/lib/welcome.js`
   (gated), `welcome-bot/lib/activityTracker.js` (`hasEverLeft` added),
   `build.js` (`verification-gate` subcommand),
   `admin-panel/src/routes/templates.js` + `public/templates.html` (toggle
   UI).

3. **moderation-log now includes attachment URLs and who deleted a
   message.** Discord's `messageDelete` gateway event never includes the
   executor — only a separate Audit Log entry that can lag behind. The
   handler now waits up to 3s for a matching `guildAuditLogEntryCreate`
   entry before sending the log. Self-deletes (Discord records no audit
   entry for those) are now labeled explicitly instead of silently blank.
   File: `logs-bot/events/moderationLog.js`.
   **Known related gap, not fixed**: bulk-deletes (Discord's
   `messageBulkDelete` event) still aren't logged by this file at all — only
   single-message deletes are handled.

4. **Fixed FiveM status showing nothing**: Cfx.re moved their public
   server-list API from `servers-frontend.fivem.net` (404s for every
   server) to `frontend.cfx-services.net`. File: `admin-panel/src/fivem.js`.
   **Known limitation, not a bug**: if `sv_endpointPrivacy` is enabled on
   the FiveM server, the player list in that same API comes back fully
   redacted (`name: "Player"`, `id: 0`) for every connected player — FXServer's
   own behavior, an open product decision for the server owner, not
   something the panel can fix in code.

5. **Discord OAuth login**, replacing PIN-only login as the primary flow.
   `src/discordOAuth.js` + `src/routes/discordAuth.js`. Unregistered members
   who log in via Discord get redirected to `/request-access`; the owner
   gets a DM and can one-click-approve from `admin-panel`. Approved/manually-
   created accounts get an unusable random PIN internally since they only
   ever log in via Discord — the PIN column still exists in the DB schema
   but is effectively vestigial for new accounts. The PIN-login form itself
   was later **removed entirely** from `login.html`. Owner-only "log out
   everyone" button added (`POST /api/admins/logout-all`).

6. **Full visual redesign + rebrand to "Enclave RP BOT"**: light theme
   (white + purple) and a full dark theme (black + gold) with a
   localStorage-persisted toggle, custom hand-drawn nav icons, self-hosted
   IBM Plex Sans Arabic font. Moderation tools merged from a standalone
   `/moderation` page into a third tab on `/server`; `/moderation` now
   redirects.

Older context (points-bot integration, zero-tolerance auto-kick/ban channel,
durable audit-file mirroring, the LSPD repo split) predates active work on
this repo and is visible in `git log` if needed, but is stable/unchanged.

## 7. Open items

- `node build.js verification-gate` still needs running on the live server,
  and the feature's toggle is still off (§2/§6.2) — unchanged from the
  previous handover.
- **`welcome-bot/config/welcome.js`'s channel-name fallbacks need a precise
  follow-up** (§6.1): run `node export.js` now that the rename is live, find
  the real current names of the welcome/rules/ticket channels in
  `server-snapshot.json`, and set `channelName`/`rulesChannelName`/
  `ticketChannelName` to match exactly (copy-paste, don't hand-transcribe —
  these use bold Unicode characters that are easy to get subtly wrong by
  hand). Also worth checking whether `WELCOME_CHANNEL_ID`/`RULES_CHANNEL_ID`/
  `TICKET_CHANNEL_ID` are actually set in `/etc/enclave-admin-bot.env` — if
  they are, these name fields are cosmetic-fallback-only and this is low
  priority; if they aren't, welcome messages may have been silently missing
  channel mentions for a while.
- **`enclave-logs-bot`'s `EnvironmentFile` wasn't found** this session (see
  §2/§4 table) — `systemctl cat enclave-logs-bot` showed no
  `EnvironmentFile=` line at all, unlike the other three units. Worth
  checking where it actually gets `DISCORD_TOKEN`/`GUILD_ID` from before
  relying on any assumption about its config.
- 11 channels with no separator character at all weren't covered by the
  channel-style rename (§6.1) — cosmetic-only gap, not urgent, would need
  emoji-boundary detection to fix.
- Bulk-message-delete isn't logged by `logs-bot` (§6.3) — a real gap, not
  urgent unless it matters operationally.
- `sv_endpointPrivacy` player-name redaction (§6.4) is an open product
  decision for the server owner, not a code task.
- Two stale items from a much older backlog, status unclear — verify before
  acting on either: a Railway SSL-cert support ticket (the Railway account
  itself was deleted entirely earlier in this project's life, so this may
  simply be moot now), and a standalone "Enclave RP tickets bot" build (an
  `enclave-tickets` service was separately found already running live on the
  Oracle box — possibly already covers this, was never confirmed either way).

## 8. Git workflow used throughout this project

No CI/CD, no PR-based merging for this owner's normal flow — commits go
straight to `claude/project-setup-deployment-g4jde9`, then get fast-forwarded
onto `master`, then both get pushed. As of this rewrite the two branches are
identical (`35b8d5e`). Deploys are the manual sequence in §2, run by the
owner over SSH after being given the exact commands — there is no automatic
deployment on push.
