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

Web (needs [emsdk](https://emscripten.org/docs/getting_started/downloads.html) **4.0.11**, the version the Godot 4.7 web templates are built with; other versions can fail to load):

```sh
emsdk install 4.0.11 && emsdk activate 4.0.11   # then source emsdk_env in this shell
cd extension
scons platform=web target=template_release threads=no
scons platform=web target=template_release            # threaded variant
```

For the web export preset, tick **Extensions Support**. The threaded build needs cross-origin isolation (itch.io: "SharedArrayBuffer support").

Rebuild after pulling C++ changes. Godot needs a restart to pick up a new library on Windows, because the DLL is locked while the editor runs.

## Test scene controls

`scenes/test_world.tscn`: WASD, Space, Shift sprint, Ctrl crouch, LMB rifle, RMB blast, E place block, 1-4 block material, Arrow keys look (backup for remote desktop), F fly, T flashlight, F3 stats, Esc release mouse.
