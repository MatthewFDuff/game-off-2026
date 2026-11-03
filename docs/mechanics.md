# Mechanics: list and implementation plan

Compiled 2026-11-02 from `docs/SHIFT.pdf` (the brainstorm doc). Story beats are left out on
purpose; only the mechanics are here. Where the doc was ambiguous or had two versions of an idea,
the choice made is marked **decision** and listed again under "Open decisions" at the end.

The reference screenshots in the doc (GTFO caves / labs / tentacle zone, Portal 2 elevator) are
tone and art references, not mechanics.

## 1. The list

### Controls (from the doc, with what they map to)

| Input | Doc says | Plan |
|---|---|---|
| WASD | movement | exists |
| Mouse, arrow keys | aim | exists |
| Left click | shoot | shroom shooter, current ammo |
| Middle click | melee | new |
| Right click | secondary (grenade / flask) | throw the selected flask |
| **Shift** | change ammo type (the theme key) | new; see decision 1 |
| E | interact | exists for doors; generalize |
| Space | jump | exists |
| Esc | pause (not in multiplayer) | solo: pause the tree; co-op: release the mouse as now |
| F1 | show controls | new overlay |
| (not in doc) Ctrl / C crouch, T flashlight | | exists, keep |

### Enemies

1. **Basic shroom**: small, slow, easy to kill, comes in numbers. Can sneak up on you.
2. **Fast shroom**: rusher.
3. **Exploding shroom**: runs in and blows up (hurts players and terrain).
4. **Giant**: tank, with a crit spot ("dangly little alien antennae").
5. **Ranged shooter**: spits at range.
6. **Tentacle fungi**: stationary, grabs / hits anything that walks past.
7. **Poison cloud**: hangs on the ceiling, drops a cloud when disturbed or when players pass under.
8. **Alarm shroom**: screams and calls a horde when it sees you.
9. **Mommy shroom**: spawns lots and lots of shrooms until killed.
10. **Spore shroom**: fills the area with fog / spores (vision denial).

### Weapons

- **Shroom shooter**: the experimental mushroom gun, one gun with swappable ammo. Shift changes
  the ammo type. This is the main weapon.
- **Melee** on middle click. The doc lists axe, knife, katana, fist / foot / toes (a Dungeon
  Crawler Carl joke). **Decision**: one melee attack with a swappable look; the first is the axe.
- **Flamethrower** appears as both a weapon and an ammo type. **Decision**: it is an ammo type.
- **Syringe**: listed under weapons in the doc; dropped (decided 2026-11-02).

### Shroom shooter ammo types

| Ammo | Behavior |
|---|---|
| Basic | hitscan, infinite (so nobody is ever stuck) |
| Shotgun | hitscan cone, several pellets, short range |
| Flamethrower | short cone, continuous, applies Burning, costs fuel per second |
| Explosive | projectile, blast on impact (reuses the current blast carve), hurts terrain and assets |
| Ricochet | projectile, bounces off voxels up to N times, pierces shrooms |
| Homing | projectile, steers toward the nearest shroom in a cone |
| Poison | projectile, leaves a poison cloud that applies Poisoned |

Ammo is found in the lab (pickups, cabinets, drawers) in limited quantity, except basic.

### Grenades / flasks (right click)

Experimental flasks found in the labs, limited quantity. Thrown in an arc, shatter on impact and
leave an area effect for a few seconds:

- **Fire**: burning pool, Burning to anything in it.
- **Poison**: cloud, Poisoned to anything in it.
- **Rage**: **decision**: shrooms in the cloud turn on each other (and are faster). Alternative:
  a player buff.
- **Freeze**: Frozen (stopped) for a few seconds, then slowed.

### Status effects

The doc calls these scope creep, to be added if the game needs more balance / challenge. But the
ammo and flasks above already need **Burning, Poisoned, Frozen, Raging on enemies**, so a minimal
status system on enemies is in scope from the start. Status effects on players (poison cloud,
spore fog) come later.

### Interactables

- **Doors** (exist, including locked). Add: **keys / keycards** that unlock a specific door.
- **Desk drawers**, **cabinets**: containers, open with E, hold ammo / flasks / keycards.
- **Computers / terminals**: read text on screen, and can fire triggers (unlock a door, cut
  power, start the generator sequence).
- **Paperwork**: readable notes (lore pickups).
- **Break room**: sink, fridge, water cooler. Fridge and cooler are containers (snack = small
  heal, water = clears Poisoned); the sink is flavor.
- **Pickups**: health, ammo, flasks, keycards. Lying in the world (item spots) or in containers.
- **Interactable stations**: medkit station (heal, limited charges), ammo bench.
- **Vents**: shootable grates; shrooms come through them, players can crawl through them.
- **Generator / machinery**: the generator restores facility power, which starts the big horde
  and a survival timer. Other machinery: switches and valves tied to triggers.
- **Emergency glass** (from the walkthrough): a wall case you break to get the first weapon.

### Power states (from the walkthrough)

Facility power, backup power (emergency lights and the intercom only), restored power. Lights
already have a facility / emergency flag; doors, terminals and the generator react to the state.

### Encounter flow mechanics (the parts of the walkthrough that are systems, not story)

- Training area where combat is taught safely.
- Ambient shrooms trickle in while you explore; alarm shrooms and triggers call hordes.
- Generator event: turning it on triggers a horde and a timer you must survive.

## 2. What already exists (build on it, don't redo it)

- `Player` (`scripts/player/player.gd`): movement, crouch, ladders, health with regen, damage
  with knockback, shake and recoil, death and revive, co-op state streaming.
- `Rifle` (`scripts/player/rifle.gd`): hitscan placeholder with tracers, muzzle flash and remote
  shot replication. Alt fire is a terrain blast. Both only hit voxels; nothing hits entities yet.
- `LevelPlay` (`scripts/level/level_play.gd`): doors (voxel doors, locked flag, host-run),
  triggers (box, once / repeat, any / all players), kill zones, asset damage to the payroll.
- `LevelSchema`: marker types already include `horde` (position only), `item` (an item name
  string), `clone_vat`, `speaker`, `light` with `power = facility | emergency`.
- `Lab`: spawns, respawn at the clone vat, interact key wired to doors, host / peer plumbing.
- `WorldSync`: every voxel change goes through the host and replays on peers.
- `VoxelWorld` (C++): `move_box` box collision, `raycast`, `carve_sphere`, and a **flow-field
  navigation** (`update_flow_field(target, max_distance)`, `get_flow(feet)`) with ledges, drops,
  headroom and "breach" spans that enemies can dig through. It takes one target.
- `ShroomModels` and `assets/vox/shrooms/stage4_<v>_eyes.vox`: grown shroom bodies with eyes,
  live-reloadable.
- `Sfx`: synthesized sounds, including `shroom_hit`, `shroom_pop`, `shroom_chitter`, `bite`,
  `hurt`, `alarm`, `power_down`, `power_up`, `blast`, `rifle`, `chip`.
- Old enemy code (`scripts/game/shroom.gd`, `shroom_manager.gd`) from before the pivot is in git
  at `0112949^` and shows how the flow field was driven; reuse the movement bits.

## 3. Rules that apply to every step

- **Network-aware from the start.** The host owns enemies, spawners, pickups, containers, power
  state and the horde director. Peers get spawn / state / death messages. Shots are
  **shooter-authoritative**: the shooting peer detects the hit and sends `(enemy id, damage,
  point)` to the host, like `WorldSync._request_carve`; the host applies it and broadcasts the
  result. Co-op is friends only, so trusting the shooter is fine and keeps shooting responsive.
- **Terrain damage stays on `WorldSync`.** Explosions, exploding shrooms and breaching enemies
  carve through it, never `VoxelWorld` directly.
- **Every enemy, weapon and pickup is a `.vox` model** under `assets/vox/` with a generated
  placeholder, so the user and Zack can replace it in MagicaVoxel. New folders: `enemies/`,
  `weapons/`, `items/`.
- **Every new placeable thing is a marker or prop property in `LevelSchema`,** so it is placed
  in the level editor, not in code.
- **Tests**: a headless test per phase (like `editor_tool_test.gd`), and `tools/net_test.sh`
  extended so the host and a client end with the same enemy roster and world.

## 4. Implementation plan

Phases are in dependency order. Each is playable on its own.

### Phase 0: Controls (half a day)

1. `InputSetup`: add `melee` (MMB), `cycle_ammo` (Shift), `show_controls` (F1), `pause` (Esc),
   `ammo_1..4` (number keys, as a backup to Shift). **Decision 1**: Shift becomes "shift ammo"
   and sprint is removed; walk speed goes up to about 5.5 m/s. L4D2-style games have no sprint,
   and Shift as the theme key should do the themed thing.
2. F1: a `ControlsOverlay` on `LabHud` listing the bindings (generated from `InputSetup`, so it
   never goes stale).
3. Esc: in solo play, pause the tree and show the pause panel; in co-op keep the current
   behavior (release the mouse, game keeps running).

### Phase 1: Enemies and hordes, with the basic shroom (2 days)

The foundation every other enemy and weapon needs.

1. **`Enemy`** (`scripts/enemies/enemy.gd`, `scenes/enemy.tscn`): `Node3D` with a voxel body
   mesh from `.vox` (via `world.build_model_mesh`, like remote players), an AABB, `max_health`,
   `speed`, `damage`, `attack_range`, `attack_cooldown`. Moves with `world.move_box` and
   gravity. Host-simulated; peers interpolate position and yaw from unreliable state packets at
   10 Hz (reuse `Player._remote_states`). Death: `shroom_pop` sound, body bursts into
   `VoxelDebris`, node freed everywhere.
2. **Hit detection for entities**: `Combat.ray_hit(from, dir, range)` returns the nearest of the
   voxel hit (`world.raycast`) and any enemy AABB hit (`AABB.intersects_ray`), with the enemy's
   named hit zones checked first (for crit spots). `Combat.sphere_hit(center, radius)` for
   blasts and clouds. Enemies register in a group so this is a simple loop.
3. **Damage path**: `Rifle` calls `Combat.ray_hit`, and on an enemy hit sends
   `EnemyManager.request_hit(id, damage, point, kind)` to the host; the host applies damage,
   emits `enemy_damaged` / `enemy_died`, and broadcasts a hit-flash to peers. Knockback and the
   crit multiplier live here.
4. **Navigation**: extend `VoxelWorld.update_flow_field` to take an `Array[Vector3]` of
   targets (multi-source Dijkstra, a small C++ change in `voxel_world_nav.cpp`), so each enemy
   walks toward the nearest player without one field per player. `EnemyManager` refreshes it at
   about 5 Hz with all living players. Enemies step toward `get_flow(feet).next`; a `breach`
   result makes them dig (`world_sync.carve_sphere` on the blocking voxels, slow) so planks
   and vents are not safe forever.
5. **Attacks**: when within `attack_range` of a player, swing with a cooldown; damage goes to
   the player's owner (`Player.take_damage` via RPC, as `Lab._kill` does).
6. **Basic shroom**: stage-4 shroom body with eyes, slow (2.5 m/s), low health, bite attack.
   Chitters only when close ("can sneak up on you"): no sound at range.
7. **Spawners and the horde director**: the `horde` marker gets fields `kinds` (which enemies),
   `rate`, `max_alive`, `active` (starts on / off), `radius`. `HordeDirector` (host) runs a
   state: *calm* (ambient trickle from active spawners), *horde* (a burst of N from spawners
   near the players, started by alarm shrooms, triggers or story code), *finale* (the generator
   timer, phase 6). `LevelPlay.triggered` can target a spawner id with a new trigger field
   `activates` (spawner id or `horde`).
8. **HUD**: health bar, a hit marker, damage flash. Enemies get a brief white flash on hit.
9. **Tests**: `tests/enemy_test.gd` (headless: spawn, path to a player through a door frame,
   attack, die, debris); `net_test.sh` checks both peers see the same enemies.

### Phase 2: The shroom shooter and ammo (2 days)

1. **`Weapon`** replaces `Rifle`: a view model from `assets/vox/weapons/shroom_shooter.vox`,
   `AmmoType` resources (`scripts/weapons/ammo/*.gd`) describing fire mode, damage, spread,
   rate, projectile scene, sounds and the HUD icon color. `Shift` / number keys change the
   active type; the gun's glow voxels recolor to the ammo color so co-op partners can see it.
2. **Ammo inventory** on the player: counts per type, basic is infinite. HUD shows the current
   type, count, and the next type.
3. **Hitscan types**: basic, shotgun (pellets with spread), flamethrower (a short cone checked
   each tick, applies Burning, drains fuel). Flame gets a particle cone and a looping sound.
4. **Projectiles** (`scripts/weapons/projectile.gd`): moved with `world.raycast` per step so
   they never tunnel through voxels, simulated by the shooter and replicated visually to peers
   (spawn + hit messages). Explosive: blast radius carve plus `Combat.sphere_hit`. Ricochet:
   reflect off the hit normal up to 4 bounces, passes through enemies. Homing: steers toward
   the nearest enemy within a 30 degree cone. Poison: leaves a `Cloud` (phase 3).
5. **Pickups** (`scripts/items/pickup.gd`): a small bobbing voxel model, picked up by walking
   over it (health, ammo of a type, flask of a type, keycard). The `item` marker's string names
   the pickup (`ammo_explosive`, `flask_fire`, `medkit`, `keycard_red`). Host owns pickups and
   tells peers when one is taken. Enemies have a chance to drop ammo.
6. **Sounds**: one per ammo type in `Sfx` (reuse `rifle` for basic, `blast` for explosive).
7. **Tests**: `tests/weapon_test.gd` for each ammo type hitting a target enemy in a box room.

### Phase 3: Melee, flasks and status effects (1.5 days)

1. **Melee** (MMB): short-range box hit in front of the camera, high damage, a knockback,
   `Combat.box_hit`. One `melee` animation on the view model (a swing tween); the model comes
   from `assets/vox/weapons/axe.vox` so knife / katana are drop-in swaps later.
2. **`StatusEffects`** component on `Enemy`: a dictionary of effect -> time left, ticked by
   the host. Burning: damage per second, spreads to touching shrooms, tints the body orange.
   Poisoned: slow damage, green tint. Frozen: speed 0 then 50 %, blue tint. Raging: targets the
   nearest shroom instead of players, 1.5x speed, red tint. Peers get the tint through the
   state packet.
3. **Flasks** (RMB): the selected flask type (cycle with Q, see decision 3) is thrown as a
   `Projectile` with an arc; on impact it spawns a `Cloud` (fire pool / poison cloud / rage
   cloud / freeze burst) that applies its status to anything inside for its lifetime. Fire
   pools also ignite shroom voxels (`SHROOM_*` materials) in the terrain. Clouds are host-owned
   areas, drawn with a particle volume on every peer.
4. **Inventory HUD** for flasks (count per type) next to the ammo readout.
5. Player-side statuses (Poisoned from clouds, blinded by spores) come with those enemies in
   phase 4, using the same component on `Player`.

### Phase 4: The enemy roster (3 days, one or two enemies at a time)

Each is an `Enemy` subclass with its own `.vox` placeholder and a generator in a new
`EnemyModels` (like `ShroomModels`), listed in `LevelSchema` so spawners and item spots can
name it. In the order they pay off most:

1. **Fast shroom**: 2x speed, half health, zigzags when within 6 m.
2. **Exploding shroom**: runs at you, flashes, then `carve_sphere` + `sphere_hit`. Killed early,
   it still blows (smaller). Hurts assets, so it costs payroll.
3. **Alarm shroom**: stands still, screams when it has line of sight to a player
   (`world.raycast`), which tells the `HordeDirector` to start a horde at the nearest spawners.
   The `alarm` sound exists.
4. **Giant**: 10x health, slow, big swing with knockback that carves a little terrain. A `crit`
   hit zone on the antennae (a named sub-box of the model) takes 5x damage; shooting the
   antennae off removes the zone and makes it stagger.
5. **Ranged shooter**: keeps 8 to 12 m away, spits a slow projectile (the same `Projectile`
   class) that applies Poisoned.
6. **Mommy shroom**: stationary, spawns basic shrooms every few seconds up to a cap; killing it
   pops the brood. Placed with a spawner marker set to `kinds = ["mommy"]`.
7. **Spore shroom**: on death or when approached it emits spores: a `Cloud` that raises local
   fog density (`WorldEnvironment` fog on each peer scaled by distance) and applies Blinded to
   players.
8. **Poison cloud (ceiling)**: placed on ceilings (spawner `on_ceiling` flag, or an item spot);
   drops a poison `Cloud` when a player passes under or when shot. Shooting it first from far
   away is the counterplay.
9. **Tentacle fungi**: stationary, a reach radius; grabs the nearest player (pulls and holds,
   `Player` gets a `held` state) until it takes enough damage or a partner melees it. Good
   co-op moment.

### Phase 5: Interactables (2 days)

1. **`Interactable` interface**: `prompt()` text and `use(player)`; `Lab._on_local_interact`
   becomes a generic "what am I looking at within 3 m" check over doors and interactables, and
   the HUD shows the prompt ("[E] Open", "[E] Read", "Locked: needs red keycard").
2. **Containers** (drawers, cabinets, fridge, water cooler, lockers): a prop property
   `container` with `contents` (a list of pickup names) and `opened`; E opens it once and spawns
   the pickups in front of it. Set in the level editor inspector. Host owns the state.
3. **Keycards**: a pickup; doors get `door_key` (a keycard name). `is_door_locked` becomes
   "locked and the player has no matching key". Keys are shared across the party (any player
   holding it opens the door for everyone, L4D2 style).
4. **Terminals**: a prop property `screen_text` and `on_use` (a trigger id to fire). Reading
   shows the text on the HUD; using fires the trigger, which story code and spawners already
   listen to. Paperwork is the same with no trigger.
5. **Stations**: medkit station (`station = "medkit"`, charges) heals to full; ammo bench
   refills one ammo type. Both are props with a property and a cooldown.
6. **Emergency glass**: a prop made of `GLASS` voxels with `contents`; breaking any of its
   voxels spawns the contents (the first weapon in training). No E needed.
7. **Vents**: a prop (grate) of a soft material with a crawl-height duct behind it; enemies
   breach it through the nav "breach" cost already in the flow field, players shoot it out and
   crouch through.
8. **Power states**: `LevelPlay.power` = `facility | backup | restored`, host-set and
   broadcast. Lights already read `power`; terminals, powered doors (`door_power` flag) and the
   `power_down` / `power_up` sounds follow it. Story code sets it; the generator sets it to
   restored.
9. **Generator**: a prop with `station = "generator"`; using it with power on `backup` starts
   phase 6.

### Phase 6: The generator finale (1 day)

1. `HordeDirector.finale(duration)`: power goes to `restored`, every spawner activates, spawn
   rate ramps over the timer, alarm stings play, the HUD shows the countdown.
2. Surviving the timer fires a `finale_survived` trigger for story code; wiping (all players
   dead at once, since the clone vat respawns singles) fires `finale_failed` and resets to the
   last clone vat state.
3. Balance pass with the spawner fields; everything is editor data, so tuning needs no code.

### Phase 7 (later, only if needed)

Player status effects, more melee weapons, and enemy voxel-level body damage (chip voxels off
the model mesh instead of a health number).

## 5. Open decisions

1. **Shift**: ammo cycle, sprint removed (recommended). Alternative: keep sprint on hold, cycle
   ammo on a short tap, with the number keys as the reliable way to pick ammo. Note that
   `docs/level-editor-v2.md` section 6 (the new character controller) still assumes sprint
   (speed cap at 1.6x sprint speed, FOV kick while sprinting); whichever way this goes, that
   plan should match. Without sprint, the cap becomes 1.6x walk speed and the FOV kick goes
   on bunny-hop speed instead.
2. **Flamethrower** is an ammo type, not a separate weapon.
3. **Flask selection**: Q cycles flasks (recommended), RMB throws. Alternative: a radial menu.
4. **Rage flask** makes shrooms fight each other (recommended) rather than buffing players.
5. **Syringe**: dropped.
6. **Melee weapon**: one attack, axe model first; knife and katana are model and stat swaps.
7. **Keycards are party-wide** (any holder opens the door for everyone).
8. **Basic ammo is infinite.**
9. **Enemy damage model**: health numbers with hit zones, not per-voxel body damage, for v1.

## 6. Estimated order and size

| Phase | Days | Depends on |
|---|---|---|
| 0 Controls | 0.5 | - |
| 1 Enemies, hordes, basic shroom | 2 | - |
| 2 Shroom shooter and ammo | 2 | 1 |
| 3 Melee, flasks, statuses | 1.5 | 2 |
| 4 Enemy roster | 3 | 3 |
| 5 Interactables, power, generator | 2 | 1 (can run alongside 2 to 4) |
| 6 Finale | 1 | 4, 5 |

About 12 days of work in total; phases 5 and 2 to 4 can be interleaved. Phases 0, 1 and 2 give a
playable co-op shooter; 5 and 6 give the lab its structure.
