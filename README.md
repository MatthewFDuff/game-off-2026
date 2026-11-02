# game-off-2026

Underground mushroom-farming FPS for Game Off 2026 (theme: SHIFT). Godot 4.7, GL Compatibility, web target.

## Layout

- `extension/`: C++ GDExtension (`VoxelWorld`): voxel storage, greedy meshing, raycasts, box collision. `godot-cpp` is a submodule.
- `bin/`: `voxelcore.gdextension` plus the compiled libraries (not committed; build them yourself).
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

Rebuild after pulling C++ changes. Rebuilding works while the editor or game is running (the build moves the locked DLL aside); restart the game to pick up the new library.

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

## Playing the prototype

`scenes/facility.tscn` (the main scene) generates the facility: an atrium with the hatch shaft, a lab, a break room, storage, and the grow hall at the far end, all cut from layered ground (deep stone, rock, clay, gravel, dirt, sand pockets) behind painted concrete linings.

- **Day shift**: plant at least the quota of spores in the grow-hall beds (**E** on the substrate), fortify with build mode (**Q**; 1-4 piece, R turn, LMB place, costs money), dig and blast (LMB rifle, RMB blast). Then climb the ladder in the atrium (**W/S** on the ladder, Space to let go) and seal the hatch (**E**).
- **Night shift**: the power dies, emergency lights come on, and the spores grow into shrooms that hunt you through the facility, digging through planks, dirt, sandbags and furniture (not metal, concrete or rock). Harvest at least the quota before the timer runs out. Each harvest pays $15, surviving pays a bonus, and the quota grows every shift.
- Dying or missing the quota ends the run; **R** restarts.

Movement: WASD, Space, Shift sprint, Ctrl crouch, arrow keys look (backup for remote desktop), F fly, T flashlight, F3 stats, Esc releases the mouse.

`scenes/test_world.tscn` is the old gray-box sandbox, kept for the voxel core tests.

Tests (from the project root, with `godot` being the 4.7 editor binary):

```sh
godot --headless --path . --script res://tests/voxel_smoke_test.gd   # voxel core, building, navigation (sandbox)
godot --headless --path . --script res://tests/shift_loop_test.gd    # a full shift in the facility, ladder, hatch, breaching
godot --path . --script res://tests/facility_screenshots.gd -- <dir> # room and night screenshots
```
