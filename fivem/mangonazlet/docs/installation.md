# Installation

Short version: copy the folder, add one line to `server.cfg`, restart.
Everything else installs itself. This page covers the details per framework and
what to do if something does not line up.

---

## 1. Copy

```
resources/[jobs]/mangonazlet/
```

The folder must be named **`mangonazlet`** — the exports, the stash ids and the
consumable hook in the generated item definitions all reference it by name.

## 2. server.cfg

Order matters. `ox_lib` has to be running before MangoNazlet starts:

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure qbx_core            # or qb-core, or es_extended, or nothing
ensure mangonazlet
```

## 3. Restart

Read the console. A healthy start looks like this:

```
[mangonazlet] MangoNazlet v1.0.0 starting
[mangonazlet] framework=qbx inventory=ox target=ox database=true
[mangonazlet] job "mangonazlet" registered with qbx_core (6 grades)
[mangonazlet] 30 items written into ox_inventory/data/items.lua (backup kept)
[mangonazlet] restarting ox_inventory to load the new items…
[mangonazlet] ready — 30 products, 18 recipes, balance $25,000
```

Every value on the `framework=` line is worth checking:

| Field | Wrong value means |
|---|---|
| `framework=standalone` on a QBCore server | your framework starts *after* this resource — move it above in `server.cfg` |
| `inventory=none` | no inventory detected; crafting will produce nothing |
| `target=ox` but you use qb-target | `ox_target` is also installed; force it with `Config.Target = 'qb'` |
| `database=false` | `oxmysql` is not running — nothing persists |

You can override any of them in `config/config.lua` if detection is wrong.

---

## Per framework

### Qbox (`qbx_core`)

Nothing to do. The job is registered through `exports.qbx_core:CreateJobs()` on
every start, and items go through ox_inventory.

Qbox pays its own salary from the job's `payment` value. MangoNazlet also runs
payroll from the business balance, so staff would be paid twice. Pick one:

```lua
Config.Payroll.enabled = false   -- let Qbox pay
```

or leave it on and accept the framework salary as a small base wage.

### QBCore (`qb-core`)

Nothing to do. Both the job and the items are registered at runtime through
`exports['qb-core']:AddJobs()` and `AddItems()` — no restart of any other
resource is needed.

With `qb-inventory` rather than `ox_inventory` you lose:

- the freezer and pantry stashes (ox stash API only), and
- melting (needs per-slot metadata).

Everything else works. The display case, the customer menu and the whole
business loop are inventory-agnostic.

### ESX (`es_extended`)

The job is written into the `jobs` and `job_grades` tables, and items into
`items` when you are not using ox_inventory. Both need a working database
connection, so make sure `oxmysql` is up.

ESX has no duty system. MangoNazlet keeps duty itself, which means **duty
resets when the player disconnects or the server restarts** — staff clock in
again at the start of a shift. That is deliberate. To remove duty entirely:

```lua
Config.RequireDuty = false
```

### No framework (standalone)

Everything runs except money movement, since there is no economy to move.
Employment is stored in `mn_standalone_jobs` and managed with `/mn:setjob`.

To wire it into your own economy, listen for:

```lua
RegisterNetEvent('mangonazlet:client:money', function(account, amount, reason)
    -- amount > 0 credits the player, amount < 0 debits them
end)
```

---

## The ox_inventory item patch, in detail

ox_inventory reads `data/items.lua` once when it loads and exposes no runtime
API for adding items. The only way to install items without handing you a file
to edit is to write them into that file. MangoNazlet does it as carefully as
the operation allows:

1. Reads the current `data/items.lua`.
2. If its marked block is already there and current, does nothing.
3. Copies the original to `data/items.mangonazlet.bak` (once, never overwritten).
4. Removes any previous MangoNazlet block, so re-runs never stack.
5. Inserts the new block before the table's closing brace.
6. Restarts ox_inventory — **only when the server has zero players**.

Everything it writes is bounded by:

```lua
-- >>> MANGONAZLET AUTO-GENERATED ITEMS — DO NOT EDIT BY HAND <<<
...
-- <<< MANGONAZLET AUTO-GENERATED ITEMS — END >>>
```

Nothing outside that block is read, moved or rewritten.

**To manage items yourself instead:**

```lua
Config.AutoInstall.items = false
```

then add the definitions by hand. Run the server once with the patch enabled
and copy the generated block out of `data/items.lua` — it is exactly what you
would have written.

**If the patch fails** (read-only filesystem, unusual `items.lua` layout), the
console says so and nothing is changed. The job still registers; only the items
are missing.

---

## Item images

Optional. Missing images show the inventory's default icon and change nothing
functionally.

Put PNGs in `ox_inventory/web/images/` (or `qb-inventory/html/images/`) named
after the item. The full list is in [`admin.md`](admin.md#item-images).

---

## Verifying it works

```
/mn:setjob <your id> 5      grant yourself Owner
```

Then walk the loop:

1. Find the 🥭 blip on Vespucci beach.
2. Clock in at the staff point.
3. Supplier → buy milk ×20, cream ×20, sugar ×20, mango ×20, cups ×20, flour ×10.
4. Waffle oven → bake cones.
5. Churn machine → churn mango scoops.
6. Assembly bench → make a Mango Cup.
7. Display case → put it out for sale.
8. Stand on the customer side of the counter → the ordering menu opens.
9. Management office → the sale is in the balance and the statistics.

If every step works, the install is sound.

---

## Uninstalling

1. Remove `ensure mangonazlet` from `server.cfg`.
2. Delete the folder.
3. If you used ox_inventory, either restore `data/items.mangonazlet.bak` or
   delete the marked block from `data/items.lua`.
4. Optionally drop the tables:

```sql
DROP TABLE IF EXISTS mn_business, mn_staff, mn_stock,
                     mn_sales, mn_logs, mn_locations, mn_standalone_jobs;
```

The job stays registered in your framework's own files if you use ESX (it was
written to the database); Qbox and QBCore registrations are runtime only and
vanish on restart.
