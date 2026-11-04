# Level editor: build mode (floors, walls, ceilings)

Plan for building in **empty levels** the way the Sims does it: draw the floor, then the walls, then
the ceilings, on stacked storeys, with everything snapping to what's already there. Follows
[level-editor-v2.md](level-editor-v2.md); rock levels keep the Room tool for carving.

## Status

**All six steps are in** (Nov 3 2026). Nothing has been play-tested by hand yet. Below: what each
step did, where it differs from the plan, and what's left.

**Step 1 (the model) is in** (`scripts/level/level_build.gd`, `VoxelWorld.apply_structure`'s build
shapes, `LevelEdits.add_slab_shape`, `tests/build_model_test.gd`). There are no tools yet: pieces
are made in code or tests.

**Step 2 (storeys) is in** (`EditorTool.storey`, `change_storey`, `set_storey_height`,
`storey_plane_hit`; `EditorCamera.storey_cut`; the HUD's storey bar; `tests/build_storey_test.gd`):
- In empty levels, PgUp / PgDn and the bar's ▲ / ▼ change storeys. Going past the top adds one;
  coming down from an empty top storey drops it.
- The cutaway opens the active storey unless it's Off. It cuts at the top of the walls (the ceiling
  is cut away and the cap shows the walls); with the Ceiling tool it cuts over the ceiling.
- The bar's "Walls (m)" field sets the storey's wall height.
- The cursor lands on the active storey's floor plane wherever nothing nearer is hit. That covers
  storey 1 too: its plane is the top of the ground floor, so you can draw out in the air beside the
  starter slab.

**Step 3 (Floor and Ceiling tools) is in** (`scripts/editor/tools/build_tools.gd`,
`LevelBuild.enclosure` / `enclosures`, `tests/build_floor_test.gd`):
- An empty level's rail is Select, Floor, Ceiling, Box, Brush, Replace, Opening, Prop, Marker (no
  Room), numbered 1 to 9 in order.
- Floor and Ceiling aim at the storey's floor top or wall top (a plane, so they never jump onto
  walls).
- **Drawing:**
  - A drag paints a rectangle; Shift erases.
  - Corners snap to wall ends and shape corners, then to points along walls and shape edges, then
    to the grid. A label shows what was snapped to.
  - A click without a drag fills the room the storey's walls close in, out under the walls, and
    Shift+click erases it. An open loop says so and does nothing.
- **Auto** (the Ceiling inspector) covers every closed room that has a floor.
- Fills are stored as a new shape kind, runs: `[add, material, -R, z, x0, x1, ...]`, sorted by z.
  The C++ looks them up by binary search.

**Step 4 (Wall tool) is in** (`scripts/editor/tools/wall_tool.gd`, `tests/build_wall_test.gd`):
- The empty-level rail is now Select, Floor, Wall, Ceiling, Box, Brush, Replace, Opening, Prop,
  Marker (keys 1 to 9, then 0).
- **Drawing a wall:**
  - Press, drag, release on the storey's floor draws a wall from the press.
  - Its direction snaps to the nearest of 8, and its end to the grid along that line. A wall end,
    a point on a wall or a floor corner / edge on that line (within about 18°) wins.
  - The start snaps the same way, so a drag from a wall's end joins it.
- **While dragging:** the wheel sets the height (a wall at the storey's height stores -1 and follows
  it). Typing sets the length (`2.5`, `25v`); Tab switches to the height and Enter keeps it.
- **Ctrl+drag:** four walls around the rectangle, plus its floor and ceiling when "Floor and
  ceiling" is checked. It's one undo step (a LevelEdits group).
- **Shift+drag** along walls erases the span from every parallel wall on that line:
  - A wall keeps the part before the span; a new wall gets the part after.
  - An opening past the span moves onto the new wall with its `along` fixed, so it stays put in the
    world. Openings in the span go with it.
- **Inspector:**
  - the wall material, and the inner (left) face, set from the catalog's "Wall / Inner face" tabs
  - thickness
  - "Storey height", or a height of its own
  - "Floor and ceiling"
- The preview shows the wall's real cells as see-through prisms with edges, red when erasing, with
  length and height labels, the readout card, and the snap label. It's sent to the others as the
  presence preview.

**Step 5 (editing walls, openings and doors) is in** (`scripts/editor/tools/wall_handles.gd`,
LevelBuild's wall geometry (`corners_of`, `box_of`, `wall_at`, `opening_at`, `doors_in`),
`tests/build_edit_test.gd`):
- **Selecting:** the Select tool picks a wall by any of its voxels (one on the active storey wins),
  or an opening in a wall by its cut. The outline is the wall's own prism, square to it at 45° too
  (`LevelView.draw_corners`).
- **Handles** on each end and in the middle, on top of the wall. Drag, or click to pick up; the
  wheel nudges.
  - An end goes where the Wall tool would put it from the other end (8 directions, the same snaps).
  - The middle slides the wall sideways in grid steps.
  - Walls with an end at the moved point follow it, so corners stay closed. If one would end up at
    another angle, the move is refused ("Joined walls would bend").
  - It's one edit with the joined walls, the openings (kept in place in the world, clamped into
    the wall) and, when it slides, the doors in it. The wall is locked while it's held.
- **Inspector:**
  - wall and inner face materials (the catalog's Wall / Inner face tabs)
  - length (moves the far end)
  - storey height or its own
  - id, storey, thickness
  - Move, Duplicate (with its openings, not its doors), Split (at its middle, on the grid), Merge
    (with a joined wall in line, built the same), and Delete (with its openings and doors)
- **Opening tool on a wall:** an opening along it (`wall`, `along`, `width`, `sill`, `height`),
  centered on the cursor on the grid and clamped into the wall. Doorways start at the floor,
  windows at the sill, holes at the cursor. It works on 45° walls; the preview is the cut's prism.
- **Doors** go in straight walls only; a 45° wall says "doors go in straight walls".

**Deviation:** a door in a wall keeps the v2 door openings (a box doorway through the wall and the
slide pocket in its middle layer, from `PropPlacement._door`), not openings measured along the
wall. They still follow the wall, because sliding or moving a wall carries its door props and
`LevelEdits._door_openings` recuts their openings. Dragging an end doesn't move doors.

**Step 6 (polish) is in:**
- **Two people:** `tests/build_net_test.gd` (`tools/net_test.sh build_net_test`). A client builds
  with the editor's own tool objects:
  - a Ctrl rectangle with its floor and ceiling
  - a room closed by a 45° wall, with its floor filled and an Auto ceiling
  - a window and a door
  - a dragged wall end
  - a taller storey
  - an undo

  The host checks the objects, the voxels and the client's selected wall in presence. Both worlds
  hash the same.
- **Presence:** walls being drawn or reshaped, and the Opening tool's cut, go to the others as
  prisms (`prisms`: 8 corners each), drawn square to the wall. A selected wall or wall opening is
  outlined by its own prism.
- **Alt+click** on a wall's inner face picks the inner material (Wall tool).
- **Speed** (a Large empty level, 16 × 10 × 16 chunks, with 40 walls and a few fills):

  | Edit | Time |
  |---|---|
  | wall | about 4 ms |
  | one-room fill | about 80 ms (the flood fill is about 20 ms) |
  | Auto ceiling over 12 rooms | 150 ms |
  | storey height change (was 1.1 s) | 95 ms |
  | undoing that (was 2.9 s) | 12 ms |

  The fixes:
  - A storey change only rewrites from the first changed storey's ceiling up
    (`LevelBuild.changed_from`), which also brings it under the undo size limit.
  - The C++ structure pass keeps per-row and per-layer lists of the shapes that can touch them.
  - `WorldSync` applies a box in one go on the host. A client gets it in slices with immediate
    remeshing off, so a big undo no longer remeshes the same chunks for every thin slice.

Left over:
- A wall ending on another wall's middle doesn't split it, and only walls sharing an exact end
  follow a moved end.
- There's no hover preview of what a click-fill would cover.
- Moving a wall keeps it on its own storey.
- Doors in walls use the v2 box openings (above).

### Rock levels: build on what you aim at (Nov 3 2026)

Floor, Wall and Ceiling now work in rock levels too (fill "rock", e.g. `levels/laboratory`), for
splitting a carved room with walls and adding mezzanines. Rock levels have no storeys: everything
is built on the surface aimed at. Page Up / Down still move the cutaway there.
`tests/build_rock_test.gd` covers it.

- **Data model.** Empty levels are unchanged, and so is their saved data.
  - A wall in a rock level has `storey` -1, `base` (the voxel y of the floor top it stands on) and
    always its own `height`. `base` is a new field rather than `a.y`, because the wall code writes
    `Vector3i(x, 0, z)` in many places. `LevelBuild.wall_base` replaces `floor_y(storey)` everywhere
    a wall's bottom is needed.
  - Floors and ceilings are kept per plane, not per storey: `storey` -1 and `y` (a floor's top, a
    ceiling's bottom), with ids `floor_y<y>` / `ceiling_y<y>`. The slab is 3 voxels (the default
    storeys' `slab`) under a floor's plane or over a ceiling's. `LevelEdits.add_slab_shape` takes the
    plane as a fourth argument. With storey -1 the host checks the plane is in the world and makes
    no `storeys` object.
  - Walls "with" a wall (snapping, joined ends, merging, Shift erase, click-fills) are the ones on
    the same base: `LevelBuild.walls_on(objects, -1, base)` / `walls_with`.
- **C++ (`structure_at`).** Before, a room's inside beat everything built, so a built wall in a
  carved room would never show. Now, when the base is solid (rock levels only):
  - a built piece fills a room's inside, and recolors its lining like a lining would;
  - it never touches cells outside every room, so the rock stays as it is;
  - a wall opening only cuts inside a room, so it can't dig into the rock behind a wall.

  Empty levels (air base) keep the old order exactly. Both the debug and the release libraries were
  rebuilt. The web `.wasm` in `bin/` is stale until it's rebuilt.
- **Rail:** Select, Room, Box, Brush, Replace, Opening, Prop, Marker, Floor, Wall, Ceiling. The
  first eight keep their keys (1 to 8); Floor is 9, Wall 0 and Ceiling `-` (new: `editor_tool_slot_11`).
- **Aiming.** The floor under the cursor is the aimed voxel's top, or the floor under the air in front
  of a wall face. The cutaway's cross section and empty space give no aim.
- **Wall tool:**
  - The base is that floor's top where the drag starts, fixed for the drag.
  - The height reaches the first solid over the aim, not counting built walls (so a start on a wall
    end works). It's at most `ROCK_WALL_MAX` (8 m), and 3 m if nothing is found within that.
  - The wheel and typing still set it, and the inspector's "Up to the ceiling" can be turned off for
    a fixed height.
  - Ctrl's rectangle puts its floor at the base and its ceiling on top of the walls.
- **Floor tool:**
  - The plane follows the floor top under the cursor. Drawn there, it repaints the top 3 voxels of
    the floor.
  - **Ctrl+wheel** (any time) or the **wheel while dragging** holds the plane a grid step up or down:
    a mezzanine. The wheel alone still zooms while only aiming; that's the change from the brief.
  - A held plane stays put until Esc, a right click or a tool change. A label at the aim and the
    readout say how high it is ("1.0 m up (held)").
  - Click-fills use the walls standing on the plane.
- **Ceiling tool:**
  - The plane is the underside of the first solid over the floor aimed at, so by default it repaints
    the ceiling's lining. Ctrl+wheel lowers it for a dropped ceiling.
  - Click-fills and Auto use the walls on the floor under the plane. Auto works on the last aimed
    floor and plane, since the button takes the mouse off the world.
- **Select, handles, inspector, openings, Shift erase, Move** all work on rock level walls.
  - The handles sit on the wall's top and aim on its base plane.
  - Moving a wall puts it on the floor under the cursor.
  - The inspector shows "Stands at (m)" (the base) and the height in place of the storey.
  - The Opening tool and doors find rock level walls the same way.
- **Undo, sync, save:** everything still goes through `LevelEdits` (`put_objects`, `_do_slab`), so
  it's one undoable host edit like in empty levels. `LevelSchema.fill_defaults` turns a loaded
  `base` / `y` back into ints.

Rock level leftovers:
- A wall taller than its room (typed, or one with nothing over it within 8 m) runs on into any room
  above it, since rooms' insides are filled wherever a wall reaches.
- Walls on different floors (a mezzanine's and the room's) don't snap to or join each other.
- There's no hover preview of a fill here either, and Auto ceiling needs an aim at the floor first.
- Building on top of a prop isn't possible: props aren't voxels while editing, so the aim goes
  through them to the floor.
- `build_net_test` covers only empty levels.

Two changes from the plan below:
- Floors and ceilings are an ordered list of add / erase polygons per storey and kind (objects
  `floor_<n>` / `ceiling_<n>`), not a stored mask. The C++ rasterizes them.
- Storeys are a level object (`storeys`), so changing a height is an ordinary undoable edit.

Decided (Nov 3 2026):
- Empty levels only. Rock levels keep the Room tool. (Later the same day: rock levels get the build
  tools too, building on what you aim at; see above.)
- Storeys like the Sims.
- Walls straight or at 45°.
- Floors and walls are drawn by press, drag, release.

## Why

The Room tool builds a whole lined box in one go. That's fine for carving rooms out of rock, but
laying out a building with it is painful:
- shared walls overlap;
- L-shapes need two rooms;
- you can't add a wall across a room;
- the wall height is fixed before you see the walls.

Building in stages fixes all four: the floor plan first, then walls drawn on it (their height
adjustable as you go), then ceilings over the enclosed parts.

## 1. Storeys

- An empty level has a list of **storeys**: `settings.storeys = [{floor: y, height: h}]`, in
  voxels.
  - A storey's floor top is at `floor`, and its walls are `height` tall (default 30 = 3 m).
  - Storey n + 1's floor sits on top of storey n's walls, with the slab between them
    (`settings.slab`, default 3) as storey n's ceiling and n + 1's floor.
  - A new level starts with one storey on the starter slab.
- **Active storey:** PgUp / PgDn (and ▲ / ▼ buttons in a storey bar next to the cutaway chips) move
  between storeys. Going above the top one adds a storey, which is dropped again if left empty.
- The cutaway follows the active storey: it cuts at the storey's ceiling. The storeys below show
  normally; the ones above are hidden.
- **Changing a storey's height** (a number field in the storey bar, or the wheel while drawing a
  wall) moves every wall that follows the storey height and lifts the storeys above it. It's one
  structure edit and can be undone.

## 2. The model

Three new kinds of structure, alongside rooms and openings:

| Kind | Stored as | Voxels |
|---|---|---|
| Floor | Per storey, a **mask**: one material id per (x, z) column at voxel resolution (0 = none), run-length coded in level.json | The `slab` layers under the storey's floor top |
| Ceiling | Per storey, a mask like the floor's | The slab layers over the storey's walls |
| Wall | An object: `{kind: "wall", storey, a, b, height, thickness, material, inner}`. `a` and `b` are grid points (x, z) in voxels; `b - a` is along X, along Z, or at 45°. `height` is null to follow the storey. | Cells within thickness / 2 of the segment (measured across it), from the floor top to the top of the wall |

Notes:
- **Floors and ceilings are masks, not objects**, like Sims floor tiles. Painting more floor merges
  with what's there, erasing cuts it back, and a 45° fill leaves stair-stepped edges.
  - Edits to a mask are ops: a rectangle or polygon, the material, add or erase.
  - Undo keeps the mask's changed area before and after.
- **Walls are objects**, so they can be selected, moved and resized, and can hold openings.
  - `inner` is an optional second material for one face. A wall at least 2 voxels thick then has
    paint on one side and concrete on the other.
- **Openings attach to a wall**:
  - Fields: `{kind: "opening", wall, along, width, sill, height, type}`.
  - They're measured along the wall, so they move and stretch with it.
  - The opening cuts the wall's cells whose position along the wall is in
    `[along, along + width)` and whose height is in `[sill, sill + height)`.
  - Doors go in straight walls only, as their sliding panel needs an axis.
  - Windows and holes go in any wall.
- **Applying:**
  - It's the v2 structure rule with a new shape list: base (air) → floors, ceilings and walls (the
    later edit wins) → openings (air).
  - Cells are written only if they still hold the old structure. Hand-painted detail survives.
  - It runs in C++: `VoxelWorld.apply_structure` grows wall-segment and column-mask shapes.

## 3. Tools (empty levels)

The rail swaps Room for **Floor**, **Wall** and **Ceiling**. Box, Brush and Replace stay for
detail.

### Floor

- **Drag** a rectangle on the active storey's floor plane. It snaps to the grid, wall lines and the
  edges of floor already there.
- **Click inside** a closed loop of walls to fill the floor inside it. It follows 45° walls.
- **Shift+drag** or **Shift+click** erases.
- The material comes from the catalog. Alt+click picks one up from a floor.

### Wall

- **Press, drag, release** to draw a wall from where you pressed.
  - It snaps to 8 directions.
  - Its ends snap, in this order, to:
    1. wall ends and corners
    2. points along other walls (a T)
    3. floor corners and edges
    4. the grid
  - A snapped point shows a dot and a label ("corner", "on wall").
- **Keep drawing:** when you release on a snapped end, the next drag starts there.
- **While dragging:**
  - The wheel sets this wall's height.
  - Typing sets the length (`4.5`, `45v`), and Tab switches to the height.
  - The readout shows length × height.
- **Ctrl+drag** draws a rectangle of four walls (a quick room). With "Floor and ceiling" checked
  in the inspector, it also fills the floor and the ceiling inside.
- **Shift+drag** along walls erases the parts it covers. A wall is split if needed, and its
  openings go with the deleted part.
- Inspector: material, inner face, thickness, follow the storey height or set its own.

### Ceiling

- **Click inside** a closed loop of walls to cover it at the top of the walls.
- **Drag** a rectangle, as with floors.
- The **Auto** button covers every enclosed floor on the storey.
- Shift erases.

### Openings and doors

Same tools as now, aimed at a wall object:
- The opening attaches to the wall.
- A door prop attaches to a straight wall.

## 4. Editing walls

- **Select a wall** to get handles on its ends and its middle.
  - Dragging an end moves it, and walls joined there follow.
  - Dragging the middle slides the wall sideways; joined walls stretch to stay connected.
- **Joined walls:** two ends at the same point are joined, and a wall end on another wall is a T.
  The joins are worked out from the geometry when needed, so they're not stored.
- **Splitting and merging:** walls split at T-joins, and straight runs of the same material merge
  when saved.
- **Delete** removes the wall and its openings. Floors and ceilings stay.

## 5. Presence and multiplayer

- Wall drags and floor rectangles show for everyone, the way the volume preview does now.
- Moving a wall locks it, like moving a room.
- Mask edits don't lock. They're small ops, the host applies them in order, and the last one
  wins.

## 6. Build order

1. **Model:**
   - storeys
   - floor and ceiling masks
   - wall objects (45° too)
   - openings on walls
   - C++ rasterizing
   - save and load
   - edit ops and undo

   Tests: walls, diagonals, openings, masks, and undo over the network.
2. **Storey bar:** PgUp / PgDn, the cutaway on the active storey, storey height editing.
3. **Floor and Ceiling tools:** drag rectangles, fill enclosures, erase, snapping, Auto ceiling.
4. **Wall tool:**
   - drag in 8 directions
   - end snapping in priority order
   - live height and typed length
   - chained drawing
   - Ctrl rectangle room
   - Shift erase
5. **Editing walls:**
   - handles
   - joined walls following
   - split and merge
   - openings and doors on walls
   - inspector
6. **Polish:** presence of drags, screenshots, a two-person play-test.

## Open questions

- **Splitting walls at T-joins**, so a wall ending on another wall's middle splits it and moves
  with it.
- **Rotating a whole building or storey:** later.
- **Stairs between storeys:** a prop (stairs in the catalog), or a Stair tool that cuts the floor
  above? A prop with a floor cut is simplest.
- **Converting a build-mode level to rock or back:** no.
