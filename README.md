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

`tools/net_test.sh` runs a headless host and client against each other and checks their worlds (and enemies) end up identical; `tools/net_test.sh editor_test` does the same for a co-op editing session.

## Levels and the level editor

Levels live in `levels/<name>/` (`level.json`: settings, props and markers, readable and diffable; `voxels.bin`: the terrain and everything built, compressed). Props are stored as placements and stamped into the voxels when play starts. Run from the Godot editor, levels save into `levels/` (commit them); from an exported game they save to the user folder. The spec is `docs/level-editor.md`.

In the menu, pick a level and press **Edit level** (others can join the session and edit with you), or **New level...** (solid rock to carve rooms out of, or empty air). `levels/lab` is the old generated facility, converted once by `scripts/tools/convert_facility.gd`.

Editor controls (fly with WASD, Space up, Ctrl down, Shift fast):

| Key | |
|---|---|
| 1-7 | Box, Room, Brush, Replace, Prop, Marker, Select |
| LMB / RMB | Use the tool (box: LMB two corners fills, RMB carves; brush: hold) |
| Alt+LMB | Pick the material (or, with the prop tool, a placed prop's type) under the cursor |
| Q | Cancel a half-drawn box or a move |
| G | Grid snap 1 / 5 / 10 voxels (10 = 1 m) |
| V | Free cursor in mid-air (Ctrl+wheel sets its distance), for carving into rock |
| [ ] / B | Brush size / sphere or cube |
| R | Rotate the prop being placed, or the selection |
| M / Ctrl+D / X | Move / duplicate / delete the selection |
| Ctrl+Z / Ctrl+Y | Undo / redo (your own edits) |
| Ctrl+S | Save (the host saves for everyone) |
| F5 | Play-test; F5 again returns to editing exactly as it was |
| Wheel | Fly speed |
| Tab | Free the mouse to use the side panel (materials, props, marker types, the selection's properties) |

- **Markers**: player spawns (by player number), triggers (box volumes that fire for story scripts), intercom speakers, lights (omni / spot, color, energy, range, shadows, flicker, facility or emergency power), horde spawners (see Enemies), the clone vat (respawn point), kill zones, item spots. Each has an id that scripts use.
- **Props** have an asset value (the payroll loses its share as the prop's voxels are destroyed in play) and can be made into doors (slide offset, speed, locked; E opens them in play).
- **Room tool**: the corners mark the inside of the room. In rock levels the lining only recolors rock, so a new room opens into any room it touches.

Code: `scripts/level/` (data, schema, edits with undo, view, play runtime) and `scripts/editor/` (tool, HUD, prop thumbnails).

## Art: MagicaVoxel models

All voxel art lives in `assets/vox/` as MagicaVoxel `.vox` files, and the game reads them at runtime:

- `props/`: furniture and fittings. Levels place them by file name (`props.place("fridge", origin, facing)`).
- `characters/`: the player's body and head.
- `enemies/`: enemy bodies, `<kind>_<variant>.vox` (or one `<kind>.vox`). Each enemy picks a variant by its id, the same on every peer.
- `shrooms/`: growth stages `stage<0-4>_<variant>.vox`, plus `stage4_<variant>_eyes.vox` for grown hunters.
- `pieces/`: the old build-mode scrap pieces (reference only).
- `_palette.vox`: one cube per game material. `PALETTE.md` lists them.

The current files are generated placeholders, meant to be replaced or used as templates. Rules for editing:

- **Palette index = game material.** Paint with the palette slots listed in `PALETTE.md`, which come with every file. The slot decides hardness and glow, not just color. Unlisted (dark purple) or recolored slots get mapped to the closest material, with a warning. To add a material, add it to `scripts/voxel/voxel_materials.gd` and re-run the export.
- **Front is MagicaVoxel's front (-Y).** A prop's front faces into the room when placed facing a direction. Up is +Z in MagicaVoxel and +Y in the game.
- **The model box is the prop's frame.** Its min corner sits on the placement origin at floor level, so empty margins are kept on purpose. Characters stand on the bottom center of the box. The head pivots around its center.
- Models of any size work. Anything over 256 voxels is saved split into several models; keep those in one file.

**Live reload:** when the game runs from the Godot editor, saving a `.vox` in MagicaVoxel updates the running game within about a second. Edited props are swapped wherever they were placed: only the old model's voxels that are still intact are removed, so damage is kept. Characters, shrooms and enemies re-skin too. In co-op the host's files win and the host pushes prop changes to everyone. A save that doesn't parse keeps the old model. A toast in the bottom left confirms each reload. Exported builds don't watch files.

**Pattern materials**: some palette materials (block wall, large tile, concrete panel, diamond plate, hazard stripes) take each voxel's color from a small image in `assets/patterns/` (up to 32x32, 1 pixel = 1 voxel), tiled across the world, so a wall painted with them in the level editor gets brickwork without coloring voxels by hand. Edit the PNGs freely (live reload covers them too). To add one, add a material with `pattern = "name"` in `scripts/voxel/voxel_materials.gd` and drop `assets/patterns/name.png` in. MagicaVoxel shows these materials as their plain color.

Regenerating placeholders: `godot --headless --path . --script res://scripts/tools/export_vox.gd` writes only missing files, so edited ones are safe. `-- --force` overwrites everything. The generators are in `scripts/world/props.gd` and `scripts/world/prop_catalog.gd` (the name → generator list), plus `ShroomModels`, `EnemyModels` and the export script itself.

## Enemies

Code is in `scripts/enemies/` and `scripts/combat/`. Enemies exist only in play (play-testing from the editor too); going back to edit clears them.

- `Enemy` (`enemy.gd`, `scenes/enemy.tscn`): the base. The host simulates it: it follows the voxel world's flow field to the nearest player (one multi-target field for all players, refreshed 5 times a second), digs through soft voxels (planks, dirt) through `WorldSync` when blocked, and attacks in melee range after a short wind-up. Peers get its position and yaw 10 times a second and interpolate. Hit zones (`hit_zones`: name -> local box and crit multiplier) are for crit spots on later enemies. Hits flash it white on every peer; death pops it into debris.
- `BasicShroom` (`basic_shroom.gd`, `scenes/enemies/basic.tscn`): slow (2.5 m/s), 30 health, a 10-damage bite every second. Silent until it's within 6 m of a player, then it chitters.
- `EnemyManager` (the `Enemies` node in `scenes/lab.tscn`): spawns and kills (host), replicates to peers (late joiners get the roster), applies hits from any peer (`request_hit(id, damage, point, kind)`, shooter-authoritative), and sends enemy attacks to the bitten player's own peer. New kinds go in its `KINDS` list (kind -> scene) plus a placeholder generator in `EnemyModels`.
- `Combat`: `ray_hit` (nearest voxel or enemy along a ray), `sphere_hit`, `box_hit`. The placeholder rifle uses it: enemy hits do damage, voxel hits carve as before.
- `HordeDirector` (the `Director` node): spawns from **horde spawner** markers. Calm: active spawners trickle in enemies. Horde: `start_horde(count)` bursts from the spawners nearest the players. Finale: `finale(duration)` is a stub that ramps a horde and emits `finale_survived` (phase 6 fills it in).

Horde spawner marker fields (level editor inspector):

| Field | |
|---|---|
| `kinds` | enemy kinds, comma-separated (`basic`) |
| `rate` | spawns per minute while active |
| `max_alive` | most of this spawner's enemies alive at once (hordes ignore it) |
| `active` | trickles from the start; off means it waits for a trigger |
| `radius` | spawns land on the floor within this many meters |

Trigger markers have `activates`: comma-separated spawner ids to turn on, or `horde` to start a horde. Levels saved before these fields existed load with the defaults.

The HUD (`scripts/ui/combat_hud.gd`) shows health in the bottom left, a hit marker on the crosshair when your shot lands, and a red flash when you're hurt.

## Playing

Movement: WASD, Space jump, Ctrl crouch (no sprint), E use (doors), arrow keys look (backup for remote desktop), T flashlight. Combat: LMB shoot, MMB melee, RMB throw flask, Q cycle flask, Shift change ammo (or 1-4). F1 shows the controls. Esc releases the mouse (and pauses in solo play). Debug builds only: F fly.

All sound is synthesized at startup by `scripts/audio/sfx.gd` (no audio assets).

`scenes/test_world.tscn` is a gray-box sandbox kept for the voxel core tests. The old mushroom-farming prototype was removed in the pivot (it's in git history).

Tests (from the project root, with `godot` being the 4.7 editor binary):

```sh
godot --headless --path . --script res://tests/voxel_smoke_test.gd   # voxel core, building pieces, navigation (sandbox)
godot --headless --path . --script res://tests/enemy_test.gd         # enemies: pathing through a door, bites, hits, death, spawners, hordes
godot --headless --path . --script res://tests/vox_test.gd           # .vox round trips, prop library vs generators
godot --headless --path . --script res://tests/editor_tool_test.gd   # the level editor driven by keys and clicks
tools/net_test.sh                                                     # two-process co-op: sync, snapshots, live reload
tools/net_test.sh editor_test                                         # two-process co-op editing, play-test, save
godot --path . --script res://tests/editor_screenshots.gd -- <dir>   # editor and pattern screenshots (needs a window)
```
