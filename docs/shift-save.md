# Saving the shift

Decided 2026-11-03: one current shift per machine, saved by the host at every clone vat, resumed
from the cubicle's computer as **Continue**. In fiction it is the clone: "Your clone is held at
the Compute stair lobby." The debt carries over, so the payroll ending still bites, and nobody can
save before a fight and reload to dodge a clone fee, because the save is where they would respawn
anyway. Builds on `docs/cubicle-menu.md`.

## 1. What a shift is

A shift is a story play of the laboratory begun from the cubicle (New game, Host a shift, Join a
shift, or Continue). Play-tests from Site maintenance and the launch flags are not shifts and never
save. `Net.session.shift` says which; `Net.session.resume` says the host restores the save when
the level loads (and joiners skip orientation).

The save lives in `user://shift/` (one folder, no slots): `shift.json` and `voxels.bin`. Only the
host writes it. On the web build `user://` is IndexedDB, so the single-player web build saves too.

`shift.json`:

| Key | What |
|---|---|
| `format` | 1 |
| `level`, `level_hash` | The level name and a hash of its `level.json` text plus `voxels.bin` bytes as loaded, so a shift recorded against an older layout is refused, never loaded into the wrong rooms |
| `saved_at` | Unix time |
| `elapsed` | Seconds of play so far (`Lab.shift_seconds`, host, counts while in play) |
| `checkpoint` | `LevelPlay.checkpoint` (the vat marker id) |
| `power`, `keycards`, `armed`, `prop_state`, `doors` | As `LevelPlay._full_state` sends them (`doors`: id -> [origin, open, locked]) |
| `fired` | Trigger ids that have fired (`LevelPlay._fired` keys), so the outbreak, seals and tour lines don't replay |
| `damage_by_name`, `total_damage` | The payroll ledger |
| `deaths` | `Story.deaths` (clones grown by the party), for the bill |
| `director` | `{dormant, spawners: {id: {active, spawned, dead_fired}}}` from `HordeDirector` |
| `items_taken` | Item spot ids already picked up, if `ItemManager` can tell cheaply; else omitted |
| `party` | Player names at save time, for the record |
| `exits` | `Cubicle.exits` is not saved (it is per launch) |

`voxels.bin`: `VoxelWorld.get_data()` compressed the way `LevelData` packs voxels (its own 4-byte
size header plus zstd is fine; `ShiftSave` owns its format).

Enemies alive at the save are not saved: on resume the director starts fresh from the saved spawner
states. Each player's ammo and flasks are not saved: everyone is grown fresh at the vat with the
vat's loadout, which is what a clone is.

## 2. When the host saves

`Lab.save_shift()` (host, play mode, `Net.session.shift`, not the waiting room, not while
`director.finale_active`):

- the checkpoint changes (`LevelPlay.set_checkpoint`),
- a trigger whose actions lock a door fires (the seals),
- the generator starts (`t_m4_generator`), saved just before the finale begins,
- the player leaves from the pause menu (`LabHud` Leave shift calls it before `Net.leave`),
- the window is closed (`NOTIFICATION_WM_CLOSE_REQUEST` in `Lab`).

Resuming during the finale is impossible because nothing saves during it; a save made as the
generator starts restores to the moment before, so the finale restarts at the generator.

The payroll statement (`Ending._show` on the host) clears the save and `Net.session.shift`. Clock
in with a save on file asks once and then clears it (section 4).

## 3. Resuming

`Net.session = {level = "laboratory", mode = "play", shift = true, resume = true}` (solo:
`start_solo` with those extras; co-op: `open_session` with them, then `enter_level`; the waiting
room is skipped on a resume, friends join late by address).

`Lab._ready` on the host, when `Net.session.resume`: after the level loads and `_set_mode_locally
("play")` has stamped the props and started play, `ShiftSave.load()` and:

1. `world.set_data(save.voxels)` and `remesh_all_now()` (destroyed assets stay destroyed, forced
   doors stay open). If `VoxelWorld` reports the change to `LevelPlay._on_voxels_changed`, the
   damage it would count is discarded by the next step.
2. `play.restore(record)`: power (quiet), keycards, armed, prop_state (applying each state
   visually, no sound), doors, checkpoint, fired triggers, the ledger, and a recount of every
   asset's intact voxels from the world as it now is.
3. `director.restore(record.director)` after `director.start()`: dormant and each spawner's
   active / spawned / dead_fired.
4. `items.restore(record.items_taken)` if saved.
5. `shift_seconds = record.elapsed`; `resumed_deaths = record.deaths`, which `Story` reads into
   `deaths` when it attaches.
6. The host's player spawns at `respawn_point()` / `respawn_yaw()` (the checkpoint vat), not the
   spawn marker.

Joiners get the world and the state through the existing late-join path. Newcomers to a play level
with a checkpoint set spawn at the checkpoint vat, not the yard (`_request_entry`), whether the
level was resumed or not: a friend joining an hour in should land with the party.

If `ShiftSave.load()` fails or the layout hash differs, the host falls back to a fresh start and
`notify`s "The shift on file was recorded against an older site layout. Starting fresh.".

## 4. The cubicle's computer

- **SINGLEPLAYER**: CONTINUE comes first and is lit when `ShiftSave.exists()` and the layout
  matches, with its note: "clone held at <room>, <h:mm> on shift" (the owed total is in the record
  but never shown before the statement). Dim with "no record on file" when there is none, or
  "recorded against an older site layout" when the hash differs. Enter starts the resume (solo).
  APPLY FOR JOB (the new game) with a save on file opens **DISCARD**: "A shift is in progress. Your
  clone held at the <room> will be discarded. Fung AI does not refund clones." with DISCARD AND
  CLOCK IN (clears the save, then orientation as usual) and KEEP IT (back).
- **HOST A SHIFT**: a CONTINUE SHIFT item above BEGIN ORIENTATION when a save is on file and the
  layout matches (same note). It opens the session with `shift` and `resume`, level `laboratory`,
  and enters the level at once (no orientation, no waiting room). The roster and addresses show as
  on the host page. BEGIN ORIENTATION with a save on file goes through DISCARD first.
- **JOIN**: a joiner accepted into a session whose dict has `resume = true` skips the orientation:
  the transfer note ("Transfer accepted. Report to Site 3 tonight. A car has been sent.") and
  `Net.enter_level()`.
- **Pause menu**: Leave shift's hint says "Your clone is held at the <room>. Leaving saves the
  shift." (host) or "The host keeps the shift. You can rejoin by address." (peer).
- The room name is the `name` of the room object the vat marker stands in, else the vat id made
  readable.

## 5. Files and ownership

| Owner | Files |
|---|---|
| Capture and restore (Opus) | `scripts/story/shift_save.gd` (new), `scripts/world/lab.gd`, `scripts/level/level_play.gd`, `scripts/enemies/horde_director.gd`, `scripts/items/item_manager.gd` (only if items_taken is cheap), `scripts/story/story.gd`, `scripts/story/ending.gd`, `scripts/net/net.gd`, `scripts/ui/lab_hud.gd`, `tests/shift_save_test.gd` (new), `tests/story_test.gd` |
| The cubicle (Opus) | `scripts/story/cubicle.gd`, `tests/cubicle_test.gd`, `tests/cubicle_shots.gd` |

Nobody touches `scripts/editor/*`, `scripts/level/level_edits.gd`, `scripts/level/level_schema.gd`,
`scripts/level/level_build.gd`, `scripts/input_setup.gd`, `scripts/net/world_sync.gd`,
`tests/editor_builder_test.gd` or `tests/build_*` (another session's uncommitted work), nor
`README.md` / `docs/story.md` (updated once at the end).

### Contracts

`ShiftSave` (`class_name ShiftSave`, static):

```gdscript
const DIR := "user://shift/"
## Tests point this at a scratch folder.
static var dir_override := ""
static func exists() -> bool
## {} when none. Keys: level, vat (marker id), vat_room (readable), elapsed (seconds), clones (int),
## owed (int: damage plus clones at Lines.ENDING.clone_cost), party (Array of names), saved_at (int),
## layout_ok (bool: the level on disk still matches level_hash).
static func summary() -> Dictionary
## The whole record plus voxels, or {} if missing or invalid.
static func load() -> Dictionary
static func write(record: Dictionary, voxels: PackedByteArray) -> Error
static func clear() -> void
```

`Net`: `start_solo(level, mode, extra := {})` and `open_session(port, level, mode, extra := {})`
merge `extra` into `session`; the dict reaches joiners as it does today. `Net.session.shift` and
`Net.session.resume` are read everywhere else.

`Lab`: `func save_shift() -> void` (host; a no-op when it must not save), `var shift_seconds := 0.0`,
`var resumed_deaths := 0`.

## 6. Checks

- `tests/shift_save_test.gd` (headless, host alone, the laboratory level or a small level the
  test builds): play, reach a vat (set the checkpoint), damage an asset, open a door, fire a
  trigger with a lock action, pick up a keycard; `save_shift()`; `ShiftSave.summary()` reports the
  vat's room, the owed total and `layout_ok`; a second Lab loaded with `resume` spawns the player at
  the vat and has the same power, keycards, doors, fired triggers, ledger, spawner states and the
  same world hash; the finale blocks saving; a tampered `level_hash` makes `layout_ok` false and the
  resume fall back to a fresh start with the notice.
- `tests/story_test.gd`: the ending clears the save.
- `tests/cubicle_test.gd`: with a scratch save on file, CONTINUE is lit with its note and NEW GAME
  opens DISCARD; discarding clears the save; with no save CONTINUE is dim; with `layout_ok`
  false it is dim with the layout note; the HOST page shows CONTINUE SHIFT.
- `tools/net_test.sh` still passes.
