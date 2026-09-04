# 🎮 FiveM

Lua resources for a FiveM server. Independent of the Discord bots at the repo
root — no shared `package.json`, no shared environment.

| Path | What it is |
|---|---|
| [`mangonazlet/`](mangonazlet/) | 🥭 **MangoNazlet** — ice cream & dessert restaurant job |
| [`release/MangoNazlet/`](release/) | Ready-to-copy installation package |
| [`PLAN.md`](PLAN.md) | Research into FiveM resource standards and the architecture chosen from it |

---

## MangoNazlet

An ice cream restaurant run as a real business: staff churn product from
ingredients at four stations, stock a display case, serve walk-in customers
through a branded ordering menu, work NPC tickets, run a supply van and a
mobile truck. Sales split between a business account and employee tips, and
payroll comes out of the balance.

**Runs on:** Qbox · QBCore · ESX · standalone — detected at runtime
**Requires:** `ox_lib` · strongly recommends `ox_inventory`, `ox_target`, `oxmysql`

### Install

**Windows:** copy `release/MangoNazlet/` to the server machine and double-click
`Install-MangoNazlet.bat`. It audits the server, copies the resource in and
edits `server.cfg` for you. Then restart.

**Manually, anywhere:** copy the resource to `resources/[jobs]/mangonazlet/` and
add to `server.cfg` — `ox_lib` must come first:

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure qbx_core          # or qb-core / es_extended, or none
ensure mangonazlet       # always after ox_lib
```

Restart. The resource creates its own database tables, registers its job with
your framework and installs its items into your inventory. There is nothing to
edit — no item list, no job list, no coordinates.

### Documentation

- [Full documentation](mangonazlet/README.md) — features, config, exports, security
- [Installation, per framework](mangonazlet/docs/installation.md)
- [Administration](mangonazlet/docs/admin.md) — commands, moving the shop, queries
- [Test matrix](mangonazlet/docs/testing.md) — what was verified and how

### Tests

```bash
cd mangonazlet && lua5.4 tests/harness.lua
```

84 assertions over the real config and the real crafting, melting and
validation code.
