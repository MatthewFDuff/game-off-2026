# Props, spaces and interactions the game still lacks

Drafted 2026-11-03 from a read of `PropCatalog` (about 64 props), the built `levels/laboratory`
(423 props, 74 rooms), `docs/lab-design.md` and `docs/mechanics.md`. This is a menu of
possibilities, not a plan. "Needs" means engine work beyond drawing a `.vox`.

## What exists today

- The catalog is office and lab furniture: desks, chairs, benches, shelves, lab gear, lockers,
  crates, barrels, vents (a wall grate and a floor duct), doors, terminals, medkit and ammo
  stations, one generator, a glass case, clone vats, grow beds, specimen props.
- The lab's top counts: chairs 35, doors 51, shelves 40, spore tanks 20, terminals 19, lockers 15,
  desks 15, barrels 19. Seventy-four rooms share about 60 prop kinds, so rooms read alike.
- **Nothing lives on the ceiling.** Light is 217 invisible light markers. The only overhead
  geometry is a pipe strip in the old `facility_builder.gd`. Prop mounts are `floor`, `wall` and
  `door` only (`prop_catalog.gd` MOUNTS), so a ceiling prop cannot even be placed.
- Mycelium appears only as grow-bed shrooms, shroom pots and the cavern's stems. There is no
  infestation, no spread with depth, no growth on walls, floors or props.
- Glass is a hardness-1 material. A shot or blast removes it a few voxels at a time, like wood.
  `glass_case` is the only glass with a rule, and that rule is "press E to smash".
- Every interactable is a press-E container, note, terminal, station, door or the generator.
  Nothing reacts to being shot except explosive barrels and the fire system.

## 1. The ceiling and plenum

Reason: a sterile spore lab needs air handling, and a busy ceiling hides ceiling-spawning enemies
so they are not obvious until they drop.

- **Ceiling mount type** for props (prerequisite). Hangs from the ceiling voxel above, like the
  wall mount does for walls.
- **Duct runs**: rectangular sheet-metal trunk ducts with joints and flanges, as straight, corner,
  T and riser pieces in 10-voxel modules. Variants: bare metal, insulated (fabric wrap), and
  dripping (condensation, a puddle below).
- **Exposed pipe bundles**: three to five parallel pipes in copper, steel and green, with brackets
  and valve wheels. Run along corridor ceilings and across the cooling plant.
- **Cable trays**: ladder-style trays with bundles of black and coloured cable, a few sagging.
- **Ceiling tile grid** with some tiles missing or hanging, showing the plenum above. Doubles as a
  place for ceiling enemies to emerge from.
- **Vent diffusers** (flush ceiling grates), return air grilles and extractor fans (a slowly
  turning blade that stops when power drops).
- **Light fixtures**: fluorescent panels (the visible face of today's invisible lights), caged
  bulkhead lights, strip lights, and flickering and dead variants. Fixtures can be shot out (see
  glass).
- **Sprinkler heads, smoke detectors, speaker horns** (the intercom `speaker` markers get a body),
  **security cameras** that turn to follow you, **hazard beacons** that spin on alarm.
- **Hanging gantry and chain hoist** in storage and the generator hall.
- **Camouflage rule**: ceiling spawners always sit under a cluster of insulated duct or pipe
  lagging, and the `ceiling_cloud` sac is coloured like that lagging until it drops. Players who
  look up learn to read the pattern, and a plain ceiling means safe.
- **Ceiling hatch spawners**: a service hatch or missing tile that visibly drops open when shrooms
  come through, the same way the floor vent grate works.

**Status (A), 2026-11-03.** Props now come in packs (`scripts/world/packs/<name>_pack.gd`, listed in
`PropCatalog.PACKS`; the old catalog is `base_pack.gd`). The ceiling mount works end to end: the
editor ghost, Check level (`PropPlacement.problems`, also for `any` props) and the lab builder
(`LabLayout.ceiling_prop`, slid along the ceiling clear of doorways and props). `ceiling_pack.gd`
(category Ceiling) draws 33 placeholders: ducts (straight, corner, tee, riser, insulated, drip, end
grille), pipe bundles (straight, corner, valve), cable trays (straight, corner, sag), ceiling tiles
(grid, missing, hanging), vent diffuser, return grille, extractor fan, sprinkler, smoke detector,
speaker horn, security camera, hazard beacon, chain hoist, gantry rail, service hatch and the
fixtures (troffer, strip, bulkhead, pendant, emergency, dead). `LabBuilder` hangs a troffer over
each facility light under a ceiling and an emergency fixture at each emergency light (takes effect
when the lab is rebuilt in F). The `ceiling_cloud` sac is the insulated duct's CLOTH. Not built: the
fan turning, cameras following, beacons spinning, hatches dropping open, a puddle under the drip,
and no CHAIN or lagging material (STEEL links and CLOTH stand in).

## 2. Mycelium, growing denser toward the source

Reason: the colony is the story. It should be the level's depth gauge, a mood and lighting tool,
and sometimes an obstacle.

- **Infestation level per room (0 to 4)**, a slider in the editor, defaulted by floor and distance
  to the mother:
  - 0: nothing (floor 0).
  - 1: a few thin filaments in corners and under vents.
  - 2: wall veins, floor film, one fruiting cluster per room.
  - 3: ceiling tendrils, root ridges across floors, props cocooned, doors wrapped.
  - 4: the room is mostly mycelium, with only a route cut through it (the cavern).
- **Voxel growth materials**: `MYCELIUM` (pale, dull), `MYCELIUM_GLOW` (the pulsing veins) and
  `ROOT` (thick, dark). Hardness 1 and flammable, so the existing fire system burns them. No
  dither: floor growth is an opaque film one voxel thick, glow is emission, not alpha.
- **Floor and wall film and veins** that branch along corners, door frames and prop bases.
- **Hanging tendrils**: strands from the ceiling, 5 to 25 voxels, some reaching the floor. Pure
  decoration at level 2 to 3. At level 4 they cluster so thickly they screen sight lines.
- **Root ridges and knots on the floor**, 2 to 5 voxels high. Low ones are stepped over at the
  existing step height. Taller ones need a jump. A wall of root across a corridor is a real
  obstacle: climb a knot, burn it, or shoot it out.
- **Overgrown props**: furniture wrapped in mycelium (cocooned desk, chair, locker, a terminal with
  veins crawling over the screen). A prop-level overgrown flag could swap in the overgrown twin.
- **Sealed doors**: a door wrapped in root that must be burned or blasted. Fits the fire mechanic
  and gives flame ammo a puzzle use.
- **Pulse lines**: the colony talks by glowing. Veins pulse toward the mother in slow waves, faster
  when she is hurt or when the intercom speaks. They show the route to the cavern like a compass.
- **Fruiting bodies**: cap clusters that puff harmless spores when you pass, and in a few places a
  real spore cloud (ties to the spore shroom).
- **Glow decoys**: enemies are emissive (`SHROOM_SPOT`, `SHROOM_EYE`). To keep decor from hiding
  enemies unfairly, give decor a steady slow cyan-green and enemies a distinct hue or a pulse.
  Decor glow distracts at range and is clearly different up close.
- **Cocoons**: human-shaped wrapped bodies in walls and hanging from the ceiling at level 3 to 4,
  with name tags. Ties to the payroll theme.
- **Wither**: when the mother dies (`t_m4_mother_dead`), mycelium greys, shrinks and crumbles to
  debris. `lab-design.md` lists the wither as not built; this is its payoff.
- **Dormant tentacle roots**: look like decor until you walk past (a hide-in-plain-sight variant
  of the existing tentacle enemy).

Needs: new materials in `voxel_materials.gd`; a **growth pass** (an editor brush plus a post-build
auto pass that grows from sources, weighted by room level and following surfaces) because nobody
should draw this by hand; a Growth editor tool and per-room level field; wither as a timed
material swap; the ceiling mount for tendril props.

**Status (C), 2026-11-03:** mycelium networks landed (`scripts/world/mycelium.gd`, plan section C).
A `mycelium` marker (radius, reach, links, sag, glow, spread) placed on any floor, wall or ceiling
links to its nearest nodes and the network is voxelized as a smooth union of spheres and tapered
capsules with surface noise: ROOT core, MYCELIUM skin, MYCELIUM_GLOW spiral veins and node spots,
and a seeded random-walk film for `spread`. Drawn as live per-cluster meshes in the editor, stamped
into air at play start (clusters capped at 60,000 voxels, split along links). Veins are the new
`PULSING` emission group: a travelling wave whose strength `Mycelium.pulse` raises (intercom trigger
lines, the mommy getting hurt, the `pulse[=strength]` trigger action). The `wither` trigger action
greys it all (MYCELIUM_DEAD) and crumbles it tips first over 10 s. Burns like the shrooms. Tests:
`tests/mycelium_test.gd`. Not done here: the per-room infestation level, the Growth editor brush
and auto pass, overgrown props, sealed doors, fruiting bodies, cocoons and dormant roots; the lab's
`t_m4_mother_dead` still needs `wither` (package F).

## 3. Glass that shatters all at once

Reason: voxel-by-voxel glass looks like wood. A pane should go in one satisfying event.

- **Pane detection**: flood-fill connected glass voxels from the hit voxel (capped at a few
  thousand). On any damage above a threshold (shot, melee, blast, thrown flask) the whole pane
  breaks in one frame, as one `VoxelWorld.set_voxels` batch.
- **Shatter effect**: shards fly outward from the impact, a layered crash sound that enemies hear
  (loud glass can call attention), then settle as small debris. Reuse `VoxelDebris`.
- **Tempered glass** (lab and vault windows) takes three hits and cracks visibly between. Ordinary
  glass goes in one.
- **Glass dividers and walls**: lab partitions, observation windows, test chamber 1's
  floor-to-ceiling wall, door vision panels.
- **Fragile glass props**: specimen jars (liquid pours out and reacts, as the sample materials
  already do), vials, beakers, spore tanks (release a spore cloud), clone vats (drain and spill),
  the waiting-room aquarium (floods the floor), monitor screens, light fixtures (the room darkens).
- **Shards underfoot**: loud when walked on (alerts enemies), optional small damage. A one-voxel
  scatter that stays on the floor.
- **Glass as a mechanic**: a sealed observation window that shatters to open a shortcut, a
  skylight shot to drop shards on a crowd, a case you cannot open any other way.
- **Payroll**: glass breaks cost like any asset, priced by pane size.

**Status (B), 2026-11-03.** Landed: `scripts/world/glass.gd` (`Glass`, a node on `Lab`): on the
host, a carve or batch that takes pane glass flood-fills the rest (6-connected, cap 6,000, GDScript:
0.6 ms for a 20 x 20 pane, 9.4 ms at the cap) and clears it in one `WorldSync.set_voxels` batch a
frame later, with a 30% one-voxel `GLASS_SHARDS` scatter on the surface under it, debris scaled by
size and `glass_shatter` / `glass_shatter_big`. `GLASS_TEMPERED` (46) cracks to `GLASS_CRACKED`
(47, pattern `assets/patterns/glass_cracked.png`) on the first hit and shatters on the third; a
blast (carve radius 0.5 m or more) shatters any glass. Shards (48) crunch underfoot (player
footsteps, enemies ignore it). `LevelPlay.glass_shattered`: loose glass bills $1 a voxel as
`glass_pane` (props bill their own voxels as assets); `spore_tank` vents a spore cloud and drains,
`clone_vat` drains, `fixture_*` turns its `LAMP` to `CHAR`, `aquarium*` spills a puddle. Tempered
and cracked glass are see-through for line of sight. Test: `tests/glass_test.gd`. Not done: enemies
hearing breaking glass, shard damage, flasks breaking glass (they don't carve).

## 4. Interactive objects for fun

- **Hazards to weaponise**
  - Fire extinguisher: a foam cloud that blinds and slows shrooms and clears spore and poison
    clouds.
  - Compressed gas cylinders: rocket off when shot, explode when burning.
  - Chemical drums, acid spill, leaking pipe: pools that damage or coat things.
  - Live wire and junction box: electrify a wet floor puddle.
  - Sprinklers: a button or shot floods the room, which extinguishes fire and washes spore clouds
    but shorts lights and screens.
  - A Fung AI containment emitter in the test chambers.
- **Environmental kills**
  - A crate or pallet on a chain: shoot the chain to drop it on a horde.
  - Shelves that topple when shot at the base.
  - Tables you flip with E for cover.
  - Carts, trolleys and office chairs you push or shoot into enemies.
  - A conveyor belt and incinerator chute.
- **Switches and machinery**
  - Light switch, breaker panel, fuse box: cut a room's power.
  - Valves and levers: steam vents, flooding a trench, opening a drain.
  - Alarm pull station: calls a horde but also unlocks something, a risk and reward.
  - Fung AI security turret: friendly at first, hijackable at a terminal.
  - Lift call buttons, dumbwaiter, laundry and trash chutes: one-way shortcuts.
  - Zipline or rope.
- **Consumables and services**
  - Vending machine that bills payroll for a snack (small heal), or that you shoot for a free
    snack and get billed for anyway.
  - Water cooler and coffee machine for short buffs.
  - Eyewash station and emergency shower: clear Poisoned.
  - Fung Bucks tokens as an ammo shop (the debt joke).
  - Defibrillator that revives a downed co-op partner.
- **Toys**
  - Printer or copier that spits a lore page or jams.
  - Radio or jukebox that plays music and attracts shrooms.
  - Arcade cabinet, break-room TV, a whiteboard you can scrawl on.
  - A squeaky rubber duck that works as a distraction.
  - Security monitors showing live camera views of other rooms.
- **Barricades** (`build_pieces.gd` already has plank, sandbag, concrete block, sheet metal):
  place boards across a doorway, shrooms chew through, repair between waves. A strong fit for a
  horde shooter.

**Status (E), 2026-11-03.** Interactables (plan section E) landed in `scripts/interact/interact_rules.gd`
(`InteractRules`, LevelPlay's "Rules" child) with the art in `scripts/world/packs/interact_pack.gd`
(tab Interact). New uses in `LevelSchema.USES`: `switch`, `vendor`, `eyewash`, `defib`,
`extinguisher`, `flip`, `printer`, `radio`, `squeak`; new prop fields `once`, `price`, `buff`; packs
can now give per-name field defaults (`FIELDS`, merged by `LevelSchema.new_prop`). New trigger
actions `lights=<room>:off|on|flicker` and `sprinkle=<room>` (a room or a trigger volume). Landed:
1 switches (alarm pull also starts a horde, never while dormant; breaker / fuse box / light switch
with no `on_use` toggle their room's lights), 2 vendors (vending machine bills the payroll's new
Purchases section and drops a `snack`; `vending_machine_glass` shot drops one more and bills it as
damage; water cooler `speed` and coffee counter `reload` buffs: Player statuses hasted and
caffeinated), 3 eyewash and emergency shower, 4 defib (no downed state exists: it revives a dead
teammate within 3 m during the respawn wait, else heals), 5 fire extinguisher (Cloud `foam`, new
Enemy status `slowed`, `flask_foam` pickup and flask; the extinguisher cabinet now drops one, its
body and the new extinguisher are the new non-glowing `RED_PAINT`, material 60), 6 gas cylinders
(skid, then explode), 7 hanging crate and pallet (crush damage from any loose fragment over 50
voxels), 8 flip (five `_flipped` twins), 9 printer and copier pages (`paper_<id>` pickups that open
the reader), 10 radio and jukebox (positional loop, 20 m lure in `EnemyManager.set_lure` /
`lure_for`, which `Enemy._think` prefers over a player it can't see), 11 rubber duck squeak (10 m,
4 s lure), 13 sprinklers (`switch_sprinkler` art; the action douses, clears clouds and flickers the
room's lights for 8 s, with falling-cube rain). Forced doors (a door losing 10% of its voxels) are
on the payroll at $500 each. Not landed: 12 barricades (`BuildPieces` is only a table of piece
sizes now: nothing places pieces in play, so skipped as the plan says), 14 live wire, topple shelf,
carts and chutes (optional, not started). Room light cuts dim the light markers only; LAMP voxels
follow the facility power as before.

## 5. Spaces and room kinds missing

- **Bathrooms and locker rooms**: stalls, sinks, urinals, showers, benches. Secret 2b already
  needs a bathroom.
- **Server hall and compute floor**: server racks with blinking lights, cable cages, cooling units,
  a raised floor with lifted tiles. There is no `server_rack` prop at all and floor -2 is the
  compute floor.
- **Cooling plant**: big tanks, pump housings, pipe galleries, walkways over water.
- **Cafeteria and kitchen**: serving counters, trays, rows of tables, stoves, steel prep tables.
- **Mailroom and storage**: pigeonholes, parcel shelves, a pallet jack and forklift.
- **Security checkpoint and gatehouse**: turnstiles, a metal detector, a guard desk with monitors,
  a barrier arm, a hut. The surface has no set dressing.
- **Decontamination**: a shower tunnel, hazmat suit racks and lockers, signs, a disinfectant
  sprayer.
- **Animal and specimen holding**: cages, tanks, a dissection table with a drain, a cold-store
  rack, body bags, a morgue drawer wall.
- **Incinerator and waste**: bins, a furnace, a dumpster, a biohazard collector.
- **Mine and cavern**: timber supports, a mine cart on rails, a lantern, stalactites and
  stalagmites, a drill rig, rope.
- **Executive floor**: a plush office, a boardroom table, a trophy shelf, a safe.
- **Open-plan office**: cubicle partitions as props, filing cabinets, name plates, a printer
  station, coat racks, a standing desk.
- **Maintenance and utility**: electrical cabinets, breaker panels, a boiler, a water heater, a
  pump.
- **Corridors**: handrails, wet-floor signs, caution tape, arrows, floor decals, room number
  plates, extinguisher cabinets, evac maps, exit signs. Corridors are the most-walked space and
  have the fewest props.

Status (D3): 41 props: counter_serving, tray_stack, cafeteria_table_long, stove, prep_table_steel, dish_rack, dishwasher, bin_row, toilet_stall, toilet, urinal, sink_mirror, shower_cubicle, hand_dryer, paper_towel_dispenser, changing_bench, suit_locker, cubicle_partition_straight, cubicle_partition_corner, filing_cabinet_2, filing_cabinet_4, printer_station, copier, coat_rack, standing_desk, monitor_single, monitor_arm, keyboard_mouse, mug, photo_frame, lunch_box, jacket_chair, cot, boardroom_table, executive_chair, trophy_shelf, safe, plush_couch, drinks_cabinet, globe, potted_tree.
Status (D2): 42 props: server_rack_closed, server_rack_open, server_rack_dead, cable_cage, crac_unit, floor_tile, floor_tile_lifted, patch_panel, ups_cabinet, tape_library; pump_housing, water_tank_round, water_tank_square, pipe_gallery_segment, valve_stand, cooling_tower_stack, catwalk_segment, boiler, water_heater, electrical_cabinet, breaker_panel, junction_box, fuse_box, transformer, compressor; timber_support_frame, mine_cart, rail_straight, rail_curve, lantern, stalactite_{small,medium,large}, stalagmite_{small,medium,large}, rock_pile, drill_rig, ore_bucket, rope_coil, rope_hanging.


## 6. Character and story dressing

- **Fung AI branding**: posters ("Because you are replaceable"), an org chart, a mission statement,
  an employee of the month board, a mascot standee, badge readers, lanyards on desks. Posters get
  darker with depth.
- **Personal items**: mugs, photos, jackets, bags, half-eaten lunches, sleeping bags in labs
  (people lived here), cots in the break room.
- **Outbreak traces**: overturned furniture, barricaded doors, scratched notes, mycelium smears,
  skeletons in suits overgrown with growth.
- **The clones**: a vat holding a previous you, a wall of past-operator photos, a payroll ticker
  display. Echoes the debt ending.
- **More lore forms**: audio logs and posters with more than one line.

Status (D4): 52 props: turnstile, metal_detector_gate, guard_desk, barrier_arm, gatehouse_panel, badge_reader, lanyard_desk, camera_dome; decon_tunnel, hazmat_suit_rack, hazmat_locker, hazmat_sign, sprayer, boot_wash; animal_cage_small, animal_cage_stack, specimen_tank_tall, dissection_table, cold_store_rack, body_bag_table, body_bag_floor, morgue_drawers, biohazard_bin, incinerator, dumpster, trash_chute; poster_fung_{a..f}, org_chart, mission_statement, employee_board, mascot_standee, payroll_ticker, operator_photo_wall, clone_vat_occupied, overturned_desk, overturned_table, barricade_door, scratched_note, skeleton_suit, skeleton_overgrown, {desk,chair,locker,terminal,shelf_storage_a,table,couch}_overgrown, cocoon.

## 7. Lighting and mood props

- Exit signs, red rotating beacons, floor path lights, glow arrows.
- Flickering fluorescent tubes with a buzz, dead tubes, lamps that sway when something heavy
  passes.
- Bench lamps, UV lamps (reveal hidden writing or mycelium), blacklight posters.
- Decorative bioluminescent plants, subject to the glow-decoy rule.

Status (D1): 26 props: exit_sign, exit_sign_arrow, beacon_rotating, path_light, glow_arrow, tube_light, tube_light_dead, pendant_swaying, bench_lamp, uv_lamp, blacklight_poster, plant_pot_glow, handrail_straight, handrail_corner, wet_floor_sign, caution_tape_post, caution_tape_run, floor_decal_arrows, room_plate_101, room_plate_204, room_plate_b12, extinguisher_cabinet, evac_map, bollard, mop_bucket, cleaning_cart

## 8. Suggested order

1. **Ceiling mount, duct and pipe pieces, light fixtures.** Cheapest, changes every room, and
   delivers the camouflage rule for the ceiling clouds.
2. **Pane shatter.** A small engine change (flood-fill, batch clear, debris) with a big feel.
3. **Mycelium growth pass and three materials**, then per-room infestation, tendrils and root
   obstacles, then wither.
4. **Server rack, cooling pipe, cafeteria and bathroom prop sets**, so the middle floors stop
   looking like floor 0.
5. **Reactive props**: extinguisher, gas cylinder, hanging crate, topple shelf, breaker panel.
6. **Barricades and the hijackable turret** as co-op set pieces.

The engine pieces (ceiling mount, pane shatter, growth pass) touch `prop_catalog.gd`, the voxel
extension and the editor, and do not collide with the prop art, so they can run as separate jobs.

**Status (F), 2026-11-03.** The laboratory is dressed (plan section F, all in
`scripts/tools/lab_layout.gd`; details and counts in `docs/lab-design.md`, "Dressing pass 2"):
1,170 props (370 before; 182 are package A's fixtures), 166 mycelium nodes. Ceilings: duct runs in
route rooms, pipe bundles in the cooling plant, grow rooms and pump room, cable trays in the server
hall, ops and electrical, tile grids in admin. Camouflage: `duct_insulated` lagging and a
`service_hatch` over the three built-room ceiling spawners (cooling plant, dissection, generator
hall) and mine ventilation lagging over the cavern's; six decoy runs elsewhere. The packs' room sets,
corridor signs, posters by floor (`a` at the top to `f` in the dig), payroll ticker, operator wall,
cocoons, skeletons, overturned furniture, barricade panels and a third of containment's furniture
overgrown. Mycelium by floor (none, light, veins, tendrils plus a root wall across the gallery's
optional north end, dense in the dig), `wither` on `t_m4_mother_dead` and `pulse=0.8` on the cavern
approach (`t_m4_approach`). Interactables placed: the lobby alarm pull (opens the new fire door
`d_0_fire`), breaker panel, priced vending machines, an extinguisher cabinet per floor, gas
cylinders, hanging crates and a pallet, the bullpen radio, the ops printer, the gatehouse duck. Not
placed: decon tunnel modules (the decon room's walk lines are all doorway clearance), a hatch over
the cavern's ceiling spawner (a cave roof), cocoons on walls (the model's back layer is a voxel off
the wall, so they stand on floors or hang from ceilings), barricades across real doorways (the
builder keeps props a meter off every doorway; the panels lean on walls instead).
