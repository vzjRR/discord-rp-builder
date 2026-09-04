# Administration

Day-to-day running of MangoNazlet: commands, placing the shop, money, staff,
logging and the data behind it.

---

## Commands

All of them require the ace in `Config.Server.adminAce` (`group.admin` by default).

### `/mn:setjob <playerId> <grade>`

Puts a player on the payroll at any grade, including Owner — which the in-game
management menu deliberately cannot do.

```
/mn:setjob 12 5      make player 12 the Owner
/mn:setjob 12 0      demote them to Trainee
```

To fire someone entirely, use the management menu in the office; `setjob` only
sets grades.

### `/mn:place <anchor>`

Moves part of the shop to wherever you are standing and saves it to the
database. This is how you relocate MangoNazlet without editing a file.

```
/mn:place list        print every anchor
/mn:place display     save the display case at your feet
/mn:place reset       clear all saved placements
```

The change applies live to every player and survives resource updates.

**Anchors**

| Anchor | What it is |
|---|---|
| `duty` | Staff clock-in point |
| `register` | Staff side of the till |
| `counter` | Customer side — where the ordering menu opens |
| `customer` | Where the waiting NPC stands |
| `display` | Display case that walk-in customers buy from |
| `churn` | Churn machine (scoops) |
| `assembly` | Assembly bench (cones, sundaes, boxes) |
| `blender` | Blender (milkshakes) |
| `oven` | Waffle oven (cones, brownies) |
| `freezer` | Finished-goods stash |
| `pantry` | Ingredient stash |
| `supply` | Wholesale supplier |
| `office` | Management menu |
| `truck` | Ice cream truck bay |
| `van` | Supply van bay |

Turn on `Config.DebugZones = true` while placing to see the interaction boxes.

Anchors that carry a heading (`truck`, `van`, `customer`) take the direction you
are facing when you save them.

---

## Running the business

### Money

The business balance is the only pot. Sales credit it, payroll and ingredient
purchases debit it, and managers move money in and out from the office.

| Flow | Direction |
|---|---|
| Counter sale | 100% to the business (no employee attached) |
| Ticket / bill / truck sale | 75% business, 25% employee tip (capped at $250) |
| Ingredient purchase | out of the business |
| Truck rental fee | out of the business |
| Payroll | out of the business |
| Supply van run payout | paid to the employee directly, not from the business |

If the balance cannot cover payroll, the cycle is skipped rather than going
negative — unless you set `Config.Economy.allowNegative = true`.

### Stock

Customers can only buy what staff have made and put in the display case. An
empty case sells nothing. That is what keeps the business a business rather
than an infinite vendor.

To run it as a plain shop instead:

```lua
Config.Counter.requireStock = false
```

### Staff

Managers (grade 4+) hire, fire and set ranks from the office, up to grade 4.
Only `/mn:setjob` creates an Owner.

Hiring is face to face — the target must be within 8 metres.

---

## Logging

Everything is written to the `mn_logs` table whether or not Discord is set up.

To send it to Discord, put the webhook in `server.cfg` so it never enters your
repository:

```cfg
set mangonazlet_webhook "https://discord.com/api/webhooks/..."
```

The alternative is `server/settings.lua`, which is a server-only file players
never receive. **Do not put it in `config/config.lua`** — that is a shared
script and is downloaded by every client.

| Switch | Sends |
|---|---|
| `Config.Server.logMoney` | Deposits, withdrawals, ingredient spend, payroll, truck fees |
| `Config.Server.logStaff` | Hires, dismissals, rank changes |
| `Config.Server.logSecurity` | Rejected requests — modified clients, distance failures |
| `Config.Server.logSales` | Every individual sale (off by default; very noisy) |

### Reading the security log

```sql
SELECT created_at, citizenid, detail FROM mn_logs
WHERE action = 'security'
ORDER BY created_at DESC LIMIT 50;
```

Entries here mean a request failed validation. A handful is normal — lag makes
distance checks fail occasionally. A stream of them from one player is not.

---

## Useful queries

```sql
-- business balance
SELECT balance FROM mn_business WHERE shop = 'vespucci';

-- revenue by channel, last 7 days
SELECT channel, COUNT(*) AS sales, SUM(amount) AS revenue
FROM mn_sales WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
GROUP BY channel ORDER BY revenue DESC;

-- best sellers
SELECT item, SUM(quantity) AS units, SUM(amount) AS revenue
FROM mn_sales WHERE item <> '' GROUP BY item ORDER BY units DESC LIMIT 15;

-- staff leaderboard this month
SELECT e.name, e.grade, SUM(s.amount) AS revenue, COUNT(*) AS sales
FROM mn_sales s JOIN mn_staff e ON e.citizenid = s.citizenid
WHERE s.created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY s.citizenid, e.name, e.grade ORDER BY revenue DESC;

-- what is on the shelf right now
SELECT item, quantity FROM mn_stock WHERE shop = 'vespucci' AND quantity > 0;

-- money in and out
SELECT action, COUNT(*) AS times, SUM(amount) AS total
FROM mn_logs WHERE action IN ('deposit','withdraw','supply','payroll','truck_fee')
GROUP BY action;
```

### Adjusting the balance by hand

```sql
UPDATE mn_business SET balance = 50000 WHERE shop = 'vespucci';
```

Restart the resource afterwards — the balance is cached in memory and flushed
once a minute, so a live edit would otherwise be overwritten.

---

## Tuning

| Goal | Change |
|---|---|
| Faster shifts | `Config.Crafting.timeMultiplier = 0.6` |
| Busier counter | lower `Config.Tickets.spawnDelay` |
| Calmer counter | raise it, or `Config.Tickets.enabled = false` |
| No skill checks | `Config.Crafting.skillCheck.enabled = false` |
| Ice cream never melts | `Config.Melting.enabled = false` |
| Bigger employee cut | raise `employeeTip`, lower `businessShare` (must total 1.0) |
| Employees buy their own stock | `Config.Supply.payFrom = 'player'` |
| Shop always open | `Config.Counter.requireStaffOnDuty = false` (default) |
| Shop needs staff present | set it to `true` |
| Rebrand the interface | `Config.UI.theme` |

After changing `config/permissions.lua`, restart the resource — the framework
job is re-registered from it on every start.

---

## Item images

Optional. A missing image shows the inventory's default icon; nothing breaks.

Drop PNGs into `ox_inventory/web/images/` (or `qb-inventory/html/images/`)
using these exact filenames.

**Ingredients**

| Item | Image file | English | Arabic |
|---|---|---|---|
| `mn_milk` | `mn_milk.png` | Milk | حليب |
| `mn_cream` | `mn_cream.png` | Cream | قشطة |
| `mn_sugar` | `mn_sugar.png` | Sugar | سكر |
| `mn_mango` | `mn_mango.png` | Mango | مانجو |
| `mn_strawberry` | `mn_strawberry.png` | Strawberries | فراولة |
| `mn_cocoa` | `mn_cocoa.png` | Cocoa | كاكاو |
| `mn_vanilla` | `mn_vanilla.png` | Vanilla | فانيليا |
| `mn_pistachio` | `mn_pistachio.png` | Pistachio | فستق |
| `mn_flour` | `mn_flour.png` | Flour | طحين |
| `mn_cup` | `mn_cup.png` | Paper Cup | كوب ورقي |
| `mn_topping` | `mn_topping.png` | Toppings | توبينغ |
| `mn_syrup` | `mn_syrup.png` | Mango Syrup | شراب مانجو |

**Scoops**

| Item | Image file | English | Arabic |
|---|---|---|---|
| `mn_scoop_mango` | `mn_scoop_mango.png` | Mango Scoop | كرة مانجو |
| `mn_scoop_vanilla` | `mn_scoop_vanilla.png` | Vanilla Scoop | كرة فانيليا |
| `mn_scoop_chocolate` | `mn_scoop_chocolate.png` | Chocolate Scoop | كرة شوكولاتة |
| `mn_scoop_strawberry` | `mn_scoop_strawberry.png` | Strawberry Scoop | كرة فراولة |
| `mn_scoop_pistachio` | `mn_scoop_pistachio.png` | Pistachio Scoop | كرة فستق |

**Bakery**

| Item | Image file | English | Arabic |
|---|---|---|---|
| `mn_cone` | `mn_cone.png` | Waffle Cone | كون وافل |
| `mn_brownie` | `mn_brownie.png` | Brownie | براوني |

**Desserts**

| Item | Image file | English | Arabic |
|---|---|---|---|
| `mn_cone_single` | `mn_cone_single.png` | Single Scoop Cone | كون كرة واحدة |
| `mn_cone_double` | `mn_cone_double.png` | Double Scoop Cone | كون كرتين |
| `mn_mango_cup` | `mn_mango_cup.png` | Mango Cup | كوب مانجو |
| `mn_sundae` | `mn_sundae.png` | Sundae | صنداي |
| `mn_mango_sundae` | `mn_mango_sundae.png` | Mango Sundae | صنداي مانجو |
| `mn_sandwich` | `mn_sandwich.png` | Ice Cream Sandwich | ساندويتش مثلجات |
| `mn_family_box` | `mn_family_box.png` | Family Box | بوكس عائلي |

**Drinks**

| Item | Image file | English | Arabic |
|---|---|---|---|
| `mn_shake_mango` | `mn_shake_mango.png` | Mango Milkshake | ميلك شيك مانجو |
| `mn_shake_vanilla` | `mn_shake_vanilla.png` | Vanilla Milkshake | ميلك شيك فانيليا |
| `mn_shake_chocolate` | `mn_shake_chocolate.png` | Chocolate Milkshake | ميلك شيك شوكولاتة |
| `mn_shake_strawberry` | `mn_shake_strawberry.png` | Strawberry Milkshake | ميلك شيك فراولة |
