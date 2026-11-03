# game-off-2026

Underground mushroom-farming FPS for Game Off 2026 (theme: SHIFT). Godot 4.7, GL Compatibility, web target.

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
- `scenes/lab.tscn` / `scripts/world/lab.gd`: the co-op level. Joiners get a compressed world snapshot, then each peer's player is spawned everywhere. Each peer simulates its own player and streams its movement; the host owns everything else.
- `scripts/net/world_sync.gd`: every voxel edit goes through here. The host applies it and replays it on every peer in order, so worlds stay identical. Gameplay must not edit `VoxelWorld` directly.

Skip the menu from the command line (args after `--`): `--solo`, `--host`, `--join=1.2.3.4`, `--name=Zack`. Two copies on one machine: start one with `-- --host`, the other with `-- --join=127.0.0.1`.

`tools/net_test.sh` runs a headless host and client against each other and checks their worlds end up byte-identical.

## Art: MagicaVoxel models

All voxel art lives in `assets/vox/` as MagicaVoxel `.vox` files, and the game reads them at runtime:

- `props/`: furniture and fittings. Levels place them by file name (`props.place("fridge", origin, facing)`).
- `characters/`: the player's body and head.
- `shrooms/`: growth stages `stage<0-4>_<variant>.vox`, plus `stage4_<variant>_eyes.vox` for grown hunters.
- `pieces/`: the old build-mode scrap pieces (reference only for now).
- `_palette.vox`: one cube per game material. `PALETTE.md` lists them.

The current files are generated placeholders, meant to be replaced or used as templates. Rules for editing:

- **Palette index = game material.** Paint with the palette slots listed in `PALETTE.md`, which come with every file. The slot decides hardness and glow, not just color. Unlisted (dark purple) or recolored slots get mapped to the closest material, with a warning. To add a material, add it to `scripts/voxel/voxel_materials.gd` and re-run the export.
- **Front is MagicaVoxel's front (-Y).** A prop's front faces into the room when placed facing a direction. Up is +Z in MagicaVoxel and +Y in the game.
- **The model box is the prop's frame.** Its min corner sits on the placement origin at floor level, so empty margins are kept on purpose. Characters stand on the bottom center of the box. The head pivots around its center.
- Models of any size work. Anything over 256 voxels is saved split into several models; keep those in one file.

**Live reload:** when the game runs from the Godot editor, saving a `.vox` in MagicaVoxel updates the running game within about a second. Edited props are swapped wherever they were placed: only the old model's voxels that are still intact are removed, so damage is kept. Characters and shrooms re-skin too. In co-op the host's files win and the host pushes prop changes to everyone. A save that doesn't parse keeps the old model. A toast in the bottom left confirms each reload. Exported builds don't watch files.

Regenerating placeholders: `godot --headless --path . --script res://scripts/tools/export_vox.gd` writes only missing files, so edited ones are safe. `-- --force` overwrites everything. The generators are in `scripts/world/props.gd` and `scripts/world/prop_catalog.gd` (the name → generator list), plus `ShroomModels` and the export script itself.

## Playing the prototype

`scenes/facility.tscn` (the old single-player mushroom loop, no longer the main scene) generates the facility: an atrium with the hatch shaft, a lab, a break room, storage, and the grow hall at the far end, all cut from layered ground (deep stone, rock, clay, gravel, dirt, sand pockets) behind painted concrete linings.

- **Day shift**: plant at least the quota of spores in the grow-hall beds (**E** on the substrate; extra spores pay more at night), fortify with build mode (**Q**; 1-4 piece, R turn, LMB place, costs money; the bottom bar shows pieces and why a placement is refused), dig and blast (LMB rifle, RMB blast; 3 blast charges per shift, **B** buys one for $10 during the day). Then climb the ladder in the atrium (**W/S** on the ladder, Space to let go) and seal the hatch (**E**). The objective line under the phase title always says what to do next.
- **Night shift**: the power dies, emergency lights come on, and the spores grow into shrooms that hunt you through the facility, digging through planks, dirt, sandbags and furniture (not metal, concrete or rock). Shrooms rear back before they bite. Harvest at least the quota before the timer runs out. Each harvest pays $15, surviving pays a bonus, and the quota grows every shift.
- Dawn shows the shift's earnings; **E** skips to the next day. Dying or missing the quota ends the run with a summary; **R** restarts.

Movement: WASD, Space, Shift sprint, Ctrl crouch, arrow keys look (backup for remote desktop), T flashlight, Esc releases the mouse. Debug builds only: F fly, F3 stats.

All sound is synthesized at startup by `scripts/audio/sfx.gd` (no audio assets); `AudioDirector` in the facility scene wires it to gameplay signals.

`scenes/test_world.tscn` is the old gray-box sandbox, kept for the voxel core tests.

Tests (from the project root, with `godot` being the 4.7 editor binary):

```sh
godot --headless --path . --script res://tests/voxel_smoke_test.gd   # voxel core, building, navigation (sandbox)
godot --headless --path . --script res://tests/shift_loop_test.gd    # a full shift in the facility, ladder, hatch, breaching
tools/net_test.sh                                                     # two-process co-op test (host + client)
godot --headless --path . --script res://tests/vox_test.gd           # .vox round trips, prop library vs generators
godot --path . --script res://tests/facility_screenshots.gd -- <dir> # room and night screenshots
```
