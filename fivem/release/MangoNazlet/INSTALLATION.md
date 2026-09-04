# MangoNazlet — Installation

Your server is at `C:\FiveMServer`, so the fastest route is the installer:
it copies the resource in, edits `server.cfg` for you, and first checks that
your server actually has what MangoNazlet needs.

---

## The easy way

1. Put this whole `MangoNazlet` folder anywhere on the server machine
   (Desktop is fine).
2. **Double-click `Install-MangoNazlet.bat`.**
3. Restart your FiveM server.

That is it. The installer defaults to `C:\FiveMServer`, so there is nothing
to type.

### What it does

```
  MangoNazlet installer
  =====================
  [ ok ] Found the resource to install

  Checking the server folder
  --------------------------
  [ ok ] Server folder: C:\FiveMServer
  [ ok ] Resources: C:\FiveMServer\resources
  [ ok ] server.cfg: C:\FiveMServer\server.cfg

  Auditing your server
  --------------------
  [ .. ] 87 resources detected

    Framework : Qbox (qbx_core)
    Inventory : ox_inventory
    Target    : ox_target
    Database  : oxmysql
    ox_lib    : present

  Installing the resource
  -----------------------
  [ ok ] Installed to C:\FiveMServer\resources\[jobs]\mangonazlet
  [ .. ] 36 Lua files in place

  Updating server.cfg
  -------------------
  [ ok ] Backed up to server.cfg.mangonazlet-backup
  [ ok ] Added the ensure lines to the end of server.cfg
```

It is safe to run more than once — running it again updates the resource and
**keeps your `config\` folder**, and it never adds a `server.cfg` line twice.

### Options

Run from PowerShell if your server is somewhere else, or to preview first:

```powershell
# server in a different folder
.\Install-MangoNazlet.ps1 -ServerPath "D:\servers\rp"

# show everything it would do, change nothing
.\Install-MangoNazlet.ps1 -WhatIf

# install into resources\[standalone] instead of resources\[jobs]
.\Install-MangoNazlet.ps1 -ResourcesFolder "[standalone]"
```

### If it stops

The installer refuses to continue in only one case: **`ox_lib` is missing.**
It is the one hard requirement. Get it from
<https://github.com/overextended/ox_lib/releases>, extract to
`C:\FiveMServer\resources\ox_lib`, and run the installer again. Nothing is
changed when it stops.

Warnings (as opposed to that stop) never block the install:

| Warning | Effect |
|---|---|
| No inventory detected | Crafting produces nothing until one is installed |
| `oxmysql` not detected | Works, but nothing persists across restarts |
| No target resource | Install `ox_target`; interactions need one |
| Inventory is not `ox_inventory` | Freezer, pantry and melting unavailable; everything else works |

---

## The manual way

If you would rather not run a script:

1. Copy the **`mangonazlet`** folder into
   `C:\FiveMServer\resources\[jobs]\mangonazlet`
2. Add to `server.cfg`, in this order — `ox_lib` **must** come first:

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure qbx_core          # or qb-core / es_extended, or omit entirely
ensure mangonazlet
```

3. Restart the server.

`server-config\server.cfg.snippet` has these lines ready to copy.

---

## After the restart

Watch the console:

```
[mangonazlet] MangoNazlet v1.0.0 starting
[mangonazlet] framework=qbx inventory=ox target=ox database=true
[mangonazlet] job "mangonazlet" registered with qbx_core (6 grades)
[mangonazlet] 30 items written into ox_inventory/data/items.lua (backup kept)
[mangonazlet] ready — 30 products, 18 recipes, balance $25,000
```

MangoNazlet registers its own job and its own 30 items on that first start.
There is no item list to paste and no job to add.

> **The ox_inventory line.** ox_inventory builds its item list once when it
> loads and has no way to add items at runtime, so MangoNazlet writes them
> into `ox_inventory\data\items.lua` for you — inside a clearly marked block,
> after copying the original to `items.mangonazlet.bak`. It then restarts
> ox_inventory automatically, but only while the server is empty, so nobody's
> open inventory is disturbed. On a fresh restart that is immediate.

### Try it

In game, as an admin:

```
/mn:setjob <your server id> 5
```

Then head to the mango blip on Vespucci beach and clock in at the staff point.
The full first-shift walkthrough is in `mangonazlet\docs\installation.md`.

---

## If something is not right

The `framework=... inventory=... database=...` console line tells you almost
everything. A wrong value there is nearly always resource start order.

| What you see | Fix |
|---|---|
| `Could not find dependency ox_lib` | `ensure ox_lib` must be above `ensure mangonazlet` |
| `framework=standalone` but you run QBCore | Move your framework above `ensure mangonazlet` |
| `database=false` | Add `ensure oxmysql` above it |
| `could not create tables` | Your MySQL user lacks CREATE — import `database\install.sql` once |
| `could not install items into ox_inventory` | See `mangonazlet\docs\installation.md` |
| Nothing happens at the shop | You are not employed — `/mn:setjob <id> 5` |
| Interactions in mid-air | Your map differs — `/mn:place`, see `mangonazlet\docs\admin.md` |

The full troubleshooting table is in `mangonazlet\README.md`.

---

## What is in this package

```
MangoNazlet\
├── Install-MangoNazlet.bat   ← double-click this
├── Install-MangoNazlet.ps1   ← what the .bat runs
├── mangonazlet\              ← the resource itself
├── database\install.sql      ← only if automatic table creation fails
├── server-config\            ← server.cfg lines, to copy manually
├── INSTALLATION.md           ← this file
└── README.md                 ← full documentation
```

Item icons are optional — a missing image shows the inventory's default and
breaks nothing. Filenames are listed in `mangonazlet\docs\admin.md`.
