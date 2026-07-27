# hanshino-cave-autodig

Automates digging in [The Cave](https://mods.factorio.com/mod/the-cave) at exactly manual
speed. This document exists so the next person (possibly future-you) does not have to
re-derive the dead ends this project already walked into. Read it before changing anything,
especially the mining-speed formula and the mining mechanism.

## What problem this solves

The Cave's core loop is: walk up to a rock/rubble tile, click it, wait for it to mine, repeat
— for as long as you want to dig a tunnel or clear an area. That is a lot of repetitive
clicking with no decision content. This mod automates exactly that click, nothing more: it
does not mine faster, reach further, or generate different outcomes than clicking would. See
`portal-description.md` for the player-facing version of this guarantee.

## Why `mine_entity` is the only viable mechanism

Two other approaches look plausible and are both dead ends. This was the single most
expensive thing to establish in this project, so the evidence is recorded here in full.

**Bots cannot dig the wall.** The-cave's frontier rock is script-spawned and explicitly marked
non-deconstructable:

```
prototypes/rock.lua:6
rock.flags = { "placeable-neutral", "not-deconstructable" }
```

There is no deconstruction-order path around this flag. A bot-based "auto-dig" is not
possible against `diggy-rock` at all.

**Damage-based destruction (turrets, explosives, anything that isn't a direct player click)
yields nothing.** The-cave's dig handler decides what a destroyed rock produces based on how
it died:

```
control.lua:484-501
local player_mined_directly = event.name == defines.events.on_player_mined_entity
    and event.player_index ~= nil
local player_mined_rock_directly = player_mined_directly
    and entity.name == "diggy-rock"
local dig = {
    ...
    -- Direct player mining is the only action allowed to resolve seeded
    -- dig outcomes. Non-player destruction (especially Demolisher movement)
    -- is geometry-only: it removes the rock in its path but cannot generate
    -- caverns, rooms, enemies, resources, treasure, threats or discoveries.
    direct_player_mining = player_mined_directly,
    allow_hostile_spawns = player_mined_rock_directly,
    allow_room_generation = player_mined_rock_directly,
    allow_dig_outcomes = player_mined_rock_directly,
}
```

`allow_dig_outcomes` (resources, caverns, rooms, spawns, discoveries — everything a real dig
produces) is only ever `true` when the rock died via `on_player_mined_entity` with a real
`player_index`. Any other kind of removal — including the maintainer's own scripted-digging
simulation:

```
scripts/sim.lua:247
entry[1].die(s.force_name)
```

— takes the geometry-only branch: the rock disappears, but no resources, no cavern, nothing.
An "auto-dig" built on damaging or otherwise destroying the entity (turret fire, explosives,
`entity.destroy()`, etc.) would silently produce a tunnel with zero yield. This is why the
entire mod is built around calling `LuaEntity::mine_entity` from real player code — it is the
only removal path that sets `player_mined_rock_directly = true`.

## The multiplicative mining-speed formula

`mining_speed_for` in `src/control.lua` computes:

```lua
base * (1 + player.character_mining_speed_modifier)
     * (1 + player.force.manual_mining_speed_modifier)
```

This is **multiplicative**, not additive, confirmed by two independent sources:

- `LuaForce.manual_mining_speed_modifier`'s own API doc: "actual mining speed will be
  multiplied by `1 + manual_mining_speed_modifier`".
- The wiki's hand-mining formula: `(1 + Force Modifier) * (1 + Character Modifier) *
  (Character mining speed) / Mining time`.

Writing it as `(1 + character_bonus + force_bonus)` is only correct when one of the two
bonuses is exactly zero — an early draft of this mod did exactly that, and it was caught and
fixed during Task 7's review before it shipped. With both bonuses non-zero the additive form
underestimates effective speed (auto-dig would be slower than manual mining), and the same
error direction applies to any future combination where more than one modifier is active. Do
not "simplify" this back to addition — it looks harmless and is wrong.

## `logic.lua` / `control.lua` layering, and the zero-Factorio-dependency test

`src/logic.lua` contains every decision function (direction math, forward-candidate ordering,
cooldown math, the safety-gate decision in `blocked_reason`) as pure functions: no `game`,
`storage`, `settings`, `defines`, `prototypes`, `remote`, or `script`. `src/control.lua` is
the thin event-wiring layer that turns real Factorio state into the plain tables `logic.lua`
consumes, and turns its plain-table answers back into API calls.

The reason this split exists: **a headless Factorio server has no player character**, so
`walking_state`, `can_reach_entity`, `mine_entity`, and the GUI event handlers cannot be
exercised outside a real client at all — there is no way to unit-test them. Pulling every
decision that doesn't need those things out into a dependency-free module means that logic can
run under a plain Lua interpreter (`test/run.sh` runs it in `nickblah/lua:5.2` — no Factorio
engine involved) with a real, fast unit test suite (81 assertions as of this task), instead of
being untestable until someone plays the game.

This boundary is enforced as a test, not just a convention: the last block of
`test/test_logic.lua` strips comments out of `src/logic.lua`'s own source and scans it for the
seven forbidden global names. If anyone ever adds a `game.*` or `storage.*` call to
`logic.lua`, this test fails immediately — instead of the whole module silently becoming
untestable outside the running game with no error telling you why.

## `debug_max_stress`: an unstable, unofficial dependency

The collapse-stress gate calls into The Cave via
`remote.call("diggy-v1", "debug_max_stress", ...)`. This is registered in the-cave's
`control.lua` under the comment:

> Headless test hooks (used by the maintainer's automated benchmarks).

That is not a promise of a stable public API — it is the maintainer's own test/benchmark
plumbing that this mod happens to be able to call too. It can be renamed, restructured, or
removed in any future release of The Cave with no deprecation warning, and there is nothing
this mod can do to prevent that.

Degradation behavior (`stress_at` / `try_dig` in `src/control.lua`):

1. Before calling, check that `remote.interfaces["diggy-v1"]` and its `debug_max_stress`
   entry both still exist.
2. Wrap the actual `remote.call` in `pcall` regardless — an interface can exist with an
   incompatible signature.
3. If either check fails, print a **one-time-per-session** warning
   (`autodig.probe-unavailable`, gated on `storage.autodig.probe_warned`) and drop only the
   collapse-stress gate for that dig (`gate_collapse = false`). Auto-dig keeps running; it
   simply stops checking collapse risk until the mod is updated to match whatever The Cave
   changed.
4. The enemy gate does not depend on this interface at all and is unaffected either way.

The one thing this mod must never do is let a broken/renamed remote interface turn into an
uncaught Lua error — that would either silently disable auto-dig with a cryptic error popup,
or (worse) crash the whole mod's event handlers for every player. Hence the interface-presence
check *and* the `pcall`, not just one or the other.

## Duplicate-locale-section trap

Both `src/locale/en/autodig.cfg` and `src/locale/zh-TW/autodig.cfg` must each contain exactly
**one** `[autodig]` section (and one of each other section). Factorio's locale loader builds a
property tree per language file where section names are keys at ROOT; a section name that
appears twice in the same file makes the client reject the *entire* language file for that mod
with `Failed to load locale: Duplicate key "..." in property tree at ROOT` — this happened for
real in the sibling `locale-mod` project (see its `README.md` / `CLAUDE.md`) and shipped
undetected for three releases.

It cannot be caught by this project's headless load test (`package.sh`'s `docker run
factoriotools/factorio ... --create`): **a headless server never parses non-`en` locale
files at all**, so a load test proves the prototypes and dependencies are fine and proves
nothing about locale validity. When adding a new player-facing string, always extend the
existing `[autodig]` section — never open a second section with the same name, in either
language file.

## Why `package.sh` copies files by whitelist, not `cp -r`

`package.sh` lists the exact files that go into the zip (`src/info.json src/data.lua
src/settings.lua src/control.lua src/logic.lua src/gui.lua` plus the two locale directories)
instead of recursively copying `src/`. This mirrors a near-miss in the sibling `locale-mod`
project, where a stray `.omc/` tool-state directory got swept into a build by `cp -r` and
nearly got published to the public mod portal. Any new source file must be added to this
whitelist explicitly — an unlisted file is silently left out of the zip, which is the safe
failure direction, but also means "I added a file and it's not in the build" is usually a
forgotten whitelist entry, not a bug in `package.sh`.

## Console/RCON injection: considered and rejected

Before committing to a mod, injecting `script.on_nth_tick` via RCON directly into the running
server (no mod install, no client download) was evaluated as an alternative. Measured on a
throwaway Factorio 2.0.77 server:

- `script.on_nth_tick` registered from the console *does* fire (observed 8 times in an 8
  second window).
- `storage` is readable and writable from console-injected code, and persists in the save.
- **The handler is lost on every save/load.** There is no way to make console-injected code
  survive a server restart; it would have to be manually re-injected every single time.
- **An `error()` thrown inside the handler kills the server outright**
  (`Quitting: multiplayer error.`) — a single bad edit takes down the whole game for everyone
  connected, with no isolation.
- Measurement trap worth remembering if this is ever re-evaluated: a headless server with no
  connected players auto-pauses, which makes `on_nth_tick` appear not to fire at all (a false
  negative). The fix is `"auto_pause": false` in `server-settings.json`; there is no
  `--no-auto-pause` command-line flag.

This mod was chosen over injection because (a) clients on this server already auto-download
mods from the portal, so per-player cost is close to zero, erasing injection's main
advantage, and (b) the mod path has a pre-flight load test (`package.sh`) that catches broken
prototypes/dependencies before anything reaches the server; there is no equivalent pre-flight
check for injected console code, which fails at runtime with no safety net.

## Testing, packaging, and publishing

```bash
./test/run.sh        # logic.lua's unit tests, in Docker (nickblah/lua:5.2 — matches
                      # Factorio 2.0's embedded Lua 5.2.1; testing under 5.4 would let
                      # 5.3+-only syntax like `//` or bitwise operators pass silently,
                      # and it would only fail once it hit the real game)

./package.sh          # runs test/run.sh, builds dist/<name>_<version>.zip from the
                      # whitelist above, then a headless load test (prototypes/
                      # dependencies only — no runtime behavior; see the Docker
                      # entrypoint note below)

./package.sh --install  # also copies the zip into ../_data/mods/ (chown 845).
                         # Needs ./restart.sh on the server to take effect.

./publish.sh --init            # preview: what a first-ever publish would send
./publish.sh --init --yes      # actually publish (only succeeds once, ever)
./publish.sh --release --yes   # upload a new version (bump info.json's version first)
./publish.sh --details --yes   # update only the portal page copy
```

`publish.sh` defaults to a dry run — nothing is sent without `--yes`. Publishing a mod name is
public and permanent (a taken name can never be renamed), so this default is intentional; do
not "streamline" it away.

### Docker entrypoint gotcha (load test)

`package.sh`'s load test runs:

```
docker run --rm --entrypoint /opt/factorio/bin/x64/factorio \
    -v "$LOADTEST:/mods" factoriotools/factorio:2.0.77 \
    --mod-directory /mods --create /tmp/loadtest.zip
```

The explicit `--entrypoint` is required, not optional convenience: the image's default
`/docker-entrypoint.sh` does not replace itself with the container's CMD — it *appends* CMD as
extra arguments after its own server-start invocation, and it runs as uid `845` (the image's
`factorio` user), `chown`-ing the mounted directory to that uid before doing anything else.
That collides with a host-mounted mods directory (owned by the host user), producing
`Permission denied`. Pointing `--entrypoint` straight at the `factorio` binary skips all of
that setup and runs a clean, one-shot `--create`.

## Manual verification checklist (safety gates)

These are the checks a human needs to run at a real Factorio client after `./package.sh`
installs this build. None of them can be automated — the load test only proves prototypes and
dependencies resolve, not runtime behavior, since a headless server has no player character.

1. On an already-cleared, open area near a wall, turn on auto-dig. It should dig only a few
   tiles before printing "應力 X.XX（安全上限 3.00）" ("rock stress X.XX (safety limit 3.00)")
   and stopping.
2. Cross-check the number by hand:
   `/c game.player.print(remote.call("diggy-v1","debug_max_stress", game.player.surface.index, -4,-4,4,4))`
   — confirm the mod's reading is in the same ballpark.
3. Dig a normal single-tile-wide tunnel through ordinary rock — it should **not** be blocked
   (a 1-tile corridor's stress should sit well below 3.0). If it keeps getting blocked, the
   `STRESS_PROBE_HALF` sampling box (currently ±4, a 5x5 area) is likely picking up an existing
   large open cavity nearby; try narrowing it to ±2 and re-test.
4. Dig until a biter/spawner/turret appears nearby — auto-dig should print "附近敵人增加了"
   ("more enemies nearby") and stop.
5. Clear out the enemies near you and turn auto-dig back on — it should resume digging
   normally (this proves the enemy-count baseline tracked the decrease, not just increases).
6. **Simulate The Cave changing its interface:** run
   `/c remote.remove_interface("diggy-v1")`, then keep digging. Expected: exactly one warning
   print, then digging continues normally with the enemy gate only — **no Lua error window**
   may appear. This test permanently breaks The Cave on whatever save it's run on
   (`diggy-v1` is gone for the rest of that session); use a throwaway save and do not save
   over anything you care about afterward.

See the task's brief (`.superpowers/sdd/2026-07-27-cave-autodig-v1/task-10-brief.md`, Step 3)
for the original wording; the six items above are equivalent and self-contained.

## v2 backlog

- **Mode 3 — locked-facing dig**: dig in a direction fixed by the player, independent of
  which way they happen to be walking right now.
- **Mode 4 — area-select dig with pillar reservation**: player marks out a region; auto-dig
  clears it while deliberately leaving a grid of support columns standing (relevant once
  The Cave's collapse system is in play over a large cleared area, not just a single tunnel).

Neither mode is designed yet beyond the name above — that design work is out of scope for this
task.
