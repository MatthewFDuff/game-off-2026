# Level editor v2: plan

Written and agreed 2026-11-02 after the first co-op play-test of v1 (`docs/level-editor.md`). v1's data
model, networking (`LevelEdits` → host → `WorldSync`), undo, props-as-instances, markers, doors
and play-test revert all stay. What changes is how you **look at** the level, how you **build
rooms**, how **props sit**, how **input and UI** work, and how **walking** feels.

## Status

- **Step 1 done (2026-11-02)**: `EditorInput` (input priority, modal gate), `editor_*` actions in
  `InputSetup`, player polling gated, Esc back-out chain, Paper theme (dark blue-gray accent) and the
  new HUD layout (top bar, tool rail, inspector, catalog drawer with prop categories and search,
  hint line, toasts, help and menu modals), scrubbable number fields, synthesized UI sounds.
  Tested headless (`editor_input_test`, `editor_tool_test`, `net_test.sh editor_test`) and in
  screenshots; not yet play-tested by hand.
- **Step 2 done (2026-11-03)**: `EditorCamera` (builder view: orbit / pan / zoom / Q E / frame,
  mouse always free, tools aim through the mouse), cutaway (terrain shader `cut_height`, a cap plane
  colored from the cut layer's voxels, aim ray starts at the cut, marker gizmos above it hidden;
  Auto / Manual / Off), V switches views, walk view lands under the mouse and walks (F flies).
  Choices made while building it: a right click without a drag is the tool's RMB, so the Brush
  carves with Shift+LMB in the builder view; the free cursor moved from V to N (walk view only);
  Auto keeps its last height while the pivot is over solid rock, so panning across walls doesn't
  flash the roof back. Tested headless (`editor_builder_test`) and in screenshots.
- **Step 3 done (2026-11-03)**: `VolumeSteps` (`scripts/editor/tools/volume_steps.gd`) drives Room,
  Box and Replace: corner, floor (on the start surface's plane), height (a vertical line through
  the floor's center, relative to where the aim was so the default holds until the mouse moves);
  wheel / Shift+wheel, typed meters or `v` voxels, Tab, Enter, RMB / Backspace back; edge labels and
  a readout card. Choices made while building it: the start snaps only x / z to the grid (y stays on
  the surface, so a floor at 39 isn't dropped to 35); a room started on a wall stands on the floor
  below; starting on a floor's top or on the cut defaults the height downward, and a room dug from
  the cut reaches the floor under the camera's pivot so it lines up with the room beside it; looking
  almost straight down, the mouse doesn't set the height (wheel and typing do). Tested headless
  (`editor_volume_test`, `editor_tool_test`) and in screenshots.
- **Step 4 done (2026-11-03)**: `room` and `opening` objects (`LevelSchema`), structure edits in
  `LevelEdits` (`put_objects` batches, `$n` ids for objects made in the same edit, door props keep a
  linked opening), the `structure` op (`LevelStructure` builds it, `VoxelWorld.apply_structure`
  runs it), the Room tool making room objects, Room from space (Alt+click), room selection and
  handles (`scripts/editor/tools/room_handles.gd`), room inspector (linings from the catalog, exact
  corners), Move / Duplicate with openings, doors and contents (`room_tools.gd`), Delete filling
  back in, and the Opening tool (doorway / window / hole). Choices made while building it: any
  natural rock (dirt, clay, sand, gravel pockets) counts as untouched base, and filling back uses
  plain rock; a room's inside and an opening are always cut, and a cell no room claims any more
  always goes back to base, but a new or moved lining only replaces untouched base (so it never
  walls up hand-carved spaces) and a re-line only what still has the old lining; Room from space
  adopts without touching voxels; Auto cut follows the selected room's ceiling. Deferred to later
  steps: the floor handle, rotating rooms, arches, a room list in the inspector, and warnings for
  props left floating after a resize (step 5). Tested
  headless (`editor_room_test`, `editor_room_tool_test`, `net_test.sh editor_test` with a client's
  room and resize) and in screenshots.

- **For steps 4-5**: `docs/lab-design.md` section 9 (the lab layout plan) lists schema items to fold in:
  door prop placeholders (single sliding 1.2x2.2 m, double 2.4x2.2, security with reader, blast
  2.4x2.4, vent hatch 1.2x1.2) and a trigger / on_use `actions` field (power, lock / unlock / open /
  close a door, turn off a spawner, replace a box's material). Its non-schema hooks (lab.gd,
  horde_director.gd, scripts/tools) belong to that plan, not the editor.

## What the play-test told us

| Feedback | Cause in v1 | v2 answer |
|---|---|---|
| We imagined multiplayer MagicaVoxel / Sims build mode | Only a first-person fly cam | **Builder view**: orbit camera from above, mouse always free, cutaway; first-person kept as **Walk view** |
| Can't see what others are doing | Only their bodies are visible | Presence: everyone's camera, cursor, tool preview and selection in their color |
| One click + drag rooms are hard to size | Two-corner box with a surface raycast; the second corner jumps onto walls | **Three-click rooms** on a locked plane, live dimensions, wheel and typed sizes |
| Rooms can't be resized | A room is a one-off voxel op; nothing remembers it | **Rooms become objects** with handles; resizing re-lines only what changed |
| Props hang in the air / sink into walls | Footprint centered on the cursor cell, no support or overlap check | **Mounting rules**: floor / wall / ceiling props, contact required, push-out, red ghost when invalid |
| Wheel in a menu changed fly speed; Tab moved focus and Space then pressed a button | Movement polls `Input` directly; Godot focus navigation left on; one panel for everything | **Input router** with a strict priority order; no keyboard focus on buttons; no Tab focus |
| Controller feels meh | `move_toward` acceleration, jump only on the exact frame on the floor | Coyote time, jump buffer, friction + Quake-style air control (bunny hops), variable jump |
| Menus feel janky | Default Godot theme, one long side panel | Paper UI (from Puzzle Pals / Edgeless), laid out as toolbar + catalog drawer + inspector card |

## 1. Two views

One key (**V**) switches the local view. Each person picks their own; the level, tools and
selection are the same in both.

### Builder view (the default when editing)

- **Camera**: orbits a pivot point on the ground. Right-drag or middle-drag orbit, Shift+middle-drag
  or **WASD** pan (relative to the camera's yaw), **wheel** zoom, **Q / E** rotate 45°, **F** frame the
  selection, **Home** frame the whole level. Pitch clamped 15°–89° (top-down allowed). Smoothed.
- **Mouse is never captured.** Tools aim with a ray from the mouse through the camera, so UI and
  world share one cursor (no Tab to free the mouse).
- **Cutaway** (rock levels are solid from above, so this is required): a horizontal **cut height**.
  Voxels above it aren't drawn and the cursor ray ignores them. **Page Up / Page Down** move it by one
  grid step; **C** cycles `Off → Auto → Manual`. Auto puts it at the ceiling of the room under the
  pivot. Cut faces show as a flat hatched cap (rock cross-section) using the back-face trick in
  `voxel_terrain.gdshader`: a fragment above the cut is discarded; a back face below it is drawn in
  the cap color.
- **Walls-down** (Sims style), toggle with **X** in builder view: the room-facing walls on the camera's
  side are drawn at 20% height so you can see in at low angles. Shader-only, like the cut.
- **Grid**: a faint grid on the plane under the cursor, at the snap size, fades with distance.

### Walk view (the existing first person, improved)

- Walks with gravity and the new controller (section 6), or flies (**F** toggles noclip fly). Mouse
  captured; tools aim from the crosshair as in v1. This is for detail work, checking scale and
  sight lines, and testing jumps.
- Entering walk view from builder view drops you at the point under the mouse (feet on the floor
  there), facing the camera's direction. Leaving it puts the builder pivot at your feet.

### Presence (both views)

- Each person has a color (already used for name tags).
- Builder-view users appear to others as a small floating camera gizmo with their name; walk-view
  users as their body (as now).
- Everyone's **cursor box, tool preview (room in progress, prop ghost, brush) and selection
  outline** are drawn in their color for everyone. Sent unreliable at ~10 Hz, only while it
  changes: `{peer, view, cursor, tool, preview}`.
- A thing someone is resizing or moving is **soft-locked**: others see it outlined in that color
  with their name and can't grab it until they let go. Locks are host-tracked and drop on
  disconnect.
- A small roster chip (top-left) lists who's here, their color and view; click a name to jump the
  camera to them.

## 2. Rooms as objects

### The model

A room becomes a level object (`kind = "room"`) instead of a fire-and-forget voxel op:

```
{id, kind: "room", name, from: Vector3i, to: Vector3i,   # the inside (air), [from, to)
 floor, wall, ceiling: material, thickness: int, order: int}
```

plus **openings** (`kind = "opening"`: doorway, window, arch; a box that cuts through linings and
belongs to a room wall, so it moves with the wall).

**Doors cut their own opening.** Placing a door prop in a wall creates an opening the size of the
door, linked to it (`opening.door = <door id>`); moving or deleting the door moves or removes its
opening. The Opening tool only cuts holes: it never places a door.

The **structure** of the level is a function from a cell to a voxel, computed from all rooms and
openings:

1. inside an opening, or inside any room's interior → air
2. else inside a room's lining → that room's floor / wall / ceiling material (latest `order` wins)
3. else → the level's base (rock material for rock levels, air for empty levels)

`voxels.bin` is still the truth (box, brush, replace and pasted detail are just voxels). The
structure is only used to work out what a room change should touch.

### Applying a room change

Adding, resizing, re-lining or deleting a room or opening (one new `WorldSync` op,
`{type: "structure", region, before: [rooms], after: [rooms]}`) runs per cell over the union of the
old and new outer boxes:

- `old = structure_before(cell)`, `new = structure_after(cell)`; skip if equal.
- Write `new` if the cell still holds `old` (nobody painted it), **or** if the cell is leaving every
  room (it must become rock / air again).
- Otherwise leave it: hand detail on walls survives a resize or a lining change.

This runs in C++ (`VoxelWorld.apply_structure`), since a big room is hundreds of thousands of cells.
Each peer runs the same op on the same voxels, so worlds stay identical. Undo records the voxel box
before / after plus the object before / after, grouped, like v1.

### Existing levels

`levels/lab` was converted from the generator and has no room objects. Its geometry stays as plain
voxels. A **Room from space** action (room tool, Alt+click inside a carved space) finds the largest
axis-aligned air box around the click and adopts it as a room object with the linings it finds, so
old rooms can be resized too.

## 3. Building rooms: three clicks

Room tool, either view:

| Step | Mouse | Wheel | Shown |
|---|---|---|---|
| 1. Start corner | Cursor on the surface under the mouse, snapped | — | Snapped cell box |
| 2. Floor | Ray hits the **horizontal plane** at the start's floor height (never jumps onto walls); sets the opposite corner | Grow / shrink **width** one grid step; Shift+wheel **length** | Floor rectangle, edge labels |
| 3. Height | Ray hits a vertical plane through the far edge facing the camera | Grow / shrink height one grid step | Full box, all three labels |
| Click again | Builds it | | |

- Default height when step 3 starts: the last height used (first time: 3 m / 30 voxels).
- **Right-click or Backspace** steps back one step; **Esc** cancels.
- **Type a number** during step 2 or 3 to set the active dimension exactly (in meters, `2.5`, or
  voxels with a `v`, `25v`); **Tab** switches the active dimension; **Enter** commits it.
- **Dimensions**: `Label3D`s on the edges in meters (`6.0 m`), plus a readout card at the top
  center: `Room · 6.0 × 4.5 × 3.0 m (60 × 45 × 30 voxels)`. The active dimension is highlighted.
- The same three-step flow is used for **Box** (fill / carve) and **Replace**, so every volume tool
  works the same way.
- Wheel during a step always sizes; outside a step it zooms (builder) or does nothing (walk). This
  is the only thing the wheel is shared with, and the hint line says which it is doing.

## 4. Resizing and editing rooms

- **Select** a room by clicking its floor or wall in the Select tool (or in the room list in the
  inspector). It outlines in your color, with **handles**: one per wall face, one on the ceiling,
  plus corner handles for two walls at once.
- **Click-or-drag** a handle: press and release on it to pick it up (it follows the mouse along its
  axis, click to drop), or press, drag, release. Wheel nudges a picked-up handle by one grid step.
  Live dimension labels as above.
- Moving a wall **moves its openings** with it. Openings can't go past the room's corners.
- Inspector for a room: name, floor / wall / ceiling materials, thickness, exact size and position
  fields, Delete (fills it back in), Duplicate.
- **Move** a whole room (M): picks it up with its openings; props and markers inside move with it
  (optional checkbox, on by default).
- Props left unsupported after a resize turn red with a warning in the status card ("2 props are
  floating"); click the warning to select them.

## 5. Props that sit on things

Each prop gets a **mount** in `PropCatalog` (default `floor`): `floor`, `wall`, `ceiling`, `any`.
Corkboards, whiteboards and wall shelves are `wall`; lights hang from the `ceiling`.

Placement from the cursor ray's hit (voxel or another prop's model):

- **Floor props** on an upward face: the bottom rests on the hit surface. On a wall face: dropped to
  the floor below the cursor, back against the wall, facing away from it.
- **Wall props** on a wall face: back flush against the wall, facing out (facing set automatically,
  R overrides), bottom snapped to the grid.
- **Ceiling props** on a downward face: top flush against the ceiling.
- **Push-out**: if the ghost overlaps solid voxels or another prop's box, it's pushed out along the
  hit normal, then sideways (up to half its footprint) to the nearest free spot.
- **Valid** = no overlap **and** at least one voxel of contact on its mount side (floor under it,
  wall behind it, ceiling above it). Contact counts other props, so a lamp can sit on a desk.
  Invalid ghosts are red and clicking does nothing (a short "needs something to sit on" toast).
- **Grid**: props snap to the grid along the surface but always sit flush on it (the snap never
  lifts them off it).
- Moving or duplicating an existing prop uses the same rules.
- A level-check button (inspector, Level tab) lists floating or overlapping props.

Markers keep free placement (triggers and kill zones are volumes), but spawns, clone vats and
horde spawners rest on the floor the same way.

## 6. Character controller

Shared by play and the editor's walk view (`scripts/player/player.gd`, `_walk`).

- **Coyote time** 0.1 s: you can still jump just after walking off a ledge.
- **Jump buffer** 0.12 s: a jump pressed just before landing fires on landing.
- **Friction model** instead of `move_toward`: ground friction (~6/s) plus acceleration toward the
  wish speed. **Friction is skipped on the landing frame when a jump is buffered**, so chained jumps
  keep their speed (bunny hopping).
- **Air control** (Quake style): acceleration only adds speed along the wish direction up to a small
  air wish speed (~1 m/s), so turning the mouse while strafing curves and slowly gains speed.
  A soft cap (e.g. 1.6 × sprint speed) keeps it from breaking levels; tunable.
- **Variable jump height**: releasing jump while rising cuts upward velocity in half.
- **Feel**: small camera dip on landing (by fall speed), crouch-jump (crouch in the air raises the
  feet), smoothed crouch height, slight FOV kick when sprinting. All exported and tunable.
- Headless test: scripted inputs check coyote jumps, buffered jumps, and that 10 chained hops keep
  ≥ 95% of speed while plain walking doesn't exceed sprint speed.

## 7. Input: one router, clear rules

A new `EditorInput` node owns editor input. Priority, highest first; each layer eats what it uses:

1. **Modal dialogs** (save-as, new level, confirm delete, help): everything.
2. **Text entry** (a focused `LineEdit` / number field): all keys. Enter commits and releases focus,
   Esc reverts and releases. Clicking the world also releases.
3. **Mouse over UI**: any click and wheel over a panel goes to the panel and never reaches the world
   or the camera. (Every panel has `mouse_filter = STOP`; scroll containers eat the wheel even at
   their ends.)
4. **Active tool step** (room step 2, a picked-up handle): wheel, number keys, Tab, Backspace.
5. **Tool and editor shortcuts** (InputMap actions, see the keymap).
6. **Camera / movement**.

Rules that fix the play-test bugs:

- Player and camera movement **stop polling `Input` directly** while editing; they read
  `EditorInput.movement()` and `EditorInput.wants_keyboard()`, which return nothing while layers 1–2
  are active. Space can't fly you up while you type, and can't press a button.
- **No keyboard focus on buttons**, toggles, tabs or swatches (`focus_mode = NONE`), and the editor
  theme removes Godot's `ui_focus_next / ui_focus_prev` (Tab) navigation. Only text fields take focus.
- All shortcuts are **InputMap actions** (`editor_*`), defined in `InputSetup` like gameplay
  actions, so the help overlay and tooltips print the real keys, and rebinding later is easy.
- Number fields are **scrubbable** (drag left / right on the label) and accept typed values; no
  SpinBox arrow buttons. Changing a value sends one edit when you let go, not one per step.
- Esc closes the innermost thing: tool step → selection → open popup → (nothing open) pause menu.

### Keymap

| Key | Builder view | Walk view |
|---|---|---|
| V | Switch to walk view | Switch to builder view |
| WASD | Pan | Move |
| Space / Ctrl | — | Jump / crouch (fly: up / down) |
| F | Frame selection | Toggle fly |
| Right / middle drag | Orbit | (mouse look) |
| Wheel | Zoom; sizes during a tool step | Sizes during a tool step |
| Q / E | Rotate camera 45° | — |
| Page Up / Down, C | Cut height, cut mode | — |
| 1–8 | Tools (Select, Room, Box, Brush, Replace, Opening, Prop, Marker) | same |
| R | Rotate the ghost / selection | same |
| G | Grid snap 1 / 5 / 10 | same |
| M, Ctrl+D, Delete | Move, duplicate, delete selection | same |
| Alt+click | Eyedropper (material, prop type, room linings) | same |
| Ctrl+Z / Ctrl+Y / Ctrl+S | Undo / redo / save | same |
| F5 | Play-test | same |
| F1 | Help overlay with all keys | same |
| Esc | Back out one step, then pause menu | same |

## 8. Editor UI (Paper style)

Editor only; in-game HUD and menus keep their own style.

### Style source

Port from **Puzzle Pals** (`C:\Projects\Godot\puzzle-pals`), the documented version of the style
Edgeless started; its `docs/ui-style-guide.md` is the reference. It's all `StyleBoxFlat` (cream
fill, thick light rim, rounded corners, small drop shadow), no shaders.

Copy into `res://scripts/editor/ui/` and `res://assets/ui/` (paths fixed up, uids regenerated):

- `common/ui/data/puzzle_pals_theme.tres` → `editor_theme.tres`, set on the editor's root
  `Control` only (not `gui/theme/custom`, so the game's UI is untouched).
- `common/fonts/Lato-Black.ttf`, `Lato-Regular.ttf`; `common/ui/art/icons/ui_*.svg`.
- `common/ui/paper_palette.gd` (`PaperPalette`, tokens + `card(radius, rim)` for code-built panels).
- `common/ui/modal_gate.gd` (`ModalGate`), which becomes layer 1 of `EditorInput`.
- `pop_button.gd` (hover punch and tilt, toned down for a dense tool rail). Puzzle Pals' click and
  pop `.wav`s have unknown licenses (their own SOURCES.md says so), so the editor synthesizes
  `ui_click` / `ui_pop` in `Sfx` instead.

Key values: paper `#FBF8F2`, raised `#FFFDF9`, well `#F3EEE5`, rim `#ECE6DA`, ink `#14323F`, muted
ink `#5E7C8B`, focus `#F2AD29`, danger `#B32727`; Lato Black 16 default, Regular for body; cards
radius 18 / rim 5 / shadow (0, 4); buttons radius 12 / rim 3, press drops the shadow 3 → 1 and the
label 2 px. **Accent: dark blue-gray**, Edgeless's slate (`#14323F`, hover `#22495A`, pressed
`#0B1E26`) in place of Puzzle Pals blue, in both the theme and `PaperPalette.ACCENT*`. Person colors (presence) go on chips and outlines, never on panels.

Over a 3D world the cream panels are opaque, so they're kept to the edges and compact; the hint
line and measure readout are small `PaperPill`s.

### Layout

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ [lab ▾] ● saved   (●Matt builder ●Zack walk)     Room 6.0 × 4.5 × 3.0 m     [↶][↷][💾][▶ Play] │
│ ┌──┐                                                                    ┌──────────────┐ │
│ │⬚ │ Select                                                             │ Inspector    │ │
│ │▭ │ Room                                                               │ (tool options│ │
│ │■ │ Box                                                                │  or the      │ │
│ │● │ Brush                         (world)                              │  selection)  │ │
│ │⇄ │ Replace                                                            │              │ │
│ │▯ │ Opening                                                            │              │ │
│ │🪑│ Prop                                                               │              │ │
│ │⚑ │ Marker                                                             └──────────────┘ │
│ └──┘                                                                                    │
│ toasts                     LMB: start corner · RMB: back · wheel: zoom                  │
│ ┌ Catalog ─[Lab][Office][Storage][Industrial][Doors]──────── 🔍 ────────────────────────┐ │
│ │ [thumb][thumb][thumb][thumb][thumb][thumb][thumb][thumb][thumb]  ← materials or props │ │
│ └──────────────────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

- **Top bar**: level name (menu: Save, Save as, Level settings, Quit to menu), saved / unsaved dot,
  roster chips, the **measure readout** (center, only while sizing), undo / redo / save / play-test.
- **Tool rail** (left): icon buttons with the key number; tooltip shows name, key and a one-line how-to.
- **Inspector card** (right): the tool's options, or the selection's properties (room, prop, marker,
  opening). Tabs at the top: **Tool**, **Selection**, **Level** (settings, room list, level check).
- **Catalog drawer** (bottom, collapsible with **B**): materials for volume tools and Brush, props by
  category for the Prop tool, opening types for Opening, marker types for Marker. Thumbnails, names on
  hover, search box, recent row. Categories come from a `category` field added to `PropCatalog`.
- **Hint line** (above the drawer): what the mouse buttons and wheel do right now.
- **Help overlay** (F1), **pause menu** (Esc), **new level / level picker** (from the main menu's
  Edit level), **confirm dialogs**: Paper modals.
- Walk view hides the rail and drawer (crosshair + hint line + top bar). **B** opens the drawer and
  frees the mouse until it closes; nothing uses Tab to free the mouse any more.

## 9. Code changes

| Area | Change |
|---|---|
| `scripts/editor/editor_camera.gd` (new) | Builder orbit camera, cutaway / walls-down uniforms, grid overlay |
| `scripts/editor/editor_input.gd` (new) | The router (section 7), actions, `wants_keyboard()`, `movement()` |
| `scripts/editor/editor_tool.gd` | Split into one script per tool under `scripts/editor/tools/` sharing a base (`aim(ray)`, steps, preview); aims from either view's ray |
| `scripts/editor/tools/volume_steps.gd` (new) | The three-step sizing used by Room, Box and Replace |
| `scripts/editor/room_handles.gd` (new) | Selection handles, click-or-drag, nudge |
| `scripts/editor/prop_placement.gd` (new) | Mount rules, push-out, support check |
| `scripts/editor/presence.gd` (new) | Broadcasts and draws everyone's cursor / preview / selection, soft locks |
| `scripts/editor/ui/` (new) | Paper theme and widgets, top bar, tool rail, inspector, catalog drawer, modals; replaces `editor_hud.gd` |
| `scripts/level/level_schema.gd` | `room` and `opening` kinds and fields; prop `mount` / `category` |
| `scripts/level/level_edits.gd` | Room / opening edits produce `structure` ops; lock requests |
| `scripts/net/world_sync.gd` | `structure` op |
| `extension/src/voxel_world*.cpp` | `apply_structure(region, before, after, base)`; raycast with a max height (cutaway) |
| `shaders/voxel_terrain.gdshader` | `cut_height`, cap color, walls-down |
| `scripts/player/player.gd` | Controller (section 6); reads `EditorInput` while editing |
| `scripts/world/prop_catalog.gd` | `mount` and `category` per prop |
| `tests/` | Room three-click and resize (incl. detail kept), structure op net test (byte-identical), prop placement validity, controller feel, input router (wheel over panel, Space in a text field) |

## 10. Build order

Each step is usable and tested before the next.

1. **Input router + Paper theme shell**: `EditorInput`, actions, focus rules, Paper theme, new HUD
   layout with the existing tools moved in. Fixes the jank first.
2. **Builder view**: orbit camera, mouse-ray aiming for all existing tools, cutaway, V switch, walk
   view drop-in.
3. **Three-click volumes** for Room / Box / Replace, with labels, wheel and typed sizes.
4. **Rooms as objects**: schema, `structure` op in C++, room select + handles + resize, Room from
   space, openings.
5. **Prop placement**: mounts, push-out, support, red ghosts, level check.
6. **Presence**: cursors, previews, selections, soft locks, roster.
7. **Character controller**.
8. Polish: walls-down, grid overlay, help overlay, catalog search / categories, sounds.

The controller (7) touches nothing else and can be done any time, e.g. first, if we want to
play-test movement sooner.

## Open questions

- Walls-down: shader trick (fast, approximate) or real per-room hiding (exact, more work)?

Decided 2026-11-02: free cut height only (no floor selector); dark blue-gray accent; doors cut
their own opening, openings never add doors.
