# MangoNazlet — Installation

Three steps. Nothing to edit.

---

## 1. Copy the resource

Copy the **`mangonazlet`** folder into your resources directory:

```
your-server/resources/[jobs]/mangonazlet/
```

Keep the folder name exactly `mangonazlet`.

## 2. Add it to server.cfg

Open `server-config/server.cfg.snippet`, and make sure your `server.cfg` starts
these in this order:

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure qbx_core          # or qb-core / es_extended, or omit entirely
ensure mangonazlet       # always after ox_lib
```

## 3. Restart the server

Done. On first start MangoNazlet creates its database tables, registers its job
with your framework, and installs its 30 items into your inventory.

You should see:

```
[mangonazlet] MangoNazlet v1.0.0 starting
[mangonazlet] framework=qbx inventory=ox target=ox database=true
[mangonazlet] job "mangonazlet" registered with qbx_core (6 grades)
[mangonazlet] 30 items written into ox_inventory/data/items.lua (backup kept)
[mangonazlet] ready — 30 products, 18 recipes, balance $25,000
```

---

## Try it

```
/mn:setjob <your server id> 5
```

Head to the 🥭 blip on Vespucci beach, clock in at the staff point, buy
ingredients from the supplier, and start making ice cream.

The full first-shift walkthrough is in
`mangonazlet/docs/installation.md` under **Verifying it works**.

---

## What if something is off?

**The console line `framework=... inventory=... database=...` tells you almost
everything.** If a value looks wrong, it is nearly always resource start order
in `server.cfg`.

| Line you see | What to do |
|---|---|
| `Could not find dependency ox_lib` | Move `ensure ox_lib` above `ensure mangonazlet` |
| `framework=standalone` but you run QBCore | Move your framework above `ensure mangonazlet` |
| `database=false` | Add `ensure oxmysql` above it |
| `could not create tables` | Your MySQL user lacks CREATE — import `database/install.sql` once |
| `could not install items into ox_inventory` | Filesystem is read-only; see `docs/installation.md` |

Full troubleshooting table: `mangonazlet/README.md`.

---

## Contents of this package

```
MangoNazlet/
├── mangonazlet/            ← copy this folder to your server
├── database/install.sql    ← only needed if automatic table creation fails
├── server-config/          ← server.cfg lines to copy
├── INSTALLATION.md         ← this file
└── README.md               ← full documentation
```

**Optional:** item icons. Missing images just show the inventory default and
change nothing. Filenames are listed in `mangonazlet/docs/admin.md`.
