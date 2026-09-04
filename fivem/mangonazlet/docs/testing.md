# Test matrix

What was verified, how, and what could not be verified in this environment.

**No FiveM server was available while building this**, so nothing below claims
a runtime test happened. The distinction is kept explicit throughout: static
checks and offline logic tests were run and their results are real; anything
requiring a running game server is marked as needing an in-game pass.

---

## Automated — run with `lua5.4 tests/harness.lua`

The harness loads the real config files and extracts the real function bodies
out of `server/inventory.lua`, so it exercises shipping code rather than a copy.

**84 assertions, all passing.**

| Group | Assertions | Covers |
|---|---|---|
| Configuration integrity | 14 | Every station has recipes; every recipe targets a real station, produces a real product and needs real ingredients; every menu and ticket item is makeable; economy split totals 1.0; no duplicate item names; every recipe's ingredients cost less than its output sells for |
| Permissions | 6 | Unknown/negative/nil grades fall back to lowest rather than granting access; trainees cannot use the till; only manager and owner can manage; managers cannot mint owners |
| Input validation | 8 | `MN.int` rejects nil, text, booleans, NaN, ±infinity, out-of-range and negative values; floors decimals; accepts numeric strings |
| Money formatting | 6 | Zero, hundreds, thousands, millions, negatives, nil |
| Ingredient checking | 9 | Sufficient/insufficient stock; wildcard draws across flavours; **explicit + wildcard cannot double-spend one scoop**; all shortfalls reported |
| Ingredient consumption | 6 | Correct amounts taken; no negative quantities; a short inventory is refused without partially charging |
| Melting curve | 9 | Full value until the limit; monotonic decay; never below the floor before ruin; ruined past the limit; missing metadata treated as fresh |
| Localisation | 9 | English and Arabic key parity; direction flags; formatting; missing key returns the key |
| Product helpers | 7 | Label fallback; unsellable price is zero; perishability; catalogue is ingredients only |
| Recipe resolution | 4 | Correct id resolves; **right id at the wrong station is refused**; unknown and non-string ids refused |
| Placement overrides | 6 | Anchors, stations and vehicle bays move; headings preserved; unknown anchors and malformed input ignored safely |

## Automated — static analysis

| Check | Result |
|---|---|
| Lua syntax, all 36 files (`luac5.4 -p`) | pass |
| JavaScript syntax (`node --check`) | pass |
| HTML tag balance | pass |
| CSS brace balance | pass |
| SQL: statement/paren/backtick balance, no destructive verbs | pass |
| Every file on disk is listed in `fxmanifest.lua` | pass |
| Every manifest entry exists on disk | pass |
| No undefined `MN.*` / `Products.*` / `Permissions.*` / `Locations.*` / `Recipes.*` call | pass |
| No client file calls a server-only function, or vice versa | pass |
| Every client callback is registered on the server | pass |
| Every triggered net event is registered on the other side | pass |
| Every NUI callback used by `app.js` exists in Lua | pass |
| Every `SendNUIMessage` action has a JS handler | pass |
| Locale key parity EN/AR, and no unused or missing keys | pass (165 each) |
| No TODO / FIXME / placeholder / lorem / dummy | pass |
| No `console.log` in the NUI | pass |
| No secret committed | pass |
| All 30 item names reconcile across products, recipes and the installer | pass |

## Automated — security audit

Every one of the **32** server entry points was enumerated and inspected for
identity, distance, rate-limit and type validation.

| Property | Result |
|---|---|
| Entry points with a rate limit | 32 / 32 |
| Entry points with an identity or ownership check | 30 / 32 |
| The two without | `:menu` (public price list, distance-gated + throttled) and `:world` (clock report, throttled to 30s, effect bounded by config) — both intentional |
| Monetary values read from a client payload | none, except the staff-entered bill amount, which is bounded by `Config.Billing.maxAmount` and validated |

## Automated — performance audit

| Check | Result |
|---|---|
| Per-frame (`Wait(0)`) loops | none |
| Client threads idling below 1 second when away from the shop | none |
| Entity/blip creators without an `onResourceStop` handler | none |
| Database writes on the sale hot path | none (balance and stock flush once a minute) |

---

## Needs an in-game pass

These cannot be verified without a running FiveM server and are listed so they
can be checked deliberately rather than assumed.

### Installation

| # | Check | Expected |
|---|---|---|
| 1 | Start on Qbox | `framework=qbx`, job registered, items patched into ox_inventory |
| 2 | Start on QBCore | `framework=qb`, job and items registered at runtime, no restart needed |
| 3 | Start on ESX | `framework=esx`, rows appear in `jobs` and `job_grades` |
| 4 | Start with no framework | `framework=standalone`, `/mn:setjob` works |
| 5 | Start twice in a row | Second start reports "already present", writes nothing |
| 6 | Start with players online | ox_inventory restart is deferred, not forced |
| 7 | Start with `ox_lib` missing | Clear error naming the fix; no error spam |
| 8 | Start with `oxmysql` missing | `database=false`, resource still runs in memory |

### Placement

| # | Check | Expected |
|---|---|---|
| 9 | Default coordinates on a stock map | All 15 anchors reachable on foot at Vespucci |
| 10 | `/mn:place freezer` | Saves, applies live for all players, survives restart |
| 11 | `/mn:place reset` | Returns to defaults after restart |

> Anchor 9 is the one most likely to need adjustment. The defaults were chosen
> as an open-air beachfront kiosk precisely so no MLO is required, but exact
> heights on a modified map may differ — `/mn:place` exists for that.

### The shift

| # | Check | Expected |
|---|---|---|
| 12 | Clock in / out | Interactions appear and disappear with duty |
| 13 | Buy ingredients | Business balance falls by the exact catalogue price |
| 14 | Craft with enough ingredients | Progress bar, skill check on difficulty ≥ 2, item delivered |
| 15 | Craft without ingredients | Refused before the progress bar, nothing consumed |
| 16 | Cancel mid-craft | Ingredients lost, no product — the intended penalty |
| 17 | Walk away mid-craft | Craft cancels |
| 18 | Craft at the wrong rank | Locked in the menu, refused on the server |
| 19 | Full inventory | Refused before ingredients are consumed |
| 20 | Stock the display case | Stock rises for every player, live |
| 21 | Buy from the counter menu | Money taken once, item delivered, stock falls |
| 22 | Buy with an empty case | Refused |
| 23 | Buy with no money | Refused, nothing delivered |
| 24 | Serve an NPC ticket | Tip paid, ticket disappears for everyone |
| 25 | Let a ticket expire | Customer leaves, ticket clears |
| 26 | Bill a player who accepts | Money moves once, business credited |
| 27 | Bill a player who declines | Nothing moves |
| 28 | Walk away before paying a bill | Refused on distance |
| 29 | Supply van run | Van spawns, pickups register in order, payout on return |
| 30 | Truck out, sell, store | Fee charged once, 1.4× price at a hotspot, vehicle removed |
| 31 | Sell away from a hotspot | Refused |
| 32 | Melting | Value drops after 15 minutes, inedible after 45 |

### Management

| # | Check | Expected |
|---|---|---|
| 33 | Deposit and withdraw | Balance and personal account both move once |
| 34 | Withdraw more than the balance | Refused |
| 35 | Hire nearby / far away | Works / refused |
| 36 | Promote to grade 4 / attempt grade 5 | Works / refused |
| 37 | Fire an owner | Refused |
| 38 | Fire yourself | Refused |

### Interface

| # | Check | Expected |
|---|---|---|
| 39 | Open in Arabic | Fully RTL, cart on the correct side |
| 40 | Open in English | LTR |
| 41 | Escape and the close button | Both release focus |
| 42 | Stock changes while open | Menu updates without reopening |
| 43 | Browser console | No errors |
| 44 | 1920×1080 and ultrawide | Layout holds |

### Adversarial

These are the ones worth actually attempting with a modified client.

| # | Attempt | Expected |
|---|---|---|
| 45 | `craftFinish` with no `craftStart` | Refused and logged |
| 46 | Start a cheap recipe, finish an expensive one | Refused on the reservation mismatch |
| 47 | Craft from across the map | Refused on distance |
| 48 | Checkout with an edited price in the NUI | Server price used; the edited figure is ignored |
| 49 | Checkout with a negative or huge quantity | Refused |
| 50 | Checkout with an item that is not on the menu | Refused |
| 51 | Serve the same ticket twice | Second attempt refused |
| 52 | Answer someone else's bill | Refused and logged |
| 53 | Spam any callback | Rate limited |
| 54 | Register another player's vehicle as your truck | Refused on type/model/distance |
| 55 | Sell an ingredient as a product | Refused |
| 56 | Promote yourself | Refused |

Every rejection above should appear in `mn_logs` with `action = 'security'`.
