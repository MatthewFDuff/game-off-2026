# Prop build plan

Drafted 2026-11-03 from `docs/prop-gaps.md`. Builds everything in that document except the security
turret. Six packages; A, B and C run first in parallel, the art packs (D) and interactables (E)
once A has landed, and the dressing pass (F) last.

Rules that apply to every package:

- Everything is voxels or pixels. **No dither**, no alpha except where real transparency is needed.
- Placeholder art is drawn by generator functions and exported to `assets/vox/...` with
  `godot --headless --path . --script res://scripts/tools/export_vox.gd` (never `--force`: the
  team edits those files by hand). After export the `.vox` is the source of truth.
- Props never block doorways, nothing spawns before the story event, spawns are never in view.
- Every voxel edit in play goes through `WorldSync`. The host decides, peers replay.
- The Compatibility renderer draws about 32 lights; `LevelView` culls to the 20 nearest.
- Tests are headless: `godot --headless --path . --script res://tests/<name>.gd`. Each package
  adds or extends one and runs it, plus the suites it could have broken.
- The working tree is shared with other sessions and other agents. Nobody commits, stages, stashes
  or checks out. Edit only the files your package names; re-read a shared file before editing it.

## A. Prop packs, the ceiling, light fixtures

Engine first, so the art packs can be written in parallel without colliding.

1. **Packs.** `PropCatalog.entries()` is one long function and `CATEGORIES`, `MOUNTS`,
   `LevelSchema.ASSET_VALUES` and `DEFAULT_USES` are four tables in two files. Move to packs:
   `scripts/world/packs/<name>_pack.gd`, each a `RefCounted` with static `CATEGORY: String`,
   `MOUNTS: Dictionary` (prefix to mount), `VALUES: Dictionary` (prefix to $), `USES: Dictionary`
   (prefix to use), and `static func entries(add: Callable) -> void` calling
   `add.call(name, func(p: Props, o: Vector3i) -> void: ...)`. `PropCatalog.PACKS` lists the pack
   scripts; `entries()`, `category_of()`, `mount_of()`, `LevelSchema.default_value()` and
   `default_use()` merge the packs' tables after the built-in ones. Move the existing catalog as is
   into `scripts/world/packs/base_pack.gd` (one pack, no behavior change). Drawing helpers that a
   pack needs (`box`, `_begin`, `_legs`, `_glass_panes`, the small gear) stay on `Props`; make
   `_begin` public as `begin` and keep `_begin` as an alias.
2. **Ceiling mount.** `PropPlacement` already handles mount `"ceiling"`; nothing in `MOUNTS` uses
   it. Add `"ceiling"` and `"any"` to the pack tables, make sure the editor's ghost, `touches`,
   `problems` (Check level) and `LabBuilder` (a `ceiling_prop(room, name, fx, fz, facing, fields)`
   in `LabLayout`, placed with its top flush under the ceiling, and keep-out respected) all work,
   and that `tests/editor_prop_test.gd` covers placing one under a ceiling and refusing it on a
   floor.
3. **Ceiling pack** (`ceiling_pack.gd`, category "Ceiling"), the proving case, in 10-voxel modules
   so runs line up on the 1 m grid: `duct_straight`, `duct_corner`, `duct_tee`, `duct_riser`,
   `duct_insulated` (cloth wrap), `duct_drip` (with a hanging drip), `duct_end_grille`,
   `pipe_bundle_straight`, `pipe_bundle_corner`, `pipe_valve` (a wheel), `cable_tray_straight`,
   `cable_tray_corner`, `cable_tray_sag`, `ceiling_tile_grid` (a 20 x 20 panel), `ceiling_tile_missing`,
   `ceiling_tile_hanging`, `vent_diffuser`, `return_grille`, `extractor_fan`, `sprinkler_head`,
   `smoke_detector`, `speaker_horn`, `security_camera`, `hazard_beacon`, `chain_hoist`,
   `gantry_rail`, `service_hatch` (the ceiling twin of `vent_grate`, where ceiling spawners come
   from).
4. **Light fixtures** (same pack): `fixture_troffer` (a 12 x 2 x 6 panel with a `LAMP` face),
   `fixture_strip`, `fixture_bulkhead` (caged, wall or ceiling, `any`), `fixture_pendant`,
   `fixture_emergency` (`EMERGENCY` material, so it only glows on backup power),
   `fixture_dead` (dark glass). `LAMP` and `EMERGENCY` voxels already follow the power state
   through the shader's emission groups, so fixtures light up and go dark with the room. The light
   marker stays the light source; `LabBuilder` places a fixture prop under each facility light it
   makes and an emergency fixture at each emergency light.
5. **Camouflage rule** is data, applied in F: every `on_ceiling` spawner sits under a
   `duct_insulated` cluster; give `ceiling_cloud`'s placeholder sac the insulated duct's cloth
   color (in `EnemyModels`) so it reads as lagging until it moves.

Files: `prop_catalog.gd`, `level_schema.gd` (value and use lookups only), `props.gd` (helpers),
`prop_placement.gd`, `lab_builder.gd`, `lab_layout.gd` (the helper only), new `packs/`,
`enemy_models.gd` (sac color), `tests/editor_prop_test.gd`, `export_vox.gd` if needed.

## B. Glass that shatters as a pane

1. `scripts/world/glass.gd` (`class_name Glass`, a node on `Lab` like `Fire`). On the host it
   listens to `WorldSync.carved` and `voxels_set`: when the removed set contains `GLASS`, it
   flood-fills (6-connected, cap 6,000) the `GLASS` still connected to those voxels and clears it
   in one `world_sync.set_voxels` batch. Debris burst scaled by pane size, a crash sound (`Sfx`)
   with a layered big-pane variant.
2. `GLASS_TEMPERED` material (hardness 2, slightly bluer): a pane of it survives two hits, each
   hit turns the pane to `GLASS_CRACKED` (a pattern material with crack lines, 1 px = 1 voxel) and
   the third shatters it. The host keys panes by their lowest voxel. A blast (explosive ammo,
   exploding shroom) shatters any glass in one go.
3. Shards: after a shatter, a one-voxel-thick scatter of `GLASS_SHARDS` lands on the first solid
   surface under the pane's footprint (about 30% coverage, deterministic from the pane key).
   Walking on shards plays a crunch (hook the player's footstep material, add one if there is
   none); enemies ignore it.
4. Props: breaking glass costs payroll as any asset. A prop whose glass pane shatters reacts by
   name prefix through `LevelPlay`: `spore_tank` releases a spore cloud (`Cloud` as the spore
   shroom's), `clone_vat` drains (its liquid voxels go), `fixture_*` goes dark (its `LAMP` voxels
   turn to `CHAR`), the waiting room's aquarium (if it has one) spills water voxels. The existing
   `glass_case` rule keeps working (its `count_matching` sees the pane gone).
5. `tests/glass_test.gd`: a scratch room with a 20 x 20 ordinary pane, a tempered pane and a spore
   tank; one basic shot shatters the whole ordinary pane and leaves shards; three shots the
   tempered one; the spore tank's pane spawns a cloud; the payroll charged the pane; a peer sees
   the same voxels (headless host and client as `tools/net_test.sh` does, if cheap; otherwise the
   host-side check).

Files: new `glass.gd`, `voxel_materials.gd` (three materials, pattern PNG under `assets/patterns/`),
`lab.gd` / `lab.tscn` (the node), `level_play.gd` (prop reactions), `player.gd` (footsteps),
`sfx.gd`, new test. Do not touch `prop_catalog.gd` or `level_schema.gd` beyond a one-line value.

## C. Mycelium networks

The user's ask: place mycelium so that tendrils connect by themselves into tentacle and root
shapes. Marching squares is the right instinct; in a voxel world the equivalent is an isosurface
sampled straight into voxels: every node is a sphere, every link a tapered capsule, the network is
their smooth union, and a voxel is solid where the distance field is inside. That gives organic,
auto-connected roots with no mesh step.

1. **Marker type `mycelium`** in `LevelSchema.MARKERS` (color a sickly cyan). Fields: `radius`
   (voxels, 1 to 12, default 4), `reach` (link range in voxels, default 40), `links` (most links
   per node, default 3), `sag` (0 to 1: links droop in the middle, for hanging tendrils), `glow`
   (0 to 1: how much of the skin is the pulsing vein material), `spread` (0 to 30 voxels: film
   grown on the surface the node sits on). It stands on floors, walls and ceilings like other
   markers (placement by the aimed face).
2. **The network** (`scripts/world/mycelium.gd`): nodes link to their nearest `links` nodes within
   `reach` (symmetric, no duplicate edges, deterministic). Voxelize a connected cluster into its
   bounding box with a smooth-min union of spheres and capsules whose radius tapers from one node's
   to the other's, a little low-frequency noise on the surface so it is not a tube, and `sag` as a
   downward bow. Material by depth: `ROOT` core (dark), `MYCELIUM` skin (pale, dull), with
   `MYCELIUM_GLOW` veins as a few spiral stripes along each link and spots on the nodes,
   proportioned by `glow`. `spread` adds a one-voxel film of `MYCELIUM` with `MYCELIUM_GLOW`
   filaments on the node's surface, branching outward (a random walk along the surface, seeded by
   the node's id). All three materials: hardness 1, flammable like the shroom materials.
3. **Where it goes.** Stamped the way props are: into the voxels when play starts (only into air,
   never into walls or props), and drawn in the editor as a mesh from `build_model_mesh` per
   cluster, through `LevelView`, so moving a node redraws its cluster live. The mesh is swapped
   back for voxels on play. Clusters cap at 60,000 voxels; a bigger one is split by its links.
4. **Obstacles.** Root ridges stop players at the normal step height; a knot taller than the jump
   needs a hole shot or burned through. Enemies path around or dig (hardness 1), as they do with
   substrate.
5. **Pulse.** A fourth emission group in `VoxelMaterials` / the terrain shader: `PULSING`
   materials' emission swings with time and position (a slow wave along world X plus Z, so it
   travels), amplitude set by a shader uniform `pulse_amount` that `LevelPlay` raises for a few
   seconds on `t_m4_mother_dead`'s approach, on intercom lines and when the mommy is hurt (a
   `pulse(strength)` on `Mycelium`, host-called, synced). Enemy glow is unchanged, so the pulse
   itself is the tell between decor and enemies.
6. **Wither.** A trigger action `wither` (`LevelPlay` actions): the host turns every mycelium
   material to `MYCELIUM_DEAD` (grey, no emission) and over 10 s removes voxels from the far ends
   inward (by distance from the nearest node), in `set_voxels` batches every 0.2 s, with a dry
   crumble sound and grey debris. The lab's `t_m4_mother_dead` gets this action in F.
7. `tests/mycelium_test.gd`: three nodes link into a Y, the cluster is one connected solid, links
   taper, two nodes beyond `reach` stay apart, a hanging node with `sag` bows below the straight
   line, `spread` grows film only on the surface and only into air, a stamped network never
   overwrites a wall or prop voxel, the player is stopped by a knot and steps over a ridge, fire
   burns it, wither removes it all within 12 s, and a peer's voxels match the host's.

Files: new `mycelium.gd`, `voxel_materials.gd` (four materials, the group), `voxel_terrain.gdshader`,
`level_schema.gd` (the marker), `level_view.gd`, `level_play.gd` (stamp on start, the action, the
pulse), `editor_hud.gd` only if the marker inspector needs a field type it lacks, `lab_layout.gd`
(a `mycelium(room, fx, fz, fields, up)` helper), new test.

## D. Art packs (after A)

Each pack is its own file under `scripts/world/packs/` plus one line in `PropCatalog.PACKS`, so the
four packs can be drawn in parallel. Every prop gets a category, a mount, a value and (where it
reads or opens) a use, is drawn inside its footprint (the exporter warns otherwise), and is exported.
Sizes are voxels at 0.1 m: a door is 22 tall, a person 18, a desk 7 to 8. Reuse the gear helpers.

- **Pack D1, lighting and corridors** (`lighting_pack.gd`, `corridor_pack.gd`): exit sign (glows,
  `EMERGENCY`), rotating beacon, floor path light, glow arrow decal (a one-voxel floor plate),
  fluorescent tube (lit, flickering variant is the light marker's flicker, dead), swaying pendant,
  bench lamp, UV lamp, blacklight poster, bioluminescent plant pot (steady glow, never pulsing);
  handrail (straight, corner), wet-floor sign, caution tape post and run, floor decal arrows, room
  number plate, extinguisher cabinet (glass front), evac map, exit arrow sign, bollard, mop and
  bucket, cleaning cart.
- **Pack D2, machine rooms** (`compute_pack.gd`, `plant_pack.gd`, `mine_pack.gd`): server rack
  (closed, open with blinking `SCREEN` dots, dead), cable cage, CRAC cooling unit, raised floor
  tile (lifted, with cable below), patch panel, UPS cabinet, tape library; pump housing, water tank
  (round, square), pipe gallery segment, valve stand, cooling tower stack, catwalk segment with
  rail, boiler, water heater, electrical cabinet, breaker panel (wall), junction box (wall), fuse
  box, transformer, compressor; timber support frame, mine cart, rail segment (straight, curve),
  lantern (wall, hanging: `any`), stalactite (ceiling), stalagmite, rock pile, drill rig, ore
  bucket, rope coil, rope hanging (ceiling).
- **Pack D3, people spaces** (`kitchen_pack.gd`, `bathroom_pack.gd`, `office_pack.gd`,
  `exec_pack.gd`): serving counter, tray stack, cafeteria table (long, with attached stools),
  stove, steel prep table, dish rack, dishwasher, bin row; toilet stall (wall + door), toilet,
  urinal (wall), sink with mirror (wall, mirror as `GLASS_TEMPERED` over `STEEL`), shower cubicle,
  hand dryer (wall), paper towel dispenser (wall), locker bench, suit locker; cubicle partition
  (straight, corner), filing cabinet (2 and 4 drawer), printer station, copier, coat rack, standing
  desk, monitor (single, on arm), keyboard and mouse (desk-top), mug, photo frame, lunch box,
  jacket on chair, cot; boardroom table, executive chair, trophy shelf, safe (container), plush
  couch, drinks cabinet, globe, potted tree.
- **Pack D4, security, hazard and story** (`security_pack.gd`, `decon_pack.gd`,
  `specimen_pack.gd`, `story_pack.gd`): turnstile, metal detector gate, guard desk with monitors,
  barrier arm, gatehouse hut panel, badge reader (wall), lanyard on desk, camera dome (ceiling);
  airlock door pair uses `door_security`; decon shower tunnel, hazmat suit rack, suit locker,
  hazmat sign (wall), sprayer, boot wash; animal cage (small, stack), specimen tank (tall glass),
  dissection table with drain, cold-store rack, body bag (on table, on floor), morgue drawer wall,
  biohazard bin, incinerator furnace, dumpster, trash chute (wall); Fung AI posters (6 texts,
  wall; the text drawn in pixel letters with `PixelFont` if a pixel-text helper is available,
  else blocks), org chart, mission statement, employee of the month board, mascot standee, the
  payroll ticker display (`SCREEN`), a wall of past-operator photos, a vat with a figure in it
  (`clone_vat_occupied`), overturned desk, overturned table, barricaded door (planks across),
  scratched note (wall), skeleton in a suit, skeleton overgrown; **overgrown twins** of desk,
  chair, locker, terminal, shelf_storage_a, table, couch, server rack (the base model with
  `MYCELIUM` growth and a few `MYCELIUM_GLOW` veins, named `<base>_overgrown`); cocoon (floor,
  hanging: `any`, with a name tag voxel strip).

Each pack agent also appends its props to `docs/prop-gaps.md`'s "What exists today" (a one-line
count per pack) and runs `tests/vox_test.gd` and `tests/editor_prop_test.gd`.

## E. Interactables (after A and B)

Props with behavior, in `interact_pack.gd` for the art and `level_play.gd` / `interactables.gd`
for the rules. Priority order; do what fits, and report what is left:

1. `switch` use (a generic lever, button, light switch, breaker lever, alarm pull): E fires
   `on_use` every time (or once with `once`), with the existing trigger `actions` doing the work
   (`power=`, `lock=`, `activates`, and new `lights=<room id>:off|on` which `LevelView` applies to
   the lights inside that room's box). The alarm pull station activates a horde and fires its
   trigger; the breaker panel cuts a room's lights.
2. `vendor` use: vending machine charges `price` to the payroll and drops `contents` (a snack
   item, a small heal, new `snack` pickup); shooting its glass drops one snack too and bills it as
   damage, as the glass rule already does. Coffee machine and water cooler: a `buff` field
   (`speed` or `reload`, 20 s) on use.
3. `eyewash` use: clears Poisoned and Burning on the user. Emergency shower: the same plus
   douses fire around it.
4. `defib` use: revives the nearest downed teammate within 3 m (if revive exists, reuse it; else
   heals the user).
5. **Fire extinguisher** (a floor prop): shot or caught in fire it bursts into a foam cloud (new
   `Cloud` kind `foam`: 4 m, 6 s, slows enemies to half, clears spore and poison clouds it
   overlaps, douses fire). E picks it up as a throwable (`flask_foam`) if the flask system takes a
   new kind cheaply; otherwise shooting only.
6. **Gas cylinder**: shot once it vents and skids 6 m in a random direction knocking enemies
   back; burning or blasted it explodes (reuse the exploding shroom's blast).
7. **Hanging crate**: a crate under a chain of `CHAIN` voxels from a `chain_hoist` ceiling prop.
   Shooting the chain detaches the fragment (`detach_floating` does this already); add crush
   damage to enemies and players under a falling fragment heavier than 50 voxels.
8. `flip` use: a table or desk swaps to its `_flipped` twin (the pack draws both) as cover.
9. **Printer**: a `note` whose text is printed as a `paper` pickup on the floor (lore pages).
10. **Radio / jukebox**: toggles a looping diegetic track and, while on, pulls enemies within 20 m
    toward it (a lure point the `EnemyManager` prefers over players it cannot see).
11. **Rubber duck**: E squeaks; a squeak is a 10 m lure for 4 s.
12. **Barricades**: if `BuildPieces` still works in play, `plank_stack` gives 4 planks on use and
    E on a doorway with planks nails a plank piece across it (enemies dig through it in about 10 s
    each, players can hop it); if the old build system is gone, skip and say so.
13. **Sprinkler**: a wall `switch` with action `sprinkle=<room>`: douses fire and clears clouds in
    the room for 8 s, and the room's lights flicker.
14. Live wire, topple shelf, carts and chutes are last and optional.

`tests/interact_test.gd` grows with one check per use that landed. The payroll report (the ending)
lists vending charges and forced doors as it lists damage.

Files: `interact_pack.gd`, `level_schema.gd` (`USES`, fields), `level_play.gd`,
`interactables.gd`, `cloud.gd`, `enemy_manager.gd` (lure), `inventory.gd` / `item_manager.gd`
(snack, paper, foam), `ending.gd` (payroll lines), `sfx.gd`, the test.

## F. Dressing the laboratory (after everything)

Edit `scripts/tools/lab_layout.gd` only (it is the plan as data), regenerate with
`godot --headless --path . --script res://scripts/tools/build_laboratory.gd -- --force`, then run
`tests/laboratory_test.gd` (about 10 min) and `tests/laboratory_play_test.gd`.

- Ceilings: duct runs along every corridor and route room, pipe bundles in the cooling plant and
  grow halls, cable trays in the server hall and ops, tile grids with missing tiles in admin, a
  fixture at every light (A does this in the builder), `duct_insulated` over every `on_ceiling`
  spawner and in at least as many places without one.
- Room sets: server racks and raised floor on -2, cooling plant pipes and tanks, bathrooms with
  stalls, the cafeteria counters in the break room, turnstile and guard desk in the gatehouse,
  decon racks in the airlock, cages and the morgue wall in containment, timber and carts in the
  dig, executive dressing in the security office, printers and filing cabinets in the bullpen.
- Corridors: handrails, signs, room plates, extinguisher cabinets, evac maps, exit signs.
- Story: posters getting darker by floor, the payroll ticker in the lobby, the operator photo wall
  by the first vat, cocoons from -3 down, skeletons in the sample room, overturned furniture and
  barricaded doors after the outbreak point.
- Mycelium by floor: 0 none; -1 two or three small clusters under vents, `spread` film in grow
  hall 2; -2 veins in the server hall and inference lab, one hanging cluster in the cooling
  plant; -3 tendrils in the dissection lab and gallery, a root wall across the gallery's optional
  side passage, overgrown twins replacing a third of the furniture; dig: dense networks on every
  wall, the mother's dais wrapped in `ROOT`, `glow` high. `t_m4_mother_dead` gets `wither`.
- Interactables: an alarm pull in the lobby (a trap and a shortcut), a breaker panel in
  electrical, the vending machines in the break room priced, an extinguisher cabinet per floor,
  gas cylinders in the wet lab and cooling plant, a hanging crate in the lift dock and the
  generator hall, a radio in the bullpen, a printer in ops, the duck on the gatehouse desk.
- The cubicle and waiting room get a tile ceiling, a troffer each, the exit sign and a poster.

Update `docs/lab-design.md`'s status and `README.md`'s prop and marker lists. Hand play-test
notes go to the user; nothing here is hand-tested until they do.
