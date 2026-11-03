# game-off-2026

Story-driven co-op voxel horror shooter for Game Off 2026 (theme: SHIFT). Godot 4.7, GL Compatibility. Desktop co-op, single-player web build.

## Layout

- `extension/`: C++ GDExtension (`VoxelWorld`): voxel storage, greedy meshing, raycasts, box collision. `godot-cpp` is a submodule.
- `bin/`: `voxelcore.gdextension` plus the compiled libraries. The Windows library is committed so the project opens without a C++ toolchain; rebuild and commit it whenever you change the C++.
- `scripts/`, `scenes/`, `shaders/`: game code.

## Building the extension

One-time setup:

```sh
git submodule update --init
pip install scons
```

Windows (needs Visual Studio 2022 with the C++ workload):

```sh
cd extension
scons                          # debug build, used by the editor and debug runs
scons target=template_release  # release exports
```

Commit the rebuilt DLL along with your C++ changes. Close the editor before pulling, since it keeps the DLL locked. Rebuilding works while the editor or game is running (the build moves the locked DLL aside); restart the game to pick up the new library.

If the Windows build crashes on load inside godot-cpp after a web build, do a clean rebuild (`scons -c && scons`). Windows and web builds share godot-cpp's generated bindings, and cleaning one platform regenerates them under the other.

## Web export

One-time setup:

- [emsdk](https://emscripten.org/docs/getting_started/downloads.html) **4.0.20**, the version the Godot 4.7.2 web templates report at startup (a mismatch can break loading the extension). The scripts expect it in `C:\dev\Tools\emsdk`; set `EMSDK=...` otherwise.
  ```sh
  git clone https://github.com/emscripten-core/emsdk.git C:/dev/Tools/emsdk
  cd C:/dev/Tools/emsdk && ./emsdk install 4.0.20 && ./emsdk activate 4.0.20
  ```
- Godot 4.7.2 export templates (Editor > Manage Export Templates). Only the `web_*` ones are needed.

Then, from Git Bash in the project root:

```sh
tools/export_web.sh               # builds the wasm extension and exports to build/web/ (debug: add `debug`)
python tools/serve_web.py         # http://localhost:8060 (browsers won't run it from file://)
node tools/web_smoke.mjs out.png  # headless Chrome check: loads the game, prints the console, screenshots
```

The `Web` preset in `export_presets.cfg` uses the no-threads variant with **Extensions Support** on, so it runs on any host without special headers. The editor's own Godot path can be overridden with `GODOT_BIN=...`.

For itch.io: zip the contents of `build/web/`, upload as an HTML game, and set the viewport to 1280x720 with the fullscreen button enabled. The `index.side.wasm` engine module is ~44MB uncompressed; itch serves it compressed.

## Co-op

The main scene is `scenes/menu.tscn`: play solo, host, or join by address. Co-op runs on the desktop build over ENet; web builds are single-player. The host forwards **UDP 24680** on their router, and friends join the host's public IP (LAN players use the LAN address shown on the pause screen).

- `scripts/net/net.gd` (`Net` autoload): hosting, joining, the player roster.
- `scenes/lab.tscn` / `scripts/world/lab.gd`: plays or edits a level. Joiners get the level and a compressed world snapshot, then each peer's player is spawned everywhere. Each peer simulates its own player and streams its movement; the host owns everything else.
- `scripts/net/world_sync.gd`: every voxel edit goes through here. The host applies it and replays it on every peer in order, so worlds stay identical. Gameplay must not edit `VoxelWorld` directly.

Skip the menu from the command line (args after `--`): `--solo`, `--host`, `--join=1.2.3.4`, `--name=Zack`, plus `--edit` (open the level editor) and `--level=name`. Two copies on one machine: start one with `-- --host`, the other with `-- --join=127.0.0.1`.

**Desktop build:** `godot --headless --path . --export-release Windows build/windows/Expendable.exe` (the `Windows` preset; needs the release DLL, built with `scons target=template_release` in `extension/`). Zip `build/windows/` (the exe plus `libvoxelcore...dll`) and send it. Windows Firewall asks the host to allow the game the first time they host; allow it.

`tools/net_test.sh` runs a headless host and client against each other and checks their worlds (and enemies and pickups) end up identical, including a client's explosive shot, a client opening a container and the host cutting the power; `tools/net_test.sh editor_test` does the same for a co-op editing session.

## Levels and the level editor

Levels live in `levels/<name>/` (`level.json`: settings, props and markers, readable and diffable; `voxels.bin`: the terrain and everything built, compressed). Props are stored as placements and stamped into the voxels when play starts. Run from the Godot editor, levels save into `levels/` (commit them); from an exported game they save to the user folder. The spec is `docs/level-editor.md`.

In the menu, pick a level and press **Edit level** (others can join the session and edit with you), or **New level...** (solid rock to carve rooms out of, or empty air). `levels/lab` is the old generated facility, converted once by `scripts/tools/convert_facility.gd`.

The editor is being redesigned (`docs/level-editor-v2.md`); steps 1 (input rules, paper UI), 2 (builder view), 3 (three-click volumes), 4 (rooms as objects, openings), 5 (props that sit on things), 6 (seeing each other) and the 8 polish pass are in (7, the movement, is under Playing). There are two views, and **V** switches between them:

- **Builder view** (the default): an orbit camera from above with the mouse always free; the tools aim through the mouse. Right or middle drag orbits (a right click without dragging is the tool's RMB), Shift+middle drag or WASD pans (Shift fast), the wheel zooms, Q / E turn 45°, F frames the selection, Home the whole level. The **cutaway** hides everything above a height so you can see into rooms in rock: Auto cuts at the ceiling of the room you're looking at, Page Up / Down sets it by hand, C cycles Off / Auto / Manual. Cut rock shows as a darkened cross section. **H** (or the Walls chip) puts the walls down: above knee height, whatever stands between the camera and the room you're looking at is hidden, so you can look in from a low angle, and the cursor aims through it. A faint grid at the snap size shows on the floor under the cursor.
- **Walk view**: first person, for detail work and checking scale. You land where the mouse pointed, facing the same way, and walk with gravity; F toggles flying (Space up, Ctrl down). Click the world to aim with the crosshair.

**Room, Box and Replace** take three clicks: a start corner, the far corner of the floor (the mouse follows the floor's plane, so it never jumps onto a wall), then the height; the box starts with RMB to carve. While sizing, the wheel grows or shrinks the highlighted size (Shift+wheel the other floor side), typing sets it exactly (`2.5` meters or `25v` voxels, Enter keeps it), Tab moves to the next size, RMB or Backspace steps back. The sizes show on the box's edges and in a card at the top. Heights start at the last one used (rooms 3 m). A room started on the cutaway's cut rock digs down to the floor you're looking at, so it lines up with the room beside it.

**Editing together**: everyone sees what everyone else is doing in their color: their cursor, what they're building or resizing, the prop they're about to place and what they have selected. Someone in the builder view shows as a small camera with their name (their body is hidden while they're up there). Whatever someone is moving or resizing is held for them ("Zack is moving this"): nobody else can grab it until they let go, and it's let go if they leave. The name chips at the top say who's in which view; click one to jump to them.

**Esc** backs out one step at a time (a half-drawn box, then the selection, then in the walk view frees the mouse for the panels, then opens the menu). **F1** shows every key in the game. The keys are `EDITOR_KEYS` in `scripts/input_setup.gd`.

| Key | |
|---|---|
| 1-8 | Select, Room, Box, Brush, Replace, Opening, Prop, Marker |
| LMB / RMB | Use the tool (brush: hold, and in the builder view Shift+LMB carves since a right drag orbits). RMB backs out of a step |
| Alt+LMB | Pick the material (or, with the prop tool, a placed prop's type) under the cursor |
| G | Grid snap 1 / 5 / 10 voxels (10 = 1 m) |
| V | Builder view / walk view |
| N | Walk view: free cursor in mid-air (Ctrl+wheel sets its distance), for carving into rock |
| [ ] | Brush size |
| R | Rotate the prop being placed, or the selection |
| M / Ctrl+D / Delete or X | Move / duplicate / delete the selection |
| Ctrl+Z / Ctrl+Y | Undo / redo (your own edits) |
| Ctrl+S | Save (the host saves for everyone) |
| F5 | Play-test; F5 again returns to editing exactly as it was |
| B | Show / hide the catalog (materials, props, markers) |
| Wheel | Builder view: zoom; walk view: fly speed (over a panel it only scrolls the panel) |

The editor's UI uses the paper style from Puzzle Pals (`assets/ui/editor_theme.tres`, `scripts/editor/ui/`, accent recolored dark blue-gray); only the editor uses it. Its input rules are `scripts/editor/editor_input.gd`: buttons never take keyboard focus, Tab never moves focus, panels keep their clicks and the wheel, and while a modal or a text field has the keys, nothing in the world reads them.

- **Markers**: player spawns (by player number), triggers (box volumes that fire for story scripts), intercom speakers, lights (omni / spot, color, energy, range, shadows, flicker, facility or emergency power), horde spawners (see Enemies), the clone vat (respawn point), kill zones, item spots. Each has an id that scripts use.
- **Props** have an asset value (the payroll loses its share as the prop's voxels are destroyed in play) and can be made into doors (slide offset, speed, locked; E opens them in play). Doors can also need a keycard (`door_key`: `red`, `blue`, ...) or power (`door_power`: refuses on backup power).
- **Using props** (E in play, see Interactables below): a prop's `use` field makes it a container, terminal, note, station, generator or glass case. New props start with a sensible `use` for their name.
- **Level settings**: `start_power` (`facility` or `backup`) in `level.json`'s settings, the power state play starts in. There's no panel for settings yet; edit the file.
- **Rooms are objects**: the Room tool's box is the room's inside, lined with its floor, wall and ceiling materials. Select a room (click its floor or a wall, or pick it from the room list the Select tool shows with nothing selected) to resize it with the handles on its walls, ceiling, floor and corners (drag one, or click to pick it up and click again to drop it; the wheel nudges it a grid step), re-line it from the catalog (Floor / Walls / Ceiling), type exact corners, or Move (M), Duplicate (Ctrl+D, a copy with its openings, doors and contents) and Delete it (it fills back in with rock). A resize rewrites only the voxels nobody painted, so detail on walls that stay put survives; where a wall moved away it goes. A new room's lining never walls up a space carved by hand, so rooms join whatever they touch. **Alt+click** with the Room tool inside a carved space (old levels, hand-dug rooms) adopts it as a room without changing a voxel, so it can be resized too.
- **Props sit on things**: a prop goes where you aim by its mount (`PropCatalog.MOUNTS`, by name; the rest stand on the floor). Floor props rest on the surface (aimed at a wall, they stand on the floor with their back to it, facing out), wall props (boards, vent grates) hang flush on walls facing out, door props go into the wall. One overlapping a wall or another prop moves to the nearest free spot (sideways, or up onto it: a crate aimed under a desk lands on the desk). A ghost that would float or has no room is red and won't place, with the reason in a toast. Other props count as something to stand on. R turns a prop (on a wall, from facing out). Spawns, clone vats and horde spawners stand on the floor too. **Check level** (Select tool, nothing selected) lists props that float or sit inside a wall; resizing, moving or deleting a room warns when it leaves some like that.
- **Door props** (`door_single`, `door_double`, `door_security`, `door_blast`, `vent_hatch`, in the catalog's Doors tab; placeholder `.vox` models): aimed at a wall, a one-voxel panel goes into the wall's middle layer on the floor, cuts a doorway through the whole wall, and cuts a pocket beside itself inside the wall that it slides into when opened (`door_offset`, its width along the wall), so the wall looks whole either side. It needs a wall at least 3 voxels thick to hide the pocket; in rock with no room behind, the doorway goes through the room's lining.
- **Openings** (Opening tool, 6): click a wall to cut a doorway (from the floor), window (at a sill height) or hole through it, sized in the inspector. An opening belongs to the wall it's in and moves with it. **Door props cut their own opening** (any prop with "Is a door" on), which follows the door when it moves and goes when it's deleted; the Opening tool never adds a door.

Presence is `scripts/editor/presence.gd` (one per player, the owner sends ~10 times a second when it changes) and the locks are `LevelEdits.locks` (host-kept, sent to everyone).

Code: `scripts/level/` (data, schema, rooms and openings to voxels in `level_structure.gd`, edits with undo, view, play runtime), `scripts/editor/` (tool, builder camera and cutaway, input rules, HUD, paper widgets, prop thumbnails) and `scripts/editor/tools/` (three-click sizing, room handles, room helpers). The voxel side of rooms is `VoxelWorld.apply_structure` in C++.

### Interactables and power

E uses the nearest door or usable prop within 3 m that the crosshair is on; the prompt under the crosshair says what will happen ("[E] Open", "Locked: needs red keycard", "No power"). Any peer asks the host (`LevelPlay.request_use(id)`), which checks and applies it and sends the result to everyone (late joiners too). Code: `scripts/level/level_play.gd` (behaviors, power, keycards), `scripts/interact/interactables.gd` (what's in view, prompts), `scripts/ui/interact_prompt.gd` (prompt and the reader panel).

Prop fields (inspector):

| Field | |
|---|---|
| `use` | `none`, `container`, `terminal`, `note`, `station_medkit`, `station_ammo`, `generator`, `glass_case` |
| `contents` | pickups, comma-separated (`ammo_shotgun,flask_fire,keycard_red`); containers and glass cases |
| `text` | what a terminal or note shows (multi-line) |
| `on_use` | a trigger id fired the first time a terminal is used, or when the generator starts. It can name a trigger marker (its `activates` runs), a spawner, or `horde` |
| `needs_power` | terminal refuses on backup power |
| `charges` | uses a station has (default 3) |
| `station_ammo_type` | ammo bench type (`homing`); empty gives the user's loaded type |
| `finale_seconds` | how long the generator's finale lasts (default 120) |
| `door_key`, `door_power` | see Props above |

| `use` | E does |
|---|---|
| `container` | opens once (`drawer_open`), drops its contents on the floor in front. Default for cabinets, drawer desks, fridges, water coolers, lockers |
| `note` | shows its text (E, Esc or walking away closes it) |
| `terminal` | shows its text (`terminal_beep`) and fires `on_use` once |
| `station_medkit` | heals the user to full, one charge |
| `station_ammo` | 20 rounds of its type, one charge |
| `generator` | on backup power: power goes to `restored`, fires `on_use`, starts `HordeDirector.finale(finale_seconds)` |
| `glass_case` | breaking any of its glass voxels (shooting it) drops its contents once (`glass_break`); E smashes it |

Keycards are party-wide: when anyone picks one up, every door needing it opens for everyone.

**Power** (`LevelPlay.power`): `facility` (normal), `backup` (facility lights and lamp voxels off, emergency lights on; powered doors and terminals refuse) or `restored` (the generator ran; like facility). The host changes it with `LevelPlay.set_power(state)` (`power_changed` on every peer, `power_down` / `power_up` sounds). Levels start on their `start_power` setting.

New props: `terminal`, `cabinet`, `drawer_desk`, `medkit_station` (wall box), `ammo_bench`, `generator`, `glass_case` (wall case), `vent_grate` (soft plastic slats: enemies dig through it, a few shots break it) and `vent_duct` (2 m of metal duct, 1 m wide and 1.2 m tall inside, enough to crouch through).

## Art: MagicaVoxel models

All voxel art lives in `assets/vox/` as MagicaVoxel `.vox` files, and the game reads them at runtime:

- `props/`: furniture and fittings. Levels place them by file name (`props.place("fridge", origin, facing)`).
- `characters/`: the player's body and head.
- `weapons/`: `shroom_shooter.vox`, the gun (view model and the model other players hold). Its `Glow` voxels take the loaded ammo's color; the muzzle is the middle of its front-most voxels.
- `items/`: pickups, one per item name (`medkit.vox`, `ammo_shotgun.vox`, ...). `Glow` voxels take the item's color.
- `enemies/`: enemy bodies, `<kind>_<variant>.vox` (or one `<kind>.vox`). Each enemy picks a variant by its id, the same on every peer.
- `shrooms/`: growth stages `stage<0-4>_<variant>.vox`, plus `stage4_<variant>_eyes.vox` for grown hunters.
- `pieces/`: the old build-mode scrap pieces (reference only).
- `_palette.vox`: one cube per game material. `PALETTE.md` lists them.

The current files are generated placeholders, meant to be replaced or used as templates. Rules for editing:

- **Palette index = game material.** Paint with the palette slots listed in `PALETTE.md`, which come with every file. The slot decides hardness and glow, not just color. Unlisted (dark purple) or recolored slots get mapped to the closest material, with a warning. To add a material, add it to `scripts/voxel/voxel_materials.gd` and re-run the export.
- **Front is MagicaVoxel's front (-Y).** A prop's front faces into the room when placed facing a direction. Up is +Z in MagicaVoxel and +Y in the game.
- **The model box is the prop's frame.** Its min corner sits on the placement origin at floor level, so empty margins are kept on purpose. Characters stand on the bottom center of the box. The head pivots around its center.
- Models of any size work. Anything over 256 voxels is saved split into several models; keep those in one file.

**Live reload:** when the game runs from the Godot editor, saving a `.vox` in MagicaVoxel updates the running game within about a second. Edited props are swapped wherever they were placed: only the old model's voxels that are still intact are removed, so damage is kept. Characters, shrooms, enemies, the gun and pickups re-skin too. In co-op the host's files win and the host pushes prop changes to everyone. A save that doesn't parse keeps the old model. A toast in the bottom left confirms each reload. Exported builds don't watch files.

**Pattern materials**: some palette materials (block wall, large tile, concrete panel, diamond plate, hazard stripes) take each voxel's color from a small image in `assets/patterns/` (up to 32x32, 1 pixel = 1 voxel), tiled across the world, so a wall painted with them in the level editor gets brickwork without coloring voxels by hand. Edit the PNGs freely (live reload covers them too). To add one, add a material with `pattern = "name"` in `scripts/voxel/voxel_materials.gd` and drop `assets/patterns/name.png` in. MagicaVoxel shows these materials as their plain color.

Regenerating placeholders: `godot --headless --path . --script res://scripts/tools/export_vox.gd` writes only missing files, so edited ones are safe. `-- --force` overwrites everything. The generators are in `scripts/world/props.gd` and `scripts/world/prop_catalog.gd` (the name → generator list), plus `ShroomModels`, `EnemyModels`, `GearModels` (weapons and items) and the export script itself.

## Enemies

Code is in `scripts/enemies/` and `scripts/combat/`. Enemies exist only in play (play-testing from the editor too); going back to edit clears them.

- `Enemy` (`enemy.gd`, `scenes/enemy.tscn`): the base. The host simulates it: it follows the voxel world's flow field to the nearest player (one multi-target field for all players, refreshed 5 times a second), digs through soft voxels (planks, dirt) through `WorldSync` when blocked, and attacks in melee range after a short wind-up. Peers get its position and yaw 10 times a second and interpolate. Hit zones (`hit_zones`: name -> local box and crit multiplier) are for crit spots on later enemies. Hits flash it white on every peer; death pops it into debris.
- `BasicShroom` (`basic_shroom.gd`, `scenes/enemies/basic.tscn`): slow (2.5 m/s), 30 health, a 10-damage bite every second. Silent until it's within 6 m of a player, then it chitters.
- `EnemyManager` (the `Enemies` node in `scenes/lab.tscn`): spawns and kills (host), replicates to peers (late joiners get the roster), applies hits from any peer (`request_hit(id, damage, point, kind)`, shooter-authoritative), and sends enemy attacks to the bitten player's own peer. New kinds go in its `KINDS` list (kind -> scene) plus a placeholder generator in `EnemyModels`.
- `Combat`: `ray_hit` (nearest voxel or enemy along a ray), `sphere_hit`, `box_hit`. The shroom shooter uses it (see Weapons and items).
- Status effects: `EnemyManager.request_status(id, name, seconds)` (any peer) -> `Enemy.apply_status(name, seconds)` on the host, which ticks `Enemy.statuses` (name -> seconds left) and sends the active set to every peer so all of them tint the body (hit flashes still show on top). **Burning**: 6 damage/s, jumps to enemies within 1 m every 0.5 s for half the time left, orange with embers. **Poisoned**: 2 damage/s, green. **Frozen**: stopped for 2 s then half speed, takes 1.5x damage, blue. **Raging**: goes for the nearest other enemy instead of players (its normal attack, through the host-side `EnemyManager.damage(id, amount, from)`), 1.5x speed, red.
- `Cloud` (`scripts/weapons/cloud.gd`, `scenes/cloud.tscn`): an area effect, `Cloud.spawn(type, at, radius, seconds)` from any peer (radius / seconds -1 for the type's own). The host owns it and gives its status to the enemies inside every 0.25 s (and, for fire and poison, to the players inside, on their own peer); the other peers only draw it. Types: `fire` (burning pool, 6 s; also burns `SHROOM_*` voxels away through `WorldSync`), `poison` (8 s), `rage` (4 s), `freeze` (an instant burst: frozen 5 s), `spore` (8 s, blinds players inside, from spore shrooms).
- `HordeDirector` (the `Director` node): spawns from **horde spawner** markers. Calm: active spawners trickle in enemies. Horde: `start_horde(count)` bursts from the spawners nearest the players. Finale: see below.

**Finale.** Using the generator (on backup power) calls `HordeDirector.finale(finale_seconds)`: power goes to `restored`, every spawner turns on, trickle rates ramp from the spawner's own `rate` to `finale_rate_multiplier` (4.0) times it, a burst of `horde_size` enemies lands every `finale_burst_interval` seconds (20.0), each `finale_burst_growth` (1.5) times bigger than the last, and `max_alive` caps are `finale_alive_multiplier` (2.0) times higher. All four are exports on the director. The alarm and a finale sting play at the start. The host replicates the countdown once a second, and every HUD shows `GENERATOR m:ss` (pulsing in the last 10 s) with SURVIVE / SHIFT SURVIVED / SHIFT FAILED banners (`HordeDirector.finale_event`). When the timer hits zero: `finale_survived` fires, the trigger id `finale_survived` is emitted on `LevelPlay.triggered`, spawners go back to how they were, living enemies stay, and a note is shown. If every player is dead at once: `finale_failed` and the trigger id `finale_failed`; spawners are restored, every enemy is despawned, power returns to `backup` and the generator can be used again (`LevelPlay.reset_prop`) so the team can retry after respawning at the clone vat.

Enemy kinds (what a spawner's `kinds` can name; scripts in `scripts/enemies/`, scenes in `scenes/enemies/`, models in `assets/vox/enemies/<kind>_<n>.vox`):

| Kind | Behavior | Counterplay |
|---|---|---|
| `fast` | Fast shroom (`fast_shroom.gd`): a thin, forward-leaning runner, 5 m/s (2x basic), 15 health, an 8-damage bite. Within 6 m of its target it zigzags side to side | One or two hits drop it; the shotgun or a flame cone catches the weave |
| `exploding` | Exploding shroom (`exploding_shroom.gd`): a swollen spotted cap, 20 health, 3.6 m/s. Within 2 m of a player it stops, pulses white/orange and hisses (`fuse`, 0.8 s), then blows: a 1.5 m carve and 40 damage to players and enemies within 3 m. Killed before that it still goes off smaller (0.8 m, 15 damage within 1.6 m). Blasts break assets, so they cost payroll | Kill it at range, ideally in a crowd of other shrooms; back off when it flashes |
| `alarm` | Alarm shroom (`alarm_shroom.gd`): rooted, 40 health, a trumpet-shaped cap. Every 0.5 s it checks for a clear line of sight (voxels only) to any living player within 25 m; on one it winds up a scream (`shroom_scream`, 1.5 s red pulse), then starts a horde at the nearest spawners and shows a notice. Rests 30 s after | Stay out of sight (walls block it), or hit it during the wind-up to choke the scream (it retries 4 s later) |
| `giant` | Giant (`giant.gd`): 300 health, 1.2 m/s, about 26x40x26 voxels. Its swing hits every player in a 2 m arc in front for 30 with a strong shove, and gouges soft terrain there. Its antennae are a `crit` zone (5x damage); after 60 damage there they break off on every peer (zone gone, mesh rebuilt) and it staggers 1.5 s | Shoot the antennae off, then keep your distance from the slow swing |
| `ranged` | Ranged shooter (`ranged_shroom.gd`): squat, wide-mouthed, 25 health. Keeps 8 to 12 m from its target (walks in along the flow field, backs straight off when closer), and every 2 s with line of sight spits a slow (12 m/s) lobbed green glob: 12 damage and poisoned 3 s, a green splat where it lands. Globs pass through other shrooms; the host simulates them and the peers draw copies | Close in behind cover and break line of sight; sidestep the slow glob |
| `mommy` | Mommy shroom (`mommy_shroom.gd`): rooted, 200 health, never attacks. Every 4 s it squashes and births a `basic` beside it (`spawn_pop`), up to 6 of its brood alive; dead ones free a slot. When it dies its whole brood pops with it | Push through the brood and focus her down; killing her clears the room |
| `spore` | Spore shroom (`spore_shroom.gd`): a puffball, 25 health, 1.5 m/s chase, weak bite. Within 4 m of a player (at most every 8 s) and on death it vents a `spore` cloud (4 m, 8 s) that **blinds** the players inside: no damage, but their own screen fogs over grey-white (refreshed while inside, 3 s after leaving) | Shoot it before it gets close, so it bursts far away; back out of the cloud |
| `ceiling_cloud` | Ceiling poison cloud (`ceiling_cloud.gd`): a sac hanging from the nearest ceiling above where it spawns, no gravity, 20 health. A player passing within 2.5 m underneath, or any hit, drops it: a 3 m, 8 s `poison` cloud on the floor below and a wet `burst`. If its ceiling voxel is destroyed it falls and bursts where it lands | Shoot it from far off so the cloud forms away from you |
| `tentacle` | Tentacle fungi (`tentacle.gd`): rooted, 120 health, 3.5 m reach. Grabs the nearest free player (`tentacle_grab`) and drags them in at 2 m/s; held within 1 m they take 8 damage/s and can't walk or jump (they can still shoot, melee and throw). Lets go after 40 damage since the grab, when another player melees it, or when it dies; it leaves a released player alone for 2 s | A partner's axe frees you instantly; or pour 40 damage into it |

The tentacle hold is host-authoritative: `EnemyManager.hold_player(player, tentacle_id, anchor)` tells the held player's own peer (`Player.set_held(id or "", anchor)`, `Player.held_by`), and that peer's `_walk` pulls toward the anchor instead of reading movement input; the position streams as usual. Blinded is a player status like poisoned (`Player.apply_status("blinded", s)`); the fog is a fullscreen overlay the local `Player` makes for its own screen (`blind_amount`).

Horde spawner marker fields (level editor inspector):

| Field | |
|---|---|
| `kinds` | enemy kinds, comma-separated (`basic`, `fast`, ... see the table above) |
| `rate` | spawns per minute while active |
| `max_alive` | most of this spawner's enemies alive at once (hordes ignore it) |
| `active` | trickles from the start; off means it waits for a trigger |
| `radius` | spawns land on the floor within this many meters |
| `on_ceiling` | the spawner is for ceiling enemies (`kinds = ceiling_cloud`): they hang from the nearest ceiling voxel above the marker (default off) |

Trigger markers have `activates`: comma-separated spawner ids to turn on, or `horde` to start a horde. Levels saved before these fields existed load with the defaults.

The HUD (`scripts/ui/combat_hud.gd`) shows health in the bottom left, a hit marker on the crosshair when your shot lands, and a red flash when you're hurt.

## Weapons and items

Code is in `scripts/weapons/` and `scripts/items/`.

- `Weapon` (`weapon.gd`, the `Weapon` node in `scenes/player.tscn`): the shroom shooter, one gun with swappable ammo. LMB fires the loaded ammo; **Shift** loads the next type you have ammo for (basic is always there), 1-4 load the first four types directly. Running out drops back to basic. Hits are shooter-authoritative: enemy damage goes to the host through `EnemyManager.request_hit`, terrain damage through `WorldSync`; the other peers see the tracers, flame and projectiles, and the ammo color on your gun.
- `AmmoType` (`ammo_type.gd`): the ammo table, `AmmoType.by_name("shotgun")`. Tune the numbers there.
- `Projectile` (`projectile.gd`, `scenes/projectile.tscn`): moved each physics tick by casting over the whole step, so it never tunnels. The shooter simulates it; other peers run a visual copy that the shooter corrects (bounces, homing) and ends.
- `Inventory` (`scripts/player/inventory.gd`, on the player): ammo per type, flasks, keycards. Cleared when play starts.
- `ItemManager` (the `Items` node in `scenes/lab.tscn`) and `Pickup` (`scripts/items/pickup.gd`, `scenes/pickup.tscn`): the host spawns a pickup for every **item spot** marker when play starts, and enemies drop a random ammo pickup 20% of the time. Walk within 0.8 m to take one; the host decides who got it and removes it everywhere. Going back to edit clears them.

| Ammo | Fires | Damage | Per pickup |
|---|---|---|---|
| Basic | hitscan, chips voxels | 12 | infinite |
| Shotgun | 8 hitscan pellets, short range | 7 each | 12 |
| Flame | 4.5 m cone, 10 ticks a second, sets Burning | 4 a tick | 60 fuel (1 per tick) |
| Explosive | projectile with a slight arc, blast crater | 20 hit + 40 blast | 4 |
| Ricochet | projectile, bounces off voxels 4 times, pierces enemies | 18 each | 15 |
| Homing | projectile, steers to the nearest enemy within 30 degrees | 20 | 10 |
| Poison | projectile with an arc, leaves a 2 m poison cloud for 5 s | 10 | 6 |

- **Melee** (MMB): an axe swing (`assets/vox/weapons/axe.vox`, held lower left while the gun stays) every 0.6 s. A beat into the swing, every enemy in a 1.2 x 1.6 m box reaching 1.6 m ahead takes 35 with a strong knockback, and the voxel you're looking at within reach is chipped (glass and planks break, concrete doesn't). Partners see the swing.
- **Flasks** (RMB throws, **Q** cycles among the types you carry): thrown in an arc (an `AmmoType` named `flask_<type>`, a `Projectile` drawn with the flask's model), every 0.8 s. They shatter into the matching `Cloud`: fire, poison, rage (shrooms fight each other) or freeze.
- Player statuses: standing in a poison cloud poisons you (2 damage/s), in a fire pool burns you (6 damage/s for 3 s); a green / orange vignette shows it. Respawning clears them.

Item spot names (the marker's `item` field): `medkit` (+50 health), `ammo_shotgun`, `ammo_flame`, `ammo_explosive`, `ammo_ricochet`, `ammo_homing`, `ammo_poison`, `flask_fire`, `flask_poison`, `flask_rage`, `flask_freeze`, `keycard_red`, `keycard_blue`, `keycard_green`. Keycards open doors for the whole party (see Interactables and power). Models come from `assets/vox/weapons/` and `assets/vox/items/`.

The HUD shows the loaded ammo and its count in the bottom right, with the type Shift loads next below it, and the selected flask and its count to the left of it.

## Playing

Movement: WASD, Space jump, Ctrl crouch (no sprint), E use (doors and props; closes notes), arrow keys look (backup for remote desktop), T flashlight. Combat: LMB shoot the shroom shooter, Shift change ammo (or 1-4), MMB melee (axe), RMB throw the selected flask, Q cycle flask. Fire, poison, freeze and rage clouds put statuses on shrooms (and fire / poison on you: watch for the vignette). F1 shows the controls. Esc releases the mouse (and pauses in solo play). Debug builds only: F fly.

The controller (`Player._walk`, shared with the level editor's walk view) moves like an arena shooter: ground friction and acceleration (Quake style) instead of easing, coyote time (a jump still works 0.1 s after walking off a ledge), a jump buffer (a jump pressed up to 0.12 s before landing fires on landing, without that landing's friction, so chained hops keep their speed), air control that only adds a little speed along the strafe direction (strafing while turning curves and slowly gains speed, up to `max_air_speed`), shorter hops when jump is let go early, crouching in the air pulling the feet up (crouch-jumps clear higher ledges), and a small camera dip on hard landings. All of it is exported on the Player and tunable.

All sound is synthesized at startup by `scripts/audio/sfx.gd` (no audio assets).

`scenes/test_world.tscn` is a gray-box sandbox kept for the voxel core tests. The old mushroom-farming prototype was removed in the pivot (it's in git history).

Tests (from the project root, with `godot` being the 4.7 editor binary):

```sh
godot --headless --path . --script res://tests/voxel_smoke_test.gd   # voxel core, building pieces, navigation (sandbox)
godot --headless --path . --script res://tests/enemy_test.gd         # enemies: pathing through a door, bites, hits, death, spawners, hordes
godot --headless --path . --script res://tests/finale_test.gd        # generator finale: ramp, survive, wipe and retry
godot --headless --path . --script res://tests/weapon_test.gd        # every ammo type, ricochet, blast carving, homing, Shift cycling, pickups, melee, flasks
godot --headless --path . --script res://tests/status_test.gd        # burning / frozen / raging / poisoned, clouds, fire burning shroom voxels
godot --headless --path . --script res://tests/fire_test.gd          # fire: spreading through flammable voxels, burning out, elemental reactions
godot --headless --path . --script res://tests/roster_b_test.gd      # mommy brood, spore blindness, ceiling poison cloud, tentacle grabs
godot --headless --path . --script res://tests/controller_test.gd    # movement: top speed, stopping, jump height, coyote time, jump buffer, bunny hops, air strafing, crouch-jump
godot --headless --path . --script res://tests/vox_test.gd           # .vox round trips, prop library vs generators
godot --headless --path . --script res://tests/editor_tool_test.gd   # the level editor driven by keys and clicks
godot --headless --path . --script res://tests/editor_input_test.gd  # editor input rules: wheel over panels, typing, Tab, modals, Esc
godot --headless --path . --script res://tests/editor_builder_test.gd # builder view: mouse aiming, orbit vs right click, pan, cutaway, walk view drop-in
godot --headless --path . --script res://tests/editor_volume_test.gd  # three-click volumes: sizing rules, wheel, typing, Tab, back, a room dug from the cut
godot --headless --path . --script res://tests/editor_room_test.gd    # rooms and openings as objects: resize, re-line, detail kept, doors, undo, delete, save
godot --headless --path . --script res://tests/editor_room_tool_test.gd # room tools by mouse: select, handles, Opening tool, move with contents, Room from space
godot --headless --path . --script res://tests/editor_prop_test.gd    # props sit on things: mounts, push-out, red ghosts, level check, a door's doorway and pocket in play
godot --headless --path . --script res://tests/interact_test.gd      # containers, notes, terminals, stations, keycards, glass, generator, power
tools/net_test.sh                                                     # two-process co-op: sync, snapshots, live reload
tools/net_test.sh editor_test                                         # two-process co-op editing, rooms, presence and locks, play-test, save
godot --path . --script res://tests/editor_screenshots.gd -- <dir>   # editor and pattern screenshots (needs a window)
```
