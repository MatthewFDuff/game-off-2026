# Performance fixes, 2026-11-04

Follow-up to `docs/perf-review-2026-11-04.md`. Every item in that review was worked through by
five agents (three Opus: voxel engine, enemies/combat/weapons, world/level/player; two Opus/Sonnet:
editor, audio/UI), each confined to its own files, then re-checked by hand where it mattered.
Nothing is committed; the working tree holds the changes. The web wasm extension was rebuilt and
the web export regenerated (`build/web/`).

## How it was measured

`tests/perf_bench.gd` is a new headless benchmark:

```sh
godot --headless --path . --script res://tests/perf_bench.gd -- --out=<file>.json
```

It loads the committed laboratory, moves the player into the open office, and times each hot path
with `Time.get_ticks_usec`: the level load, idle frames, eight shotgun carves and a rocket carve
(call time, call plus next frame, and mesh builds counted from `get_stats()`), the asset rescan for
a one-chunk and a whole-level box, 50 enemy spawns and the mesh cache size, frames with 50 enemies,
frames with homing shots, a flow refresh, a shift save, SFX synthesis, editor picking, and memory.

"Before" is the median of three runs on a pristine worktree of HEAD (`57f3e7f`), "after" the median
of three runs on the working tree, same machine, same binary (Godot 4.7.2 Steam, opt.tools). It is
headless, so GPU and draw costs are not measured; the light and particle changes below are judged
by count, not by frame time. All times are desktop; the web build runs the same script code about
two to three times slower and single-threaded, so the wins there are proportionally larger but
unmeasured.

## Results

| Measurement | Before | After | Change |
|---|---|---|---|
| Shotgun: 8 carves, call time | 14.6 ms | 1.6 ms | -89% |
| Shotgun: 8 carves, call + next frame | 19.1 ms | 6.8 ms | -65% |
| Shotgun: mesh builds per shot | 9 | 2 | -78% |
| Shotgun: real `Weapon.fire`, call time | 16.2 ms | 1.4 ms | -91% |
| Shotgun: real `Weapon.fire`, mesh builds | 13 | 2 | -85% |
| Rocket carve (r 1.2 m), call time | 7.1 ms | 1.7 ms | -76% |
| Rocket carve, call + next frame | 10.8 ms | 7.5 ms | -31% |
| Asset rescan, one-chunk box | 0.318 ms | 0.005 ms | -98% |
| Asset rescan (InteractRules), one-chunk box | 0.031 ms | 0.003 ms | -90% |
| Asset rescan, whole-level box | 5.8 ms | 7.0 ms | level, see note |
| Glass shatter prop scan | 5.9 ms | 0.006 ms | -100% |
| Idle frame in play, no enemies | 10.3 ms | 7.8 ms | -24% |
| Idle physics tick | 3.39 ms | 0.76 ms | -78% |
| Frame with 50 enemies | 11.6 ms | 8.9 ms | -23% |
| Physics tick with 50 enemies | 5.59 ms | 1.92 ms | -66% |
| Frame with 50 enemies, 95th percentile | 17.0 ms | 10.4 ms | -39% |
| Frame with 50 enemies + homing shots | 12.1 ms | 9.5 ms | -22% |
| Flow field refresh (standing still) | 0.33 ms | 0.02 ms | -93% |
| Spawn 50 enemies | 80 ms | 39 ms | -52% |
| Enemy mesh cache after 50 basic spawns (4 model files) | 50 entries | 4 entries | leak fixed |
| Shift save | 90 ms | 14 ms | -84% |
| Level load (start to first playable frame) | 6.24 s | 4.71 s | -24% |
| Static memory after the spawn test | 313 MB | 251 MB | -20% |
| Peak static memory | 447 MB | 251 MB | -44% |
| SFX work before the first frame | 222 ms | 23 ms | -90% |
| SFX first play of a not-yet-built sound | 0.1 ms | 7.9 ms | new cost, see note |
| Editor: cursor pick per frame, aim unchanged | 11.2 ms | 0.003 ms | -100% |
| Editor: cursor pick, aim changed (forced) | 11.2 ms | 0.56 ms | -95% |
| Editor: idle frame | 14.2 ms | 7.3 ms | -49% |
| Editor: idle frame, 95th percentile | 29.9 ms | 7.9 ms | -74% |

Notes on the table:

- "Call + next frame" includes one ordinary frame (about 6 to 7 ms idle after the fix), so the
  carve itself is the call-time row. Remeshing is now deferred to the end of the frame, which is
  why the call time dropped more than the frame time.
- The whole-level asset rescan is a synthetic case: one `voxels_changed` box covering the entire
  level. It is dominated by 1163 C++ `count_matching` calls and sits between 5.4 and 7.6 ms across
  runs on both trees. It no longer occurs in play because scattered edits now emit one box per
  touched chunk.
- The homing frame numbers are valid; the benchmark's "live homing shots" count is not a
  behaviour metric. It swung between 1 and 9 on identical code depending on where the crowd stood.
  A separate probe (50 enemies, 15 shots, 120 frames, three runs each tree) showed the same hit
  counts on HEAD and after the change, and 20,000 random segments found zero hits wrongly rejected
  by the new bounding-sphere test.
- SFX: synthesis is now on demand. Seven menu sounds are built before the first frame, the rest fill
  in one per frame over the first 70 frames, and a sound requested before its turn is built on that
  frame (the 7.9 ms is the 2 s game-over sting, the longest).

## What was done, by review item

Priority 1:

1. Synchronous remesh and repeated rebuilds. Edits now only mark chunks dirty; pending chunks are
   built once per frame in `frame_pre_draw` (and at the start of `_process` for headless), nearest
   the camera first, up to `immediate_remesh_limit` (default now 3, was 24), with the rest on the 4
   ms budgeted queue. `flush_edits()` builds pending chunks on demand; `remesh_all_now()` is
   unchanged. `build_chunk_mesh` memcpy/memsets the padded copy row by row, reuses each chunk's
   ArrayMesh, and sets the material once. New `carve_spheres(centers, radius, power)` on VoxelWorld
   and WorldSync: the shotgun sends one RPC per shot instead of eight, with one loose-piece pass.
   `get_stats()` gained `mesh_builds`, `chunks_pending`, `chunks_changed`, `flow_rebuilds`,
   `flow_skips`.
2. Asset rescan. `LevelPlay` and `InteractRules` keep chunk-keyed spatial indexes of assets, glass,
   reactive props, doors, props and usables, built at `start()` with precomputed boxes and kept
   current on flips, skids, take-aways and door moves. `set_voxels`, `carve_spheres` and
   `set_chunks_data` emit `voxels_changed` once per touched chunk with tight bounds.
3. Enemy mesh cache leak. `EnemyModels.model()` returns a stable key (the file path, or
   `generated:kind:variant % n`); the mesh and debris-count caches use it, and `paths()` is cached
   per kind. Variant selection and replication are unchanged.
4. SFX synthesis. Lazy per sound with a seven-sound eager set and a one-per-frame background fill.
   `_synthesize_all()` still exists. `_to_wav` still encodes per sample: `AudioStreamWAV` has no
   float format and GDScript has no vectorised float-to-int16 path.
5. Editor picking. New `scripts/editor/editor_index.gd`: cached boxes per object, per-kind lists,
   an 8 m XZ grid, cached walls per storey and openings per wall, all maintained through
   `LevelEdits.object_set` and a new `objects_version`. `_update_cursor` returns early when nothing
   it depends on changed. Verified against the old full scans on the laboratory: 6000 random rays
   and 4500 room/opening/wall/prop checks, zero mismatches, before and after edits and an undo.

Priority 2:

6. Whole-world saves. Shift saves are now a delta: `get_changed_chunks()` plus
   `get_chunks_data(slots)` relative to the level as built at load, format 2 in `ShiftSave`; format 1
   saves still load (and a session resumed from one keeps saving whole-world). `clear_changed_chunks()`
   runs after props and mycelium are stamped so the delta is only what play changed. `encode_info()`
   is cached for joiners. `_edit_base` reuses the loaded bytes instead of a second 71 MB copy. The
   joiner's voxel snapshot is still the whole world (see "Not done").
7. Trigger loop. `start()` builds the 46 volumes (triggers, kill zones, clone vats) with world boxes;
   the tick loops only those, with no per-tick allocation.
8. Lights. Per-light data cached at `_add_light`; steady energies recomputed only when the mode,
   backup power, play state or a new `lights_version` on InteractRules changes; only visible
   flickering lights animate; equal writes skipped.
9. Level load. `Props.oriented(name, facing)` caches orientation (was run three times per prop);
   `LevelData` key sets are Dictionaries; solo play shows a one-frame "Loading..." screen first; cloud
   stain meshes for the stock radii are prewarmed (27 meshes, about 0.1 s). The remaining 4.7 s is
   mostly JSON decode, 71 MB zstd, mycelium stamping and the full remesh.
10. Projectiles. Enemy list cached per physics frame in `Combat`; bounding-sphere reject before the
    transform inverse; misses return a shared read-only result; homing re-evaluates an existing
    target at 10 Hz but scans for a new one every tick (so acquisition matches HEAD).
11. Flamethrower. One `request_hits` RPC per cone check with packed ids; the host applies burning
    from the damage kind; hit flash and hit sound rate-limited to one per enemy per 0.1 s.
12. Stuck enemies. `_breach` pre-checks `find_in_sphere` for diggable material, sends nothing when
    there is none, and backs off 1.2, 2.4, 4.8 s. `WorldSync.carve_sphere` replays to peers only
    when the host removed something.
13. Flow field. C++ skips the rebuild when every target is on the same floor cell as last time and
    no nav column changed; `flow_reached` is a property instead of a `get_stats()` call. `FLOW_RANGE`
    stays 80 m because the finale selects spawners within 2 x `wake_range` by walking distance.
14. Horde director. Walk distances computed once per flow refresh (5 Hz) and stored on the spawner;
    alive lists pruned on a `removed_version` counter; cheap checks first; `player_factor()` once per
    frame.
15. Enemy tick. Targets cached per frame; constants hoisted; `get_flow` reused for 0.1 s while in the
    same column; enemies more than 25 m from every player think every second physics frame with the
    skipped time added.
16. Lights and particles. Cloud lights pooled to the 3 nearest the camera, none for spore and foam;
    projectile light only for explosive and homing; cloud, trail, ember and flame particle counts
    halved on web; cubicle glow off on web; the computer screen SubViewport redraws at 10 Hz instead
    of every frame. The cubicle's 10 lights are unchanged.
17. Editor. Thumbnails render visible tiles first (one per frame) and the rest at one per three
    frames; prop tiles built once and filtered by `visible`, search debounced 150 ms, prop names
    cached; ghost placement uses the grid; undo capped at 256 MB total (64 MB on web), oldest steps
    dropped first; HUD updates on state change; wall drags reuse cached lists; presence redraws only
    on change; `LevelBuild.storeys` no longer allocates a default per call.

Priority 3, done: `Fire._douse` bucketed by cell; `GearModels` meshes cached per model and glow
material shared per colour; projectile and splat materials shared through `VoxelFx.shared_material`;
enemy state packets split at 50 enemies; player movement RPC on ENet channel 1; ladder probe cached
per column; VoxWatch does nothing when disabled and spreads its scan over frames; the gameplay
terrain shader has no `discard` (`voxel_terrain_play.gdshader`, swapped automatically when the
cutaway uniforms are off; `voxel_terrain.gdshaderinc` holds the shared body); palette row fetched
once; `set_material_hardness` only marks nav stale on a real change; StringName keys in the C++
result dictionaries; the UI font-colour and text-fit calls run only on change.

### Not done

- The joiner's voxel snapshot still sends the whole world (`WorldSync.send_snapshot`). The delta
  path needs the host's play build (props and mycelium stamps) factored into a function both sides
  call, a tagged "chunks" blob in `world_sync.gd`, and a level-hash check with a full-snapshot
  fallback. The `encode_info()` half is done.
- Time-slicing the flow-field Dijkstra across frames. The skip helps while players stand still; any
  voxel write anywhere forces a rebuild.
- Packed-array returns for `move_box`/`get_flow`/`raycast` (they still return Dictionaries, now with
  cached keys).
- The interact prompt still loops the 54 doors each frame (usables use the index).
- `Fire._visit`'s per-voxel `get_voxel` calls (capped, no cheap GDScript win).
- The cubicle's 10 omni lights, and anything GPU-side, which was not measured.

## Behaviour changes and limitations

Rendering and feel:

- Carves show in the same frame on desktop (the flush runs in `frame_pre_draw`), but only the 3
  chunks nearest the camera are built immediately; the rest of a rocket's 8 to 27 chunks stream in
  over the next frames through the 4 ms queue. Large editor operations (room tool, undo) also stream
  in unless the editor calls `flush_edits()`.
- A shotgun blast cuts slightly differently from eight separate carves: loose pieces are detected
  once after all pellets. It is deterministic on every peer.
- Enemies farther than 25 m from every player move and think at 30 Hz on the host's own screen.
  Peers already saw 10 Hz interpolation.
- Hit flash and hit sound are capped at one per enemy per 0.1 s; damage is unaffected.
- A homing shot keeps its current target for up to 0.1 s even if a nearer enemy enters its cone.
- Only explosive and homing projectiles glow; basic, ricochet, poison, spit globs and thrown flasks
  no longer carry a light. Spore and foam clouds do not glow; of the other clouds, only the 3
  nearest the camera do.
- Web: particle counts are halved (floor of 8 per cloud), and cubicle glow is off.
- The cubicle computer screen refreshes at 10 Hz, so the cursor blink and "thinking" dots can lag by
  up to 100 ms.
- The first play of a sound that has not been built yet costs its synthesis time on that frame
  (up to about 8 ms on desktop for the longest sounds; two to three times that on web) if it is
  requested in the first second or so before the background fill reaches it. Random sound recipes
  roll their variation at first use instead of at startup.
- Stuck enemies against hard walls stop sending carves and retry at growing intervals; they still
  hop.
- Steering uses a flow lookup up to 0.1 s old; the wake-range check uses a walk distance up to 0.2 s
  old; the per-frame target list can be one frame stale (the public `targets()` is fresh).
- Lights only re-evaluate on state changes. Code that edits `rules.room_lights` directly without
  `_room_lights` would be missed (nothing does today). A broken light is no longer dropped from the
  20-light budget during an off-blink. Hidden flickering lights hold their steady energy.
- The gameplay shader swap happens the first time the editor cutaway turns on; that shader compiles
  once then, which may hitch.

Saves and networking:

- New shift saves are format 2 (delta). Format 1 saves still load; a session resumed from one keeps
  saving whole-world. The delta relies on the level hash (level.json and voxels.bin) and on the prop
  and mycelium stamps being reproducible: a changed prop `.vox` between save and resume would show
  the new model in untouched chunks and could split a prop across an old and a new chunk. A delta
  grows with how much of the level was changed; there is no automatic fallback to a full save.
- Empty carves are not replayed to peers. This is safe only because worlds are identical at that
  point in the ordered stream.
- Enemy state goes out in packets of 50; with more than 50 enemies an out-of-order packet is
  dropped as before.
- The flamethrower's client-to-host batched path is not covered by any test; the host path is.
- The `encode_info()` cache must be invalidated by any future code that changes `level.objects`
  outside `LevelEdits.object_set` (`level.invalidate_info()`).
- Player movement now uses ENet channel 1; Net creates peers with the default channel count, which
  worked in the co-op tests.

Editor:

- The cursor is recomputed only when its inputs change (aim, tool, grab, view, storey, level
  version, voxel-change counter, camera pick state). State not on that list would leave it stale
  until the mouse moves. Prop sizes are cached per object, so a live-reloaded prop with a new size
  keeps its old pick box until that object changes.
- The index follows `LevelEdits` only; writing `lab.level.objects[...]` directly leaves it stale.
- Off-screen thumbnails appear later (about 20 per second); the drawer scrolls to the top on filter
  or category change; the 355 tiles stay alive hidden; a prop added on disk shows up when the Prop
  tool is picked again; search refilters 150 ms after typing stops.
- Undo history is bounded by bytes; large carves evict the oldest steps (anyone's, undo or redo). A
  single step over the cap is still kept.
- VoxWatch reports a saved `.vox` about 1 to 1.5 s after the save instead of about 0.8 s.

## Tests

All 41 tests in `tests/` were run on the working tree after every agent finished: 36 single-process
tests and 5 two-process co-op tests. 40 passed. The one failure was `net_test` on its first run
("a pickup taken on the host disappears on the client"), with matching host and client world
hashes. That failure is pre-existing: the same test fails 1 in 8 runs on a pristine HEAD worktree
for the same reason. A random 20% enemy loot drop (`ItemManager.drop_chance`) that happens to be
`ammo_shotgun` makes the client latch onto the drop instead of the test's own pickup. On the working
tree it passed 6 of 7 runs; no run on either tree showed a world-hash mismatch. Setting
`drop_chance = 0` in `net_test.gd` would fix the flake; the test was not changed.

Two tests were edited to follow deliberate API changes: `shift_save_test.gd` (delta format checks,
plus a new format 1 resume check) and `cubicle_test.gd`. The latter's edit is not from this work
(see below). No other test was changed.

The web build was rebuilt (`tools/export_web.sh`, Emscripten 4.0.20) and exported to `build/web/`.
The Windows debug and release DLLs were rebuilt and the full suite ran against them. Nothing has
been play-tested by hand in a window or in a browser; the visual effects of the light, particle,
remesh-streaming and screen-refresh changes are judged from code and counts only.

## Unrelated changes in the working tree

Another session was editing the cubicle while this work ran (10:10 to 10:14): a Name row in the
settings menu, a rubber duck that yields to the desk's box, a `LEAF` material and a new
`fake_plant.vox`, the removal of the "-$" damage toasts from `level_play.gd`, and updates to
`docs/cubicle-menu.md`, `docs/shift-save.md`, `README.md`, `tests/cubicle_test.gd`,
`scripts/ui/settings_menu.gd` and `scripts/voxel/voxel_materials.gd`. The agents here preserved
those edits and made theirs on top. Those files should be reviewed with that in mind before
committing; they are not part of the performance work.

## Suggested next steps

1. Play the laboratory in a window: a shotgun and rocket into a wall (the streaming remesh), a fight
   with clouds and fire (fewer lights), the cubicle screen (10 Hz), and the first minute of audio.
2. Run the web export in a browser and watch the console for the first-play audio hitches and the
   loading frame.
3. Decide on the `net_test` flake fix.
4. Commit the performance work separately from the cubicle session's changes.
5. Finish the joiner delta snapshot when co-op join stalls matter.
