## The Cave — Auto-Dig

Removes the repetitive clicking that manual digging in [The Cave](https://mods.factorio.com/mod/the-cave)
requires, without changing the pace of the game in any way.

**This is not a speed-up mod.** Everything this mod does is exactly what a manual click
already does — it just saves you from doing the click yourself, over and over, for hours:

- **Mining speed is unchanged.** Auto-dig computes the same effective mining speed the game
  uses for hand-mining — base character mining speed, multiplied by your character's mining
  speed bonus, multiplied by your force's manual-mining-speed research bonus — and waits
  exactly that long between digs. It never mines faster than you could by holding the mouse
  button down yourself.
- **Reach is unchanged.** Every target is checked with the same reach-distance rule the game
  enforces on manual mining. Nothing is dug from further away than you could reach by hand.
- **Every dig consequence is unchanged.** Digging goes through the same mining call a manual
  click uses, so resource yields, cave-ins/room generation, enemy spawns, and any other
  consequence The Cave attaches to a dig trigger exactly as if you had clicked the rock
  yourself. Nothing is skipped, and nothing extra is granted.

### What it does

- **Cursor mode** — point at a rock or a pile of rubble and it keeps digging it, like holding
  the mouse button down on it.
- **Forward mode** — hold a movement key into the wall and it digs that direction, one layer
  at a time, as the wall retreats in front of you. Tunnel width is 1 or 3 tiles; a 3-wide
  tunnel clears the sides first, so the corridor stays walkable.
- **Two safety gates**, so it stops itself instead of digging you into trouble while your
  attention is on something else:
  - **Collapse-stress gate** — stops as soon as nearby rock stress approaches The Cave's
    collapse threshold, and tells you the measured value against the configured limit.
  - **Enemy gate** — stops the moment the number of enemies near you increases, so it never
    digs straight into a nest.
- A GUI panel (and two hotkeys — toggle, cycle mode) controls all of the above per player.
  Both gates and the tunnel width can be tuned per player; the collapse-stress limit is a
  server-wide setting.

### Requirements

Requires [The Cave](https://mods.factorio.com/mod/the-cave) (2.7.0 or later) and Factorio 2.0.

### Notes for server admins

The collapse-stress gate calls into one of The Cave's internal debug/benchmark hooks, which
is not a guaranteed public API. If a future version of The Cave removes or renames it, this
mod detects that, prints a one-time warning, and keeps digging with just the enemy gate — it
never crashes or silently mines through a gate that stopped working.
