# Performance review, 2026-11-04

**Status (later the same day):** every item below was worked through; the measured before/after
numbers, what changed, what was left out, and the behaviour changes are in
`docs/perf-fixes-2026-11-04.md`. The benchmark is `tests/perf_bench.gd`.

A read-only review of the game for performance problems. Five reviewers (three Opus, two Sonnet)
each read one area in full: the voxel engine and shaders, enemies and combat, world/level/player/net,
UI/story/audio/config, and the editor. The top findings were then re-checked by hand against the
code. Nothing was run or profiled, so every millisecond figure below is an estimate from reading
the code. `VoxelWorld.get_stats()` already reports `last_mesh_ms`, `max_mesh_ms`, `last_flow_ms`
and friends; check those on a real run before acting on the voxel items.

Nothing in the game was changed.

## Scale

The laboratory is the level that matters. The others are small.

| level | objects | props | light markers | triggers / kill zones | doors | usables | assets (value > 0) | raw voxels |
|---|---|---|---|---|---|---|---|---|
| laboratory | 1956 | 1224 | 217 | 35 | 54 | ~169 | 1163 | 70.9 MB |
| lab | 126 | 102 | 20 | 0 | – | – | – | 52.4 MB |
| waiting_room | 61 | 45 | 3 | 0 | – | – | – | 3.4 MB |
| cubicle | 38 | 21 | 5 | 1 | – | – | – | 1.2 MB |

The laboratory is 16 x 12 x 16 chunks of 32³ voxels (0.1 m voxels, 3072 chunks, about 51 m
across). The web build is the no-threads wasm variant, so every main-thread cost below is roughly
2 to 3x worse there, and there is no worker thread to move anything onto.

## Summary

There are real issues. Five should be fixed first; they hit every shot fired, every spawn, or
every frame.

| # | Issue | Where it bites | Desktop | Web |
|---|---|---|---|---|
| 1 | Every voxel edit remeshes its chunks synchronously, and a shotgun remeshes the same chunk up to 8 times per shot | every shot into a wall, every fire flush | High | High |
| 2 | The host rescans all 1163 assets, 54 doors, glass and reactive props on every voxel change, with no spatial filter | every pellet, every fire part (10/s) | High | High |
| 3 | The enemy mesh cache is keyed by the per-spawn id, so every spawn meshes a new body that is never freed | every spawn, on host and peers | High | High |
| 4 | All 69 sound effects are synthesized in GDScript before the first frame | startup | Medium | High |
| 5 | Editor cursor picking scans all ~2000 level objects every frame, even with the mouse still | editor, laboratory level | High | High |

Then a group of medium items: whole-world saves and snapshots on the main thread, per-tick loops
over all level objects and all 217 lights, a multi-second level load, projectile and flamethrower
costs that scale with enemy count, and light/particle counts on the Compatibility renderer.

## Priority 1: fix first

### 1. Edits remesh synchronously and the same chunk is rebuilt several times per frame
- Where: `extension/src/voxel_world.cpp:1235-1240` (`finish_edit`), `:527-532` (`set_voxels`),
  `extension/src/voxel_world.h:45` (`immediate_remesh_limit = 24`). `scenes/lab.tscn` does not
  override the limit, so gameplay runs at 24 (the two other writers are a throwaway world in
  `level_data.gd:60` and a temporary override in `world_sync.gd:269`).
- What happens: any edit touching 24 chunks or fewer builds all of them inside the call, on the
  host and on every peer. The 4 ms `remesh_budget_ms` only applies to the queue drained in
  `_process`. One chunk build is a 39k-cell padded copy through bounds-checked `read()`, a full
  greedy pass, a new `ArrayMesh` and a GPU upload, plus a 32 KB `try_compress` scan.
- Multiplied by: `weapon.gd:302-313` calls `world_sync.carve_sphere` once per pellet, and
  `build_chunk_mesh` clears the dirty flag, so 8 pellets in one chunk rebuild it 8 times in one
  frame. Each pellet also emits its own `voxels_changed` and `carved` signals, its own debris
  burst, and its own reliable RPC per peer. Fire flushes (`world_sync.gd:109-119`, `SET_PART =
  300`) rebuild overlapping chunks once per part every 0.1 s.
- Cost: a rocket (12-voxel radius) touches 8 to 27 chunks; well over 10 ms on desktop, 2 to 3x on
  web, in a single frame.
- Fix: have edits only `mark_dirty` and build once per frame (a "flush pending" pass at the start
  of `_process`, nearest the camera first, or an explicit `flush_edits()` after a batch). Set
  `immediate_remesh_limit` to 1 or 2 for gameplay. Add a batched `carve_spheres(points, radius,
  power)` for multi-pellet shots: one detach pass, one signal, one RPC. `build_chunk_mesh` can also
  `memcpy` interior rows instead of calling `read()` per cell and reuse the mesh instead of
  allocating one (`voxel_world.cpp:1303-1365`).
- Confidence: behaviour confirmed by reading; timings are estimates.

### 2. The host rescans every asset, door and reactive prop on every voxel change
- Where: `scripts/level/level_play.gd:1239-1265` (`_on_voxels_changed`) and
  `scripts/interact/interact_rules.gd:410-431` (`voxels_changed`), both connected to
  `VoxelWorld.voxels_changed`.
- What happens: each event loops all 12 glass cases and all 1163 assets, building an `AABB` per
  entry for an `intersects` test, then all reactive props and 54 doors. Every pellet, fire part,
  door stamp, glass break and explosion fires the signal.
- Made worse by: `set_voxels` (`voxel_world.cpp:478-533`) emits one bounding box over all its
  scattered points, so a fire or mycelium batch reports a box covering most of the level, and
  nearly every prop then passes the AABB test and runs a C++ `count_matching` over its volume.
- Cost: about 1250 GDScript iterations per event. A shotgun blast is 8 events: roughly 3 to 6 ms on
  desktop and 10 to 20 ms on web, per shot. Fire adds up to 10 events a second while anything burns.
- Fix: at `start()`, bucket assets, glass, reactive props and doors into a spatial hash keyed by
  chunk, and store a precomputed `AABB` per record. On an event, look up only the chunks covered.
  Have `set_voxels` emit per-chunk ranges (or pass the touched chunk list) instead of one union
  box. Fixing item 1's per-pellet batching also cuts the event count by 8.
- Confidence: confirmed.

### 3. The enemy mesh cache leaks: keyed by spawn id, so every spawn builds a new body forever
- Where: `scripts/enemies/enemy_manager.gd:209` sets `enemy.variant = id` (the unique spawn id).
  `scripts/enemies/enemy.gd:171-173` keys a static `_meshes` dictionary on `"%s:%d" % [kind,
  variant]` and stores `world.build_model_mesh(...)` under it.
- What happens: `EnemyModels.model()` picks the file with `posmod(variant, files.size())`, so the
  model data is shared, but the cache key is not. Every spawn runs a fresh C++ mesh build on the
  host and on every peer, and every resulting `ArrayMesh` stays in the static cache for the
  session. `EnemyManager.clear()` does not release them. Giant and mommy meshes are 25x16x25 and
  26x40x26 voxels.
- Cost: a mesh build per spawn (hordes burst at 6/s), plus unbounded RAM and VRAM growth over a long
  shift. The `generated:` key at `enemy_models.gd:34` has the same bug, latent today.
- Fix: key the cache by the resolved model (file path, or `kind:variant % n`). Simplest: have
  `EnemyModels.model()` return a stable `key` and use that in `build_body`. Cache
  `_debris_counts` (`enemy.gd:683-690`, a GDScript loop over every model voxel per death, 27k for a
  giant) under the same key. Also cache `EnemyModels.paths()` (`enemy_models.gd:18-27`), which
  reads the directory on every call.
- Confidence: confirmed by hand.

### 4. All sound effects are synthesized in GDScript before the first frame
- Where: `scripts/audio/sfx.gd:119-125` (`_ready` of the `SfxBank` autoload), `:246-287`
  (`_synthesize_all`), `:990-1045` (`_add_tone`, `_add_noise`), `:1091-1105` (`_to_wav`).
- What happens: 69 sounds, about 916k samples, each sample through a GDScript inner loop, then a
  second pass of one `encode_s16` per sample. Once per launch, but in front of the first frame.
- Cost: an estimated 0.5 to 2 s on desktop; 2 to 8 s of frozen tab on web with nothing drawn, which
  can trigger the browser's "page unresponsive" prompt.
- Fix: generate lazily on first play and cache (sounds are already keyed by name); or pre-generate
  only the cubicle's sounds and spread the rest over frames; or best for web, bake the WAVs offline
  with the existing synth into resources. Vectorize `_to_wav` regardless.
- Confidence: confirmed; duration estimated. Playback itself is fine: voices are pooled.

### 5. Editor: cursor picking scans every level object every frame
- Where: `scripts/editor/editor_tool.gd:426` (`_process`) via `_update_cursor` (`:477-538`),
  `room_under` (`:832`), `build_under` (`:853`), `_update_previews` (`:2058`).
- What happens: every frame, with no check that the aim ray, tool or object set changed, pass 1
  loops all objects calling `LevelBuild.is_build()`, `LevelSchema.box_of()` (which goes through
  `Props.load_prop` per prop) and `AABB.intersects_ray()`. The Select tool adds three more
  full passes (`room_under`, `opening_at` twice, `wall_at`).
- Cost: about 1750 box tests plus 3 to 4 passes of about 2000 per frame in the laboratory; an
  estimated 8 to 15 ms on desktop, 2 to 3x on web.
- Fix: skip picking when aim origin, direction, tool and object-set version are unchanged. Keep a
  cached `id -> world AABB` table updated from `object_set`, and a per-kind index so room, wall
  and opening lookups do not walk props and markers. A coarse spatial grid finishes it.
- Confidence: confirmed; ms estimated.

## Priority 2: medium

### 6. Whole-world copy and compress on the main thread, mid-play
- Where: `scripts/world/lab.gd:172-189` (`save_shift`) and `scripts/story/shift_save.gd:78-95`
  (`world.get_data()`, zstd, `JSON.stringify`, two file writes). Triggered from `_physics_process`
  when a player reaches a clone vat (`level_play.gd:982`), after every door-locking trigger, when
  the generator starts (`level_play.gd:479`, the finale beat), and on window close.
- Also: a peer joining mid-play (`lab.gd:554-580`) runs `level.encode_info()` (GDScript encode of
  1956 objects, a RegEx over 840 KB, zstd) plus `world_sync.send_snapshot` (`world_sync.gd:288-311`:
  `get_data`, zstd, 150 to 300 reliable 4 KB RPCs queued in one frame) on the host, so every
  player freezes. And `lab.gd:261-262` holds `_edit_base = world.get_data()` (~71 MB) for the whole
  play session even when the session will never return to edit mode.
- Cost: `get_data` copies about 71 MB; an estimated 100 to 300 ms on desktop and 0.3 to 1 s on
  web per save; 150 to 400 ms host stall per join; peak heap near 3x 71 MB on web.
- Fix: save a delta of dirty chunks relative to the level's base `voxels.bin` (the base is already
  on disk, guarded by `level_hash`; `mark_dirty` already knows the chunks). The same delta serves
  joiners. Cache `encode_info()` bytes until objects change. Only capture `_edit_base` when the
  session started in edit mode. On desktop, compress on `WorkerThreadPool`. At minimum hide the
  save behind the vat or generator animation.
- Confidence: confirmed; timings estimated.

### 7. LevelPlay walks all ~1956 level objects every physics tick
- Where: `scripts/level/level_play.gd:1199-1234`.
- What happens: at 60 Hz on the host it iterates every object, props and rooms included, to find
  35 trigger/kill-zone markers and 11 clone vats, allocating an array literal per marker, calling
  `marker_box` and `to_world`, and building a fresh `inside` array and `filter` lambda per trigger.
- Cost: about 2000 dictionary iterations per tick, roughly 0.4 to 0.7 ms on desktop, 1 to 2 ms on
  web, the whole time the level is played.
- Fix: in `start()`, build a list of the 46 volumes with precomputed world boxes and loop only
  those. Optionally drop to 20 Hz and use `distance_squared_to`.
- Confidence: confirmed.

### 8. LevelView updates every light every frame, including the 197 hidden ones
- Where: `scripts/level/level_view.gd:132-169`.
- What happens: 217 OmniLight3D nodes exist in the laboratory while `LIGHT_BUDGET` shows 20.
  Each frame, for every light: three `get_meta` calls, `rules.light_mode(light_id)`, and a write
  to `light_energy` (a RenderingServer call) even when unchanged. Once any room has a lights mode,
  `light_mode` builds a `room_outer` AABB per room per light per frame (217 x 3 rooms is about 650
  AABBs per frame).
- Cost: 0.2 to 0.4 ms on desktop, 0.6 to 1.2 ms on web, more with rooms switched off.
- Fix: cache per-light data at `_add_light` (base energy, flicker, containing rooms); recompute
  `light_mode` only when `room_lights` changes; animate only visible flickering lights; skip equal
  writes.
- Confidence: confirmed. Shadows are off on all laboratory lights, which is fine.

### 9. Level load freezes the main thread for seconds with nothing drawn
- Where: `scripts/world/lab.gd:102-115` and `_set_mode_locally` (`:256-295`).
- What happens: JSON parse of 842 KB; `_decode` with a linear `key in VECTOR3I_KEYS` per key;
  zstd of 71 MB; `set_data`; a second `get_data()` for `_edit_base`; mycelium plan and stamp (a
  GDScript isosurface voxelization, `mycelium.gd:428-578`); `Props.orient` run in GDScript three
  times per non-north prop (`props.gd:57-65`, `level_play.gd:173`, `InteractRules.start`),
  uncached, about 750k voxel iterations in total; 1163 `count_matching` calls; 217 light nodes;
  `remesh_all_now()` over 3072 chunks.
- Cost: the orient passes alone are 0.2 to 0.5 s on desktop and about 1 s on web; the total is
  likely a multi-second freeze on web, with the "page unresponsive" risk.
- Fix: cache `orient` by `name:facing` (as `_prop_meshes` already does), or add a C++
  `stamp_oriented`. Make `_decode`'s key sets dictionaries. Skip `_edit_base` when not editing.
  Draw a loading frame and `await process_frame` before the heavy work. Prewarm common cloud stain
  radii here too (`voxel_fx.gd:180-205`, a 6.4k-cell SurfaceTool build on first use).
- Confidence: code paths confirmed; timings estimated.

### 10. Projectiles test every enemy with a transform inverse, twice per tick when homing
- Where: `scripts/weapons/projectile.gd:132` calls `Combat.ray_hit` per sub-step per tick;
  `:148` (`_steer`) calls `Combat.enemies()` again. `scripts/combat/combat.gd:22-25, 59-68`:
  `enemies()` runs `get_nodes_in_group` and builds a typed array per call; `Enemy.ray_test`
  (`enemy.gd:255-275`) does `affine_inverse()` and returns a new Dictionary even on a miss.
- Cost: projectiles x sub-steps x enemies x 60 Hz. Up to about 15 live homing shots per player
  gives roughly 100k enemy iterations a second; several ms per frame with 60 enemies on the
  shooter's machine, worse on web.
- Fix: build the enemy list once per physics frame (or use `EnemyManager.enemies`); reject with a
  bounding-sphere or segment-vs-bounds test before the inverse; return `t` instead of a
  Dictionary; retarget homing at 10 Hz.
- Confidence: code confirmed; timing estimated.

### 11. Flamethrower sends two reliable RPCs per enemy per check, and the host echoes FX per hit
- Where: `scripts/weapons/weapon.gd:324-340` (`_fire_cone`, 10 checks/s) calls `request_hit`
  and `request_status` per enemy; on a client each is a reliable RPC with String args
  (`enemy_manager.gd:304, 358`). On the host every hit sends `_hit_fx.rpc_id` to all peers and
  plays a hit sound (`enemy_manager.gd:344-347, 391-395`).
- Cost: 10 shrooms in the flame is about 200 reliable messages/s up from one client and 100/s down
  to each peer, plus 100 hit sounds/s competing for 12 voices.
- Fix: one RPC per cone check with a `PackedInt32Array` of ids; apply burning on the host from the
  hit kind; throttle `_hit_fx` per enemy to one per 0.1 s or batch per frame.
- Confidence: confirmed.

### 12. Stuck enemies broadcast a carve every 0.6 s each even when nothing is removed
- Where: `scripts/enemies/enemy.gd:446-447, 551-560` (`_breach`) and
  `scripts/net/world_sync.gd:51-55`, which sends `_apply_carve` to every peer before checking
  whether anything was removed.
- Cost: 30 shrooms jammed against concrete (hardness above `breach_power`) is about 50 reliable
  RPCs/s per peer and 50 sphere carves/s on every machine, indefinitely. Rifle carves into concrete
  (`weapon.gd:313`, 8/s) do the same. Each carve also triggers items 1 and 2.
- Fix: back off `_breach_timer` when a dig removes nothing, or pre-check with `find_in_sphere`
  for soft materials; in `world_sync`, only broadcast when `removed` is non-empty.
- Confidence: confirmed.

### 13. The flow field rebuilds a full-level Dijkstra five times a second in one tick
- Where: `scripts/enemies/enemy_manager.gd:670-686` (`FLOW_RATE = 5`, `FLOW_RANGE = 80`),
  `extension/src/voxel_world_nav.cpp:204-300`.
- What happens: 80 m is wider than the 51 m level, so the cost cap never prunes; every refresh is
  a full multi-source Dijkstra over up to 16k columns x 6 spans, a `std::fill` of `nav_flow`, a
  scan of every column, then `get_stats()` (which walks all 3072 chunks and builds a 13-key
  Dictionary) just to read `flow_reached` (`enemy_manager.gd:678`). The director forces extra
  refreshes (`horde_director.gd:258, 605`).
- Cost: a periodic spike every 200 ms; Medium on web, Low on desktop. Check `last_flow_ms`.
- Fix: skip when no target changed column and nothing is dirty; cap the range to 30 to 40 m;
  expose `flow_reached` through its own getter; time-slice if still slow.
- Confidence: behaviour confirmed; cost estimated.

### 14. The horde director recomputes walk distance for every spawner every physics frame
- Where: `scripts/enemies/horde_director.gd:376-383, 479, 584-596`.
- What happens: per spawner per frame, `alive.filter(lambda)` then `walk_distance` (up to 5
  `get_flow` Dictionary returns plus `to_world`), before the cheap budget and cap checks.
  `player_factor()` runs twice per spawner. The laboratory has 30 to 40 spawners.
- Cost: about 2k `get_flow` calls a second plus lambda allocations, even when nothing can spawn.
- Fix: compute walk distance once per `refresh_flow` (5 Hz) and store it on the spawner; check
  budget and cap first; filter `alive` on `enemy_died`.
- Confidence: confirmed.

### 15. Per-enemy tick allocations (web baseline)
- Where: `scripts/enemies/enemy.gd:403-453`, `enemy_manager.gd:550-574, 642-644`.
- What happens: per enemy per physics frame on the host: `_think` allocates Dictionaries;
  `nearest_player` calls `targets()`, which allocates a new typed array (fast shrooms twice);
  `get_flow` and `move_box` return Dictionaries from C++ (`voxel_world.cpp:1582-1588`,
  `voxel_world_nav.cpp:303-361`, with `const char*` keys hashed per call); `separation` allocates
  `[-1,0,1]` literals and an empty array per empty crowd cell.
- Cost: roughly 2 to 3 ms per frame at 60 enemies on desktop, 2 to 3x on web.
- Fix: cache `targets()` per physics frame; hoist constants; share a static empty array; cache
  `get_flow` per enemy at 10 Hz; use `static const StringName` keys in C++ or return packed
  arrays; on web, add a simulation LOD so distant enemies think every 2nd to 4th frame.
- Confidence: code confirmed; cost plausible.

### 16. Light and particle counts on the Compatibility renderer
- Clouds: one OmniLight3D per cloud up to `MAX_CLOUDS = 24` (`scripts/weapons/cloud.gd:401-407`,
  range up to 8 m), and CPU particles of 140 + 12 (spore), 90 (foam), 40 (others) per cloud
  (`cloud.gd:515`): up to about 3.4k main-thread particles.
- Projectiles: `scenes/projectile.tscn` has an OmniLight3D on every projectile, including spit
  globs and remote copies, plus a 10-particle trail (`projectile.gd:68-75`).
- Cubicle: glow and fog enabled on the Environment (`scripts/story/cubicle.gd:1734-1739`), a
  full-screen blur chain per frame on WebGL; 10 unshadowed OmniLights (`cubicle.gd:1713-1722`)
  over large chunk meshes, each fragment paying for up to 8; the computer screen SubViewport at
  `UPDATE_ALWAYS` (`cubicle.gd:1831-1832`) when only a blink and a dots animation change.
- Cost: each omni light adds a forward pass on every chunk mesh it touches; GPU-side, worst on
  integrated GPUs and web. `fire.gd` already does this right with a pool of 3 lights.
- Fix: pool cloud lights to the nearest 2 to 4 (as Fire does), drop lights from spit globs and
  ordinary shots, halve particle amounts on web through a quality setting, gate cubicle glow on a
  setting or off on web, and drive the screen viewport at 10 Hz or on text change.
- Confidence: counts confirmed; renderer cost plausible, not profiled.

### 17. Editor: thumbnails, drawer rebuilds, ghost placement, undo memory
- Thumbnails: opening the Prop tool queues all 355 props (`scripts/editor/prop_thumbnails.gd:
  39-75`, from `editor_hud.gd:1166-1250`), one per frame, each a .vox parse, a mesh build and a
  synchronous `get_image()` GPU readback, in alphabetical rather than visible order. 355 to 700
  hitching frames once per session. Fix: queue visible tiles first, or pre-bake a PNG atlas.
- Drawer: every search keystroke or category click frees and recreates up to 355 Button tiles
  with six theme overrides each, and re-lists the directory (`editor_hud.gd:555, 1222,
  1166-1285`). Fix: build once, filter by `visible`, debounce the search, cache `_prop_names()`.
- Ghost placement: `prop_placement.gd:131-142, 168-193` is cached per cell, but when the ghost
  overlaps, `_push_out` tries up to about 80 offsets, each looping all 1224 props through
  `prop_box`: 60 to 100k calls, a 20 to 100 ms hitch per cell change over furniture. Fix: a
  spatial index or cached prop AABBs; limit tries when the first overlap is a voxel.
- Undo: `scripts/level/level_edits.gd:24-26, 121-130` stores dense `before` and `after` boxes up
  to 8M voxels per step for 100 steps, up to 16 MB per big carve. Heavy for wasm memory. Fix: a
  lower cap on web, sparse or RLE deltas, or a cap on total bytes.
- Confidence: confirmed; ms estimated.

## Priority 3: low

- `Fire._visit` makes up to 12 `get_voxel` GDExtension calls per burning voxel at 4 Hz
  (`scripts/world/fire.gd:256-292`), about 40 to 130k calls a second at `MAX_BURNING = 2500`.
  Capped and acceptable; a C++ batch neighbour query would remove it. `Fire._douse`
  (`fire.gd:219-228`) is O(all burning voxels) and foam calls it every 0.25 s for 6 s; bucket
  `_fuel` by the existing `CELL`.
- `GearModels.build` is uncached (`scripts/weapons/gear_models.gd:77-114`): every thrown flask
  and every pickup, on every peer, runs a GDScript voxel loop, two mesh builds and a new material.
  Loot bursts on enemy deaths spike it. Cache meshes per model path and tint through the material.
- A new ShaderMaterial, Gradient or BoxMesh per projectile or splat (`projectile.gd:58`,
  `voxel_fx.gd:58`, `ranged_shroom.gd:538, 573`). Cache per (size, color).
- The enemy state packet can fragment above about 80 enemies (`enemy_manager.gd:694-702`, about
  1.6 KB); losing one fragment drops the whole unreliable packet. Quantize positions or split.
- Glass shatter scans every prop in the level through `prop_box` (`level_play.gd:751-786`),
  about 0.5 ms each; several per frame from a blast. Reuse the spatial hash from item 2. The flood
  fill itself (`glass.gd:165-192`, up to 6000 voxels in GDScript) is event-driven and fine.
- Player movement sends `_net_state` on ENet channel 0 (`scripts/player/player.gd:685`), the
  same channel as every reliable RPC, so a lost carve or a snapshot burst stalls movement for that
  peer. Move it to channel 1. Rate (30 Hz, unreliable_ordered) is fine. Plausible, not measured.
- `_ladder_direction` (`player.gd:462-472`) makes up to 72 `get_voxel` calls per physics tick,
  and `_input_live()` is evaluated about 8 times per tick. Microseconds; check only on column
  change and compute input once.
- The interact prompt tests about 223 doors and usables every frame (`interactables.gd:16-46`
  from `interact_prompt.gd:94`), rebuilding door AABBs via `to_world`. About 0.1 ms. Optional.
- `VoxWatch` scans res:// at boot even when disabled (`scripts/voxel/vox_watch.gd:20-21`, about
  361 stats), and in editor runs does 9 directory listings and 361 `get_modified_time` calls in a
  single frame every 0.4 s, which skews any profiling done from the editor. Guard `_ready` with
  `enabled` and spread the scan.
- The gameplay terrain shader keeps the editor `discard`s (`shaders/voxel_terrain.gdshader:
  42-47`), which can lose early-Z on GLES3/WebGL2 for the material covering most of the screen.
  Split into a gameplay variant without `discard`. Palette row 2 is fetched twice (lines 66, 82).
- `set_material_hardness` marks nav stale unconditionally (`voxel_world.h:181-184`), so a pattern
  live-reload triggers a full nav rebuild (about 50M reads) in one frame. Editor and live-reload
  only.
- `LevelBuild.storeys` (`level_build.gd:123`) evaluates its default argument eagerly, allocating a
  Dictionary and Array per call from the editor `_process` and many loops.
- Editor HUD per-frame busywork (`editor_hud.gd:129-190`: about 20 `set_pressed_no_signal`, a
  10-replace hint string, a BBCode readout) and wall-drag full-object scans with a dictionary copy
  (`wall_handles.gd:~200-215`); 1 to 4 ms during drags only. Remote editor presence redraws its
  line meshes every frame rather than on state change (`presence.gd:~96-170`).
- UI: `combat_hud.gd:~198-215` assigns `label_settings.font_color` every frame (the setter emits
  `changed` unconditionally, plausible); subtitle and intercom panels re-fit text every frame while
  open (`cubicle.gd:2071-2076`, `intercom.gd:~224-232`, `interact_prompt.gd:~81-96`). Small.

## Checked, fine

So nobody re-investigates these:

- Collision: no physics bodies, Area3Ds or ConcavePolygon shapes anywhere in play. Enemies,
  projectiles, clouds, pickups and the player all use C++ `move_box`, `box_overlaps_solid` and DDA
  `raycast`. Jolt is enabled but idle.
- Voxel edits mark only chunks within one voxel of the edit, never the whole world. The
  background remesh queue respects its 4 ms budget, nearest the camera first. One surface and one
  material per chunk; air and buried chunks are skipped; uniform chunks stay compressed.
  `detach_fragments` is bounded.
- Props in play are stamped into the chunks, so there is no MeshInstance3D per prop. Prop, enemy
  (apart from item 3), character and .vox parses are cached.
- Enemy separation uses a crowd grid rebuilt once per physics frame, not O(n²). Line-of-sight
  checks are throttled (melee within attack range, alarm 0.5 s, tentacle 0.3 s, ranged on spit
  attempts, burning spread 0.5 s). Enemy overlays are shared static materials. Position
  replication is one packed RPC per peer at 10 Hz, unreliable_ordered; statuses only on change.
- Sfx playback is pooled (12 positional, 6 flat, 2 ambience voices), no per-play nodes, no
  per-frame audio push. `muffle_db` is at most one `can_see` per enemy sound within 40 m.
- Fire: visits spread across frames, edits batched to one `set_voxels` per 0.1 s, heat checks at
  2 Hz with a coarse early-out, a fixed pool of 12 flame emitters and 3 lights. Clouds apply
  effects at 4 Hz with the oldest evicted. Weapon tracers use a preallocated pool of 16
  MultiMeshes; hitscan damage is merged per enemy.
- Throttled loops: `LevelPlay._process` (0.6 s, only with pending notes), `InteractRules._process`
  (0.25 s), `_check_fire` (0.5 s), sprinklers (0.5 s), the light cull sort (0.25 s).
- No `get_nodes_in_group` or string `get_node` in hot loops outside `Combat.enemies()` (item 10).
  No per-frame Timers; `create_timer` is one-shot awaits only. No node leaks across level changes;
  static caches are bounded by asset count (apart from item 3).
- JSON is parsed only at load and on a joiner's `decode_info`, never re-parsed in play.
- Lights: shadows are off on every light in the laboratory, the cubicle and `player.tscn`. No
  SSAO, SDFGI, volumetric fog, MSAA, FSR or shadow atlas overrides. `lab.tscn` has one
  WorldEnvironment with glow, depth/height fog and filmic tonemap. `max_renderable_lights=64`
  leaves headroom. `driver.windows="d3d12"` is ignored under Compatibility.
- Config: `physics_ticks_per_second` default 60, no vsync or `max_fps` override, no `[audio]`
  section (44.1 kHz mix, per-voice resample from 22.05/11.025 kHz). Web preset: no threads,
  extensions on. Fine.
- Cubicle `_process`: a few float adds, visibility sets, a handful of AABB ray tests. No voxel
  work per frame; `remesh_all_now()` runs once at build. Story, waiting room, ending, experiment,
  shift save, intercom and the lab HUD have no meaningful per-frame work.
- Editor: brush dabs throttled (`DAB_INTERVAL = 0.06`) and grouped into one undo step; ghost
  meshes cached by `name:facing`; handles and gizmos are fixed nodes moved, not recreated;
  presence sends at 10 Hz on change; no per-frame JSON or autosave; cut cap rebuild is
  dirty-flagged. `scripts/tools/*` are offline CLI tools, not runtime. Editor shaders are trivial.
- FX: `VoxelFx` caches cubes, curves, splats and stains; bursts and debris free themselves with
  capped particle counts; FX shaders are vertex-only with trivial fragments.

## Suggested order

1. Items 1 and 2 together: coalesce remeshes per frame, batch pellets into one carve, bucket
   the asset rescan. These are the per-shot costs and the biggest web win.
2. Item 3: a one-line cache-key fix that stops a leak.
3. Item 4: lazy or offline SFX, because it is the first thing a web player waits on.
4. Items 7, 8, 14: the constant per-tick loops, all cheap to fix with a precomputed list.
5. Item 6: dirty-chunk saves, which also fix the join stall and the `_edit_base` memory.
6. Item 9's `orient` cache and a loading frame.
7. Items 10 to 13, 15, 16, then the editor items when editing the laboratory feels slow.

Before any of this, run the laboratory on the web build and read `get_stats()` after a shotgun
blast, a rocket and a flow refresh, to turn the estimates into numbers.
