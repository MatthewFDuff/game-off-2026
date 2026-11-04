# The cubicle is the menu

Decided 2026-11-03. The game has no menu screens. It opens in the LLM operator's cubicle
(`levels/cubicle`, today the intro scene), the player walks around it, and the computer on the desk
is the only menu surface. The cubicle intro's thought log (`docs/story.md`, act 1) becomes what
happens after New game on that same screen. The game's name on the screen is **Fung AI**.

This replaces `scenes/menu.tscn` / `scripts/ui/main_menu.gd` and `scenes/intro.tscn` /
`scripts/story/intro.gd`. The old flat prototype (artifact, 2026-11-03) is superseded except for its
colors and the save-game brainstorm.

## 1. The room

The cubicle as built by `scripts/tools/build_cubicle.gd`, extended:

- The cell (3 x 3 m, grey partitions) keeps its desk with the monitor against the north wall, the
  chair, the drawer desk, the trash can, the "Hang in there" poster (west partition) and the sticky
  note (north partition, "PRESS SHIFT WHEN IT STOPS").
- New on the desk: a **fake plant** (`fake_plant`) and a **rubber duck** (`rubber_duck`), both
  standing on the desk top. New on the floor behind the chair, along the south partition: a
  **sleeping bag** (`sleeping_bag`). A **nameplate** (a `corkboard_small` note on the partition by
  the opening) whose text the scene rewrites: the employee's name, "LLM Operator" and the shifts
  worked. The balance owed is kept (`GameSettings.balance_owed`) but never shown before the
  statement: no money anywhere in the cubicle or during the shift (no "-$" toasts in the lab), so
  the ending's bill is the first the player hears of it (decided 2026-11-04).
- The south partition has a 1 m **opening** onto a **hallway** 2 m wide running east to west, with
  three more cubicles on its far side (desk, monitor off, chair; dark, one dim ceiling light every
  other bay). The hallway ends in partitions both ways. The world grows to fit (about 19 x 6 x 13 m).
- Markers: `spawn` 1 standing beside the chair facing the monitor; a `trigger` box `t_leave` filling
  the opening (the full width and height of the doorway, one voxel deep into the hallway); a
  `speaker` in the cubicle's ceiling; the desk lamp and screen lights as today.
- Lighting as the intro has it: warm desk lamp, cold screen cast, ambient 0.2. The hallway is darker.

Props are placeholders (`PropCatalog` entries, exported by `export_vox.gd` to
`assets/vox/props/<name>.vox`), to be redrawn by the team in MagicaVoxel:

| Prop | Size (w x h x d voxels) | Look |
|---|---|---|
| `fake_plant` | 4 x 8 x 4 | A plastic pot, a stem, a blob of leaves |
| `rubber_duck` | 3 x 3 x 4 | Yellow body, a head, an orange bill |
| `sleeping_bag` | 7 x 2 x 18 | A cloth roll, slightly unzipped at the head |

## 2. Being in the room

`scenes/cubicle.tscn` (`scripts/story/cubicle.gd`, `class_name Cubicle`) is the main scene and
`Net.MENU_SCENE`. It loads the level into a `VoxelWorld` the way the intro did, and spawns the
ordinary first-person `Player` (`scenes/player.tscn`) at the spawn marker: walking, gravity, crouch,
flashlight, unarmed, no HUD, no networking (`net_peers` stays empty). The mouse is captured on the
first click ("Click to look around" on the first frame), released by Esc, as in the lab, and
captured again by itself whenever the room is the player's again (stepping away from the computer,
N or Esc on the clock-out prompt, closing a note, being set back from the hallway): no second
click.

**Interacting.** E (or a click) with the mouse captured casts from the camera against the boxes of
the interactable props within 2.5 m; a prompt at the bottom center names what the player is aiming
at: `[E] Use computer`, `[E] Rubber duck`, `[E] Sleeping bag`, `[E] Read`. The poster and sticky
note read as notes (the reader panel style). The plant says "It is plastic. It is Fung AI property."

**Leaving.** `t_leave` marks the opening. The player may step through it and a little way into
the hallway (`HALL_DEPTH`, 1.2 m straight out; `HALL_SIDE`, 0.5 m to either side of the opening);
past that: an error buzz, a red light over the hallway side of the opening flashes, the player is
frozen for 1.5 s (`process_mode` disabled), a subtitle in the intercom's style says the line, then
the player is set back one step inside the opening. The lines escalate with each attempt and the
count is kept for the shift (`Cubicle.exits`):

1. "You must remain in your cubicle during your shift."
2. "Fung AI reminds you: the hallway is not your cubicle."
3. and after: "Noted."

**Clocking out.** E on the sleeping bag, or Esc in the room (not at the computer), shows the
clock-out prompt in the console's style: "Clock out? Fung AI wishes you a restful six hours."
Enter / Y: fade to black and `get_tree().quit()` (on the web build: "You may close the tab."). Esc /
N: back in the room.

**The computer.** E or a click on the monitor zooms the camera onto the screen (a second camera
tweened from the player's camera to 0.35 m in front of the screen, 0.8 s, as the intro does) and
releases the mouse. The player is frozen while the screen is in use. Esc backs out one page at a
time; from the top page it zooms back out and recaptures the mouse on the next click.

**The duck.** E on the duck: a squeak, then the computer zooms in with the **Site maintenance**
page (section 3) instead of the sign-in.

**Payroll.** After a shift ends (section 5), the player is back in the cubicle exactly as at launch,
except the screen already shows the statement's header and blinks "1 new statement". Using the
computer rolls the statement line by line with the register tick, then Guy Fung's note, then
"Press SHIFT to sign in". The nameplate's balance is updated.

## 3. The screen

The console is drawn on the monitor's screen voxels as today: a `SubViewport` (240 x 160, raise to
320 x 200 if the pages need it) on a quad, the pixel font at 1x (one font pixel per screen texel),
green on near-black, the header line and its rule. Every page is keyboard-driven: arrows move,
Enter / SHIFT select, Esc backs out (Backspace too, anywhere but in a field, where it erases),
typed characters fill a field. Mouse clicks on a line are
welcome if cheap (project the mouse onto the quad and push the event into the viewport) but not
required. The chosen line carries an amber `>` caret.

Pages:

- **SPLASH**: `FUNG AI` at 3x, under it "Press SHIFT to sign in" blinking. Nobody is signed in
  when the game opens, even with a name on file: SHIFT always goes to SIGN IN, where the name on
  file is already typed, so Enter confirms it. MAIN then shows "signed in: Matthew".
- **SIGN IN**: "Employee name:" and a typed field with a block cursor (letters, digits, space, up
  to 20). Enter saves it (`GameSettings.name`, `Net.player_name`) and goes to MAIN (or back to
  SETTINGS when its Name row opened the field, titled CHANGE NAME).
- **MAIN**: SINGLEPLAYER / MULTIPLAYER / SETTINGS / SIGN OUT. Sign out returns to SPLASH. On the
  web build MULTIPLAYER is dimmed with "needs the desktop build".
- **SINGLEPLAYER**: CONTINUE / APPLY FOR JOB / BACK. CONTINUE is dimmed with "no record on file"
  when there is no shift on file (`docs/shift-save.md`); lit, its note names the room and the
  time on shift, never the money.
- **APPLY FOR JOB** (the new game): orientation (section 4), then
  `Net.start_solo("laboratory", "play")`.
- **MULTIPLAYER**: HOST A SHIFT / JOIN A SHIFT / BACK.
- **HOST**: `Net.open_session(port, "waiting_room", "play")`. Shows the port, the LAN addresses
  (as `LabHud.hosting_info` lists them), "friends outside your network join your public IP
  (forward UDP 24680)", and the roster live from `Net.players` ("Zack · in orientation"). SHIFT:
  orientation, then `Net.enter_level()`. Esc: `Net.close_session()` and back.
- **JOIN**: "Host address:" field (remembers the last one, `GameSettings.address`). Enter: "Dialing
  203.0.113.5:24680..." and `Net.join`. `session_started`: "Accepted. 2 staff on. Press SHIFT to
  begin orientation." then orientation, then `Net.enter_level()` (which waits for the host).
  `session_ended(reason)`: the reason, "Enter: retry · Esc: back".
- **SETTINGS**: the shared `SettingsMenu` control (section 6) at 1x.
- **LOG**: the thought log from `intro.gd`, unchanged in behavior: "session started. operator:
  you. shift: night.", one line per SHIFT after its thinking pause, the email after line 4 (the
  email window and the Accept / Decline buttons stay on the HUD layer over the screen), Decline
  runs the log out into the vignette, the heartbeat, death, the trash-bag text and "Would you like
  to go back and accept?" (Yes: the email; No: back to MAIN). Accept: "Transfer accepted. Report
  to Site 3 tonight. A car has been sent.", the fade, then the start (section 4). F9 accepts at
  once. `pause_scale` shortens the pauses for tests.
- **STATEMENT**: the payroll roll (section 5).
- **MAINTENANCE** (the duck): "SITE MAINTENANCE · authorized personnel and ducks". A level list
  (`LevelData.list()`, arrows pick), NEW LEVEL (name, size Small / Medium / Large, start Rock /
  Empty, as `main_menu.gd` has them), PLAY SOLO, HOST CO-OP, EDIT LEVEL (co-op editor), JOIN THE
  EDITOR AT <address>, BACK. These call `Net.start_solo` / `Net.host` / `Net.join` directly, with no
  orientation and no waiting room, exactly as the old menu's "Testing and editing" did.

The team's launch flags (`--solo`, `--host`, `--join=`, `--edit`, `--level=`, `--name=`,
`--skip-intro`) are unchanged: `Net` handles them before the cubicle loads.

## 4. Orientation and starting a shift

"Orientation" is the thought log. `GameSettings.orientation` is `play` (default) or `skip`
(replacing the menu's "Skip the intro" checkbox; `--skip-intro` also skips). Skipped, the screen
shows the transfer note for a moment and starts.

Starting means, by how the session was begun:

| Begun by | Start |
|---|---|
| NEW GAME | `Net.start_solo("laboratory", "play")` |
| HOST (session open) | `Net.enter_level()`: the host loads the level scene and tells every peer it is open |
| JOIN (accepted) | `Net.enter_level()`: loads the level scene once the host's is open, else waits on the transfer note ("Waiting for the host to begin the shift...") |

## 5. The shift ending in the cubicle

`Ending._show(lines, net)` no longer rolls a panel over the lab. It sets `Net.pending_statement =
lines` and `Net.pending_total = net` at once, fades to black over 2 s, and calls `Net.leave()`. The
host's leave closes the server; a peer whose fade is interrupted by the host's disconnect still has
its lines, so every player lands in their own cubicle with the statement waiting on the screen.
`Cubicle` rolls it and then clears it; `GameSettings` keeps `shifts_worked` and `balance_owed` (the
nameplate's numbers) and the cubicle updates them when the roll finishes.

`Net.end_reason` ("The host closed the session.", "Couldn't reach the host.") shows as a line on the
screen's splash, as the old menu's status line did, when there is no statement pending.

## 6. Settings, in the cubicle and in the pause menu

`GameSettings` (autoload, `scripts/game_settings.gd`) owns `user://settings.cfg` (the file the old
menu wrote; keep its `player/name`, `player/address`, `player/level` keys so names carry over):

| Key | Values | Applied by |
|---|---|---|
| `name` | string, 20 chars | `Net.player_name` |
| `orientation` | `play` / `skip` | the cubicle |
| `fullscreen` | bool | `DisplayServer.window_set_mode` |
| `mouse_sensitivity` | 0.5 to 3.0, step 0.25 (a multiplier of the player's 0.0025) | `Player` |
| `fov` | 60 to 110, step 5 | `Player`'s camera |
| `volume_master` | 0 to 10 | the Master bus |
| `volume_effects`, `volume_music` | 0 to 10 | `Sfx` offsets on `play` / `play_at` and on the ambience and stings |
| `address`, `level`, `recent_addresses` | strings | the JOIN and MAINTENANCE pages |
| `shifts_worked`, `balance_owed` | ints | the nameplate |

`set_value` saves and applies at once and emits `changed(key)`. `apply_all()` runs at startup.

`SettingsMenu` (`scripts/ui/settings_menu.gd`, `extends Control`, `static func create(scale: int)`)
draws the rows (Orientation, Fullscreen, Mouse sensitivity, Field of view, Master, Effects, Music,
and on the console only a Name row showing the name on file) in the pixel font at `8 * scale` px,
labels left and values right, the chosen row with the amber caret; `handle_key(event) -> bool`
moves (up / down), adjusts (left / right, Enter toggles two-state rows; Enter on Name emits
`rename`, and the console opens the sign-in field, returning to SETTINGS) and backs out (Esc or
Backspace emits `closed`). The console embeds it at 1x (`create(1, color, true)`); the pause panel
at 2x without the Name row.

**Pause menu** (`LabHud`): "SHIFT PAUSED", Resume, Settings (the menu in place of the buttons; Esc
returns), Invite (the hosting info, host only), Leave shift (the old End session / Leave to menu).

## 7. Files and ownership

| Owner | Files |
|---|---|
| Cubicle (Opus) | `scripts/tools/build_cubicle.gd`, `levels/cubicle/*` (regenerated), `scenes/cubicle.tscn`, `scripts/story/cubicle.gd` (+ any console page scripts it wants under `scripts/story/`), deletes `scenes/intro.tscn`, `scripts/story/intro.gd`, `scenes/menu.tscn`, `scripts/ui/main_menu.gd`; `tests/cubicle_test.gd` (from `intro_test.gd`), `tests/cubicle_shots.gd` (from `intro_shots.gd`) |
| Session and settings (Opus) | `scripts/net/net.gd`, `scripts/game_settings.gd` (new) and its autoload line plus `run/main_scene` in `project.godot`, `scripts/ui/settings_menu.gd` (new), `scripts/ui/lab_hud.gd`, `scripts/story/ending.gd`, `scripts/player/player.gd`, `scripts/audio/sfx.gd`, `tests/story_test.gd` (the ending checks) |
| Font and props (Sonnet) | `scripts/ui/pixel_font.gd`, `assets/ui/fonts/Silkscreen-*.ttf` + its license as `OFL-Silkscreen.txt`, `scripts/world/props.gd`, `scripts/world/prop_catalog.gd`, `assets/vox/props/{fake_plant,rubber_duck,sleeping_bag}.vox` |

Not to be touched by anyone in this work (another session's uncommitted editor work lives there):
`scripts/editor/*`, `scripts/input_setup.gd`, `scripts/level/level_edits.gd`,
`scripts/net/world_sync.gd`, `tests/editor_builder_test.gd`. `README.md` and `docs/story.md` are
updated once at the end.

### Contracts between the owners

`Net` (session owner), in addition to what exists:

```gdscript
const MENU_SCENE := "res://scenes/cubicle.tscn"
## Host: opens a session (server, roster) without loading the level; the host stays in the cubicle.
func open_session(port := DEFAULT_PORT, level := "waiting_room", mode := "play") -> Error
## Host: closes a session opened with open_session (peers get session_ended); no scene change.
func close_session() -> void
## Whether the host has loaded the level (peers may enter).
var level_open := false
signal level_opened
## Host: loads the level scene and announces it. Peer: loads the level scene now if level_open,
## else as soon as level_opened fires.
func enter_level() -> void
## The payroll statement to roll in the cubicle after a shift; [] when none.
var pending_statement: Array = []
var pending_total := 0
```

`join()` is unchanged. For a session opened with `open_session`, `_accepted` sets `in_session` and
emits `session_started` without changing scene (the session dict carries `staged = true` and
`level_open`). `host()`, `start_solo()` and the launch flags keep loading the level at once.

`GameSettings.get_value(key)`, `set_value(key, value)`, `signal changed(key)`, `apply_all()`, with
the keys in section 6. `SettingsMenu.create(scale)`, `handle_key(event) -> bool`, `signal closed`.

The three prop names and sizes in section 1.

## 8. Checks

- `tests/cubicle_test.gd` (headless): builds the cubicle into a scratch folder; the player spawns
  standing in air beside the chair; walking into the opening freezes, says the first line and sets
  the player back inside; the second attempt says the second line; E on the computer zooms and
  shows SPLASH; SHIFT with no name shows SIGN IN; typing a name and Enter reaches MAIN; the
  intro_test's log checks (SHIFT while thinking, the email after line 4, Decline to death and the
  go-back prompt, Yes back to the email, Accept finishes, F9 finishes) on the LOG page; the duck
  opens MAINTENANCE; Esc from SPLASH zooms out; the sleeping bag shows the clock-out prompt; a
  pending statement rolls and clears.
- `tests/story_test.gd`: the ending sets `Net.pending_statement` and fades instead of rolling a
  panel.
- `tools/net_test.sh` still passes (the flag-driven host and join paths are untouched).
- `tests/cubicle_shots.gd` (windowed): screenshots of the seated view, the hallway from the opening,
  SPLASH, MAIN, HOST, SETTINGS and the statement, for a visual check.

Run with `"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/<name>.gd`.
