# Level editor: v1 spec

## Status (2026-11-02)

All eight build steps are implemented (`scripts/level/`, `scripts/editor/`; controls in the README),
plus pattern materials. Tested headless (`editor_tool_test`, `tools/net_test.sh editor_test`) and in
screenshots; not yet play-tested by hand. Where it differs from the plan below:

- Room-tool linings are each person's tool settings (starting from the level's defaults), not
  level settings.
- In rock levels the room tool's lining only recolors solid voxels, so a new room opens into any
  room it touches; in empty levels it builds the walls.
- New levels start with a 10 x 10 m room (rock) or floor slab (empty), a spawn and a light, so
  there's something to see and aim at.
- Undo of a voxel edit restores the whole box it changed, which also reverts anyone else's later
  edits inside that box.
- Doors aren't counted as assets (they move).
- Added: pattern materials (`assets/patterns/`, see the README).

## Spec

Agreed 2026-11-02. An in-game, co-op level editor. The host and friends build levels together, the
host saves them to files, and the game loads those files instead of the generated facility.
Levels planned: the lab (main), the cubicle intro, the garbage-bag ending.

## Sessions

- The menu gets **Edit level** (host: pick or create a level) next to Play. Others join an edit
  session the same way they join a game.
- Everyone can edit at once. Every change goes through `WorldSync` (host applies, replays to peers
  in order), like weapon damage does now.
- Only the host saves. Running from the Godot editor, levels save to `res://levels/` (committed to
  git); from an exported build, to `user://levels/`.
- The editor ships in exported builds, so a friend with just the exe can join an edit session.

## Camera and controls

- Fly camera: noclip, no gravity, scroll to change speed, sprint for fast. Same view as playing.
- Crosshair cursor on the targeted voxel face, drawn as a highlighted box.
- Grid snap for tool corners: 1 / 5 / 10 voxels (10 = 1 m), cycled with a key.
- A tool bar and a small panel (material, sizes, selected object's properties). Mouse released
  (Esc) to click UI; captured to fly and aim.

## Voxel tools

| Tool | Use |
|---|---|
| Box | Click two corners (then adjust height); fill with the material, or carve. The workhorse. |
| Room | Box that carves the inside and lines floor / walls / ceiling with chosen materials (wall thickness setting). Most of the lab is built with this. |
| Brush | Sphere or cube, size 1-20, paint or carve. Detail and damage. |
| Replace | Swap material A for B inside a box. |
| Eyedropper | Pick the material under the cursor. |

- Material picker: every material from `PALETTE.md`, with swatches and names.
- Undo / redo per person: each edit records the voxels it changed (before / after). Undo replays
  the before-state through `WorldSync`, so it is shared like any edit.

## Props

- Browser of `assets/vox/props/` with thumbnails (rendered once, cached).
- Ghost preview at the cursor, snapping to the floor under it; rotate in 90 degree steps; click to
  place.
- Select (click a prop), move, rotate, duplicate, delete. Selection outlines the prop's box.
- Props stay **instances** in the level file (name, origin, facing, properties) and are stamped
  into voxels at load, so they're destructible in play and still editable and live-reloadable in the
  editor.

## Markers

Placeable gameplay objects, each with a unique **id** and a few properties edited in the panel.
Story and gameplay code finds them by id or type; no visual scripting.

| Marker | Properties |
|---|---|
| Player spawn | index (player 1-4), facing |
| Trigger | box size, once / repeat, who (any player / all players) |
| Intercom speaker | (position only; announcements play from the nearest / all) |
| Light | omni or spot, color, energy, range, spot angle, shadows on/off, flicker (none / subtle / broken), on facility power or emergency |
| Horde spawner | (position, facing) |
| Clone vat | (position, facing): respawn point |
| Kill zone | box size: where the company kills escapees |
| Item spot | item type |

Markers are visible only in the editor (simple icons / wire boxes), invisible in play.

## Doors

- A door is a **prop with door properties**: open offset (slide direction and distance, in
  voxels), speed, locked, id.
- At rest a door is voxels, so collision, bullets, enemies and damage all work unchanged. While
  moving, its voxels are erased and a mesh of the door model slides; when it stops, it's stamped
  again at the new spot. The host runs doors; peers get the erase / stamp edits plus a "door
  moving" message for the mesh.
- Opened by: interact key (if unlocked), triggers, or story scripts (`level.door("lab_main").open()`).
- Placeholder door models get added to the prop catalog (sliding lab door, security door).

## Asset values (payroll)

- Any prop can be marked a **company asset** with a dollar value (the panel; defaults per prop
  name, e.g. a fume hood is worth more than a chair).
- In play, each asset's damage = the fraction of its voxels no longer intact. Damage fires a signal
  with the asset id and the dollars lost, for the payroll system to deduct.
- Counting is done only for assets whose box an edit touched.

## Level settings

- Size (in chunks), starting fill: **solid rock layers** (carve rooms out, for the lab) or **empty
  air** (build up, for small scenes); chosen in the new-level dialog.
- Environment: fog, ambient color and energy, background.
- Room-tool default materials.

## Files

`res://levels/<name>/`:

- `voxels.bin`: `VoxelWorld.get_data()`, zstd-compressed. The base terrain and everything built,
  **without** props (they're stamped at load).
- `level.json`: settings, prop instances, markers, doors. Plain JSON, pretty-printed and sorted so
  git diffs and merges stay readable.

Joining peers receive both, in small pieces (big reliable RPCs get dropped; see `WorldSync`).

## Play-testing

- One key toggles edit / play for everyone in the session (host decides).
- Play starts from a copy: entering play keeps the edit state in memory; leaving play restores it
  exactly, so damage during the test never reaches the saved level.

## What it replaces

- The old build mode (`scripts/building/`) and `FacilityBuilder`. The current generated facility is
  converted once into `res://levels/lab/` as the starting point.
- `Lab` loads a level file instead of generating; the old mushroom scene (`facility.tscn`) is retired.

## Later (not v1)

- `.vox` export / import of level geometry.
- Copy / paste of regions, prefabs (saved groups of voxels, props and markers).
- Enemy navigation hints, elevators, other moving parts.

## Build order

1. Level file format: save / load, `Lab` loads a level, converted facility as `levels/lab`, sent to
   joining peers.
2. Edit mode: fly camera, cursor, grid snap, edit / play toggle with revert.
3. Voxel tools: box, room, brush, replace, eyedropper, material picker; undo / redo.
4. Props: browser, ghost, place / select / move / rotate / delete.
5. Markers and lights, with the property panel.
6. Doors.
7. Asset values and damage events.
8. Remove the old build mode and facility generator.
