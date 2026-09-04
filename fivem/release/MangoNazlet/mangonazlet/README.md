# 🥭 MangoNazlet

An ice cream and dessert restaurant for FiveM. Staff churn real product from
real ingredients, stock a display case, serve walk-in customers through a
branded ordering menu, work NPC tickets, run a supply van and a mobile truck —
and every cent of it flows through a business account with payroll.

**Install is copy, restart, play.** The resource detects your framework,
inventory, target and database on start and registers its own job and items
against whatever it finds. You do not edit a Lua file, an item list, a job
list, or a coordinate to get it running.

---

## Contents

1. [What it does](#what-it-does)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [How it plays](#how-it-plays)
5. [The job](#the-job)
6. [Products and recipes](#products-and-recipes)
7. [Moving the shop](#moving-the-shop)
8. [Configuration](#configuration)
9. [Commands](#commands)
10. [Exports](#exports)
11. [Security](#security)
12. [Performance](#performance)
13. [Database](#database)
14. [Troubleshooting](#troubleshooting)

---

## What it does

| System | Detail |
|---|---|
| **Job with 6 grades** | Trainee → Scooper → Ice Cream Maker → Supervisor → Manager → Owner, each with its own permissions |
| **Clock in / out** | Duty gates crafting, the till, storage and supply |
| **4 work stations** | Churn machine, assembly bench, blender, waffle oven |
| **18 recipes** | Real ingredients, timed preparation, animations, skill checks on harder items |
| **Display case** | Staff stock it; it is what walk-in customers actually buy from |
| **Customer menu (NUI)** | Branded ordering interface, cart, cash or card, Arabic RTL and English |
| **NPC tickets** | Customers queue at the counter with orders that expire; a ped stands and waits |
| **Employee billing** | Charge a nearby player, they accept or refuse |
| **Supply** | Wholesale ingredients, plus a van run to collection points for extra pay |
| **Mobile truck** | Sell at 7 weighted hotspots at 1.4× price |
| **Business account** | Balance, deposits, withdrawals, hiring, firing, ranks, statistics |
| **Payroll** | Paid from the business balance on a timer |
| **Melting** | Ice cream loses value over time and is worthless once it has melted |
| **Discord logging** | Money, staff changes and rejected requests |
| **Two languages** | Arabic (مانجو نزلت) and English (MangoNazlet), including full RTL |
| **Built from vanilla props** | A visible shop — no MLO, no stream folder, no downloads |
| **No target resource needed** | Every interaction also answers `[E]` |
| **Staffed** | NPC staff behind the counter and customers out front |

---

## Requirements

**Required**

| Resource | Why |
|---|---|
| [`ox_lib`](https://github.com/overextended/ox_lib) | Menus, dialogs, progress bars, skill checks, callbacks |

**Strongly recommended**

| Resource | What you lose without it |
|---|---|
| `ox_inventory` | Freezer and pantry stashes, and the melting system (needs per-slot metadata) |
| `oxmysql` | Persistence — balance, stock and statistics reset on restart |
| `ox_target` | Falls back to `qb-target` automatically |

**Detected automatically, none required:** `qbx_core`, `qb-core`, `es_extended`,
`qb-inventory`, `qs-inventory`, `qb-target`, `qbx_vehiclekeys`, `qb-vehiclekeys`.

With no framework at all the resource still runs: it manages employment itself
and reports money movements as an event your own economy can listen for.

---

## Installation

**1. Copy the folder**

```
resources/[jobs]/mangonazlet/
```

**2. Add it to `server.cfg`** — order matters, `ox_lib` first:

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure qbx_core          # or qb-core / es_extended — or none at all
ensure mangonazlet
```

**3. Restart the server.**

That is the whole installation. On the first start MangoNazlet will:

- create its database tables,
- register the `mangonazlet` job with your framework (with all six grades),
- register its 30 items with your inventory,
- and print exactly what it did:

```
[mangonazlet] MangoNazlet v1.0.0 starting
[mangonazlet] framework=qbx inventory=ox target=ox database=true
[mangonazlet] job "mangonazlet" registered with qbx_core (6 grades)
[mangonazlet] 30 items written into ox_inventory/data/items.lua (backup kept)
[mangonazlet] restarting ox_inventory to load the new items…
[mangonazlet] ready — 30 products, 18 recipes, balance $25,000
```

### About the ox_inventory step

ox_inventory builds its item list once at load and has no runtime API for
adding items, so the only way to install items without asking you to edit a
file is to write them into `ox_inventory/data/items.lua` for you. MangoNazlet
does that carefully:

- everything it writes sits between two clearly marked comment lines,
- your original file is copied to `data/items.mangonazlet.bak` first,
- re-running never stacks duplicates — the old block is replaced,
- nothing outside its own block is touched,
- and ox_inventory is restarted automatically **only while the server is
  empty**, so nobody's open inventory is disturbed. With players online it
  simply waits for the next empty restart.

To turn this off and manage items yourself, set
`Config.AutoInstall.items = false`.

### Item images

Icons are optional — the inventory shows a default when a `.png` is missing and
everything still works. To add them, drop files named after each item into
`ox_inventory/web/images/` (`mn_mango_cup.png`, `mn_shake_mango.png`, …).
`docs/admin.md` lists every filename.

---

## How it plays

```
   supplier ──▶ ingredients ──▶ stations ──▶ finished product
      ▲                                            │
      │                          ┌─────────────────┼─────────────────┐
      │                          ▼                 ▼                 ▼
      │                   display case      NPC tickets        mobile truck
      │                  (walk-in menu)     (counter)          (1.4× price)
      │                          │                 │                 │
      │                          └────────┬────────┴─────────────────┘
      │                                   ▼
      │                    75% business account · 25% employee tip
      └───────────────────────────────────┘
                          payroll, paid from the balance
```

A first shift, end to end:

1. Clock in at the staff point.
2. Buy ingredients from the supplier (paid from the business account).
3. Bake cones at the oven, churn scoops at the machine.
4. Assemble a Mango Sundae at the bench.
5. Stock the display case so customers can buy it.
6. Serve the customer waiting at the counter, or take a ticket at the till.
7. Take the truck to Vespucci Beach and sell the rest at a premium.
8. Clock out. Payroll lands from the business balance.

---

## The job

Job name: **`mangonazlet`** (registered for you).

| Grade | Name | Craft | Till | Storage | Supply | Manage | Pay |
|---|---|:---:|:---:|:---:|:---:|:---:|---|
| 0 | Trainee | ✅ | ❌ | ✅ | ❌ | ❌ | $250 |
| 1 | Scooper | ✅ | ✅ | ✅ | ❌ | ❌ | $400 |
| 2 | Ice Cream Maker | ✅ | ✅ | ✅ | ✅ | ❌ | $600 |
| 3 | Supervisor | ✅ | ✅ | ✅ | ✅ | ❌ | $850 |
| 4 | Manager | ✅ | ✅ | ✅ | ✅ | ✅ | $1,100 |
| 5 | Owner | ✅ | ✅ | ✅ | ✅ | ✅ | $1,500 |

Managers can hire, fire and set ranks up to grade 4 — they cannot create
another owner. Only a server admin can, with `/mn:setjob`.

> **Two paychecks?** Qbox and QBCore pay their own salary from the `payment`
> value on the job. MangoNazlet also runs payroll from the business balance.
> Pick one: either set `Config.Payroll.enabled = false`, or leave it on (the
> business-funded one is the point of the resource).

---

## Products and recipes

Everything is generated from **`config/products.lua`** — items, the customer
menu, the price list, the supplier catalogue and the SQL. Add a flavour there
and it appears everywhere at once.

**Ingredients (12)** — milk, cream, sugar, mango, strawberries, cocoa, vanilla,
pistachio, flour, paper cups, toppings, mango syrup.

**Scoops (5)** — mango, vanilla, chocolate, strawberry, pistachio.

**On the menu (13)**

| Item | Price | Station |
|---|---|---|
| Waffle Cone | $25 | oven |
| Brownie | $60 | oven |
| Single Scoop Cone | $110 | assembly |
| Vanilla Milkshake | $140 | blender |
| Chocolate Milkshake | $150 | blender |
| Strawberry Milkshake | $160 | blender |
| Mango Milkshake | $175 | blender |
| Double Scoop Cone | $175 | assembly |
| Mango Cup | $190 | assembly |
| Ice Cream Sandwich | $210 | assembly |
| Sundae | $240 | assembly |
| Mango Sundae | $290 | assembly |
| Family Box | $520 | assembly |

Recipes asking for `Products.SCOOP_ANY` accept any flavour. The server reserves
explicitly named scoops first, so a recipe wanting *a mango scoop and any
scoop* can never satisfy both from one item.

---

## Moving the shop

The shop is built from props that ship with GTA V — counters, a churn machine,
fridges, a display case, parasols and seating — spawned client-side on the
Vespucci boardwalk, with the name drawn above the counter. It needs **no MLO,
no stream folder and no downloads**, so there is a real, visible restaurant on
a stock server the moment you start it.

Every model was checked against the game's own object list, and one a
particular build lacks is skipped with a warning rather than breaking the rest.
If you have your own MLO, set `Props.enabled = false` in `config/props.lua` to
keep only the interaction points.

To put it somewhere else, you still do not edit a file. In game, as an admin:

```
/mn:place here        move the WHOLE shop to where you stand, facing your way
/mn:place list        show every anchor you can move individually
/mn:place freezer     save just the freezer where you are standing
/mn:place reset       return to the defaults
```

`here` is the one you want. Stand where the counter should be, face the way the
shop should face, and run it: every anchor, station and prop moves as one rigid
body, keeping the layout intact, and it is saved to the database immediately.
Pick a real storefront on the map and the shop takes it over.

**A note on interiors.** The build is exterior. A walkable indoor area with
walls and a door is an MLO — a mapped interior — which is a mapping job, not a
scripting one; props stacked into walls look wrong and players clip through
them. If you install an ice cream MLO, stand inside it and run `/mn:place here`,
then move individual anchors onto its counter and machines. MangoNazlet fits
itself to the interior with no code changes.

Placements are stored in the `mn_locations` table, applied live to everyone,
and survive updates to the resource. The anchors are: `duty`, `register`,
`counter`, `customer`, `display`, `churn`, `assembly`, `blender`, `oven`,
`freezer`, `pantry`, `supply`, `office`, `truck`, `van`.

Set `Config.DebugZones = true` to see the interaction boxes while you place them.

---

## Configuration

`config/config.lua` ships with working production values. The ones worth knowing:

```lua
Config.Locale = 'ar'                    -- 'ar' or 'en'; drives Lua and the NUI

Config.Economy.businessShare = 0.75     -- shop's cut of each sale
Config.Economy.employeeTip   = 0.25     -- employee's cut (must total 1.0)
Config.Economy.openingBalance = 25000

Config.Payroll.enabled = true
Config.Payroll.intervalMinutes = 30

Config.Counter.requireStock = true      -- customers can only buy what staff made
Config.Counter.requireStaffOnDuty = false

Config.Crafting.timeMultiplier = 1.0    -- 0.5 = twice as fast
Config.Crafting.skillCheck.enabled = true

Config.Melting.freshMinutes = 15        -- full value until here
Config.Melting.ruinMinutes = 45         -- worthless past here (0 = never melts)

Config.UI.theme = { mango = '#F5A623', ... }   -- rebrands the whole interface
```

Prices, recipes and grades live in `config/products.lua`, `config/recipes.lua`
and `config/permissions.lua`. Change a grade there and the framework job is
re-registered to match on the next restart.

Server-only settings — the Discord webhook and log switches — are in
`server/settings.lua`, which players never receive.

---

## Commands

| Command | Access | What it does |
|---|---|---|
| `/mn:setjob <id> <grade>` | admin | Put a player on the payroll at any grade |
| `/mn:place <anchor>` | admin | Move part of the shop to where you stand |
| `/mn:place list` | admin | List the anchors |
| `/mn:place reset` | admin | Clear saved placements |

The ace is `Config.Server.adminAce` (`group.admin` by default).

---

## Exports

```lua
exports.mangonazlet:getBalance()          --> number
exports.mangonazlet:addBalance(amount)    --> new balance
exports.mangonazlet:takeBalance(amount)   --> boolean (false when short)
exports.mangonazlet:getStock()            --> { [item] = quantity }
exports.mangonazlet:getStock('mn_sundae') --> number
exports.mangonazlet:getStaffOnDuty()      --> number
```

Example — an hourly business tax:

```lua
CreateThread(function()
    while true do
        Wait(3600000)
        local tax = math.floor(exports.mangonazlet:getBalance() * 0.02)
        if tax > 0 and exports.mangonazlet:takeBalance(tax) then
            print(('MangoNazlet paid $%s tax'):format(tax))
        end
    end
end)
```

---

## Security

The rule the resource is built on: **a client sends identifiers, never values.**
Prices, recipes, payouts and quantities are read from config on the server.

| Control | Where |
|---|---|
| Single gate for identity, duty, grade, distance | `MN.gate()` in `server/security.lua` |
| Rate limit on **all 32** server entry points | per player, per action |
| Prices recomputed from config on every checkout | the basket only names items |
| Ingredients consumed before the progress bar | one set cannot fund two crafts |
| Craft finish must match the craft that started | reservation is the authority |
| Tickets removed before payout | a ticket cannot be served twice |
| Bills re-check distance and funds at payment | not at send |
| Stock taken and refunded atomically | a failed handover refunds in full |
| Managers capped below owner | `Permissions.maxAssignable` |
| Truck binding checks type, model and location | cannot tag another player's vehicle |
| Rejected requests logged with identity | `mn_logs` and Discord |
| Webhook kept out of shared files | `server/settings.lua`, or a convar |

The customer menu is the only part a player can rewrite. It can change what is
*asked for*; it cannot change what is *charged*.

---

## Performance

Idle cost is effectively zero. There is no per-frame loop anywhere: every
client thread either sleeps on a fixed interval or scales its sleep by
distance, and all of them idle at 1–3 seconds when you are away from the shop.

- Interaction zones are registered once and filtered with `canInteract`, so
  clocking in never rebuilds them.
- The business balance and stock are held in memory and flushed once a minute
  rather than written per sale.
- Statistics are the only aggregate queries and are rate limited.
- Every ped, vehicle and blip is cleaned up on resource stop.

---

## Database

Tables are created on start. `sql/install.sql` is a manual fallback only.

| Table | Holds |
|---|---|
| `mn_business` | Business balance |
| `mn_staff` | Employees and lifetime figures |
| `mn_stock` | What is on the shelf to sell |
| `mn_sales` | Every sale, for statistics |
| `mn_logs` | Money, staff changes, rejected requests |
| `mn_locations` | Placements saved with `/mn:place` |
| `mn_standalone_jobs` | Employment when no framework is installed |

```sql
-- top earners this month
SELECT e.name, SUM(s.amount) AS revenue, COUNT(*) AS sales
FROM mn_sales s JOIN mn_staff e ON e.citizenid = s.citizenid
WHERE s.created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY s.citizenid, e.name ORDER BY revenue DESC LIMIT 10;

-- rejected requests this week
SELECT created_at, citizenid, detail FROM mn_logs
WHERE action = 'security' AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
ORDER BY created_at DESC;
```

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Could not find dependency ox_lib` | `ensure ox_lib` must come **before** `ensure mangonazlet` |
| `framework=standalone` but you run QBCore | your framework starts after this resource — reorder `server.cfg` |
| `database=false` | `oxmysql` is not running; add it above `mangonazlet` |
| Items missing from the inventory | check the start-up log; if it says it patched `ox_inventory`, restart it (automatic on an empty server) |
| `could not create tables` | your MySQL user lacks CREATE — run `sql/install.sql` once |
| No interaction appears | you are not employed, or not clocked in. `/mn:setjob <id> 5` |
| Zones are in mid-air | your map differs — use `/mn:place`, see [Moving the shop](#moving-the-shop) |
| No customers arrive | tickets need at least one employee clocked in |
| Freezer will not open | needs `ox_inventory`; other inventories have no stash API |
| Staff get paid twice | your framework also pays a salary — see [The job](#the-job) |

Turn on `Config.Debug = true` for a running commentary of every decision.

---

Part of [`vzjRR/discord-rp-builder`](https://github.com/vzjRR/discord-rp-builder).
Licensed MIT — see `LICENSE.txt`.
