# Controls

Reviewed and decided 2026-11-04. Every input the game reads, in three groups (game, UI, and the
rest), then the gamepad scheme and how it is wired in. The level editor keeps its own keyboard and
mouse shortcuts (`InputSetup.EDITOR_KEYS`, `docs/level-editor.md`) and has no gamepad support: it
is a mouse tool for the team, not part of the shipped game's controls.

Everything keyboard and mouse is registered by `scripts/input_setup.gd` at startup; `project.godot`
has no input map of its own, so Godot's built-in `ui_*` actions keep their defaults except where
section 4 says otherwise.

## 1. Game controls

Read while the game has play focus (`InputSetup.is_playing()`: the mouse is captured, or the game
is being played on a pad, section 4.1). The player (`scripts/player/player.gd`) polls movement
each physics tick; the weapon (`scripts/weapons/weapon.gd`) polls its buttons each frame.

| Action | Keyboard / mouse | Gamepad | Read by |
|---|---|---|---|
| `move_forward` / `move_back` / `move_left` / `move_right` | W / S / A / D | Left stick | `Player._walk`, `Player._fly` (`Input.get_vector`) |
| Look (`look_left` / `look_right` / `look_up` / `look_down`) | Mouse; arrow keys | Right stick | `Player._unhandled_input` (mouse), `Player._process` (actions) |
| `jump` | Space | A | `Player._walk` (also up while flying) |
| `crouch` (held) | Ctrl, C | B | `Player._walk` (also down while flying) |
| `fire` (held) | LMB | RT | `Weapon._process` |
| `alt_fire` (throw flask) | RMB | LT | `Weapon._process` |
| `melee` | MMB | RB | `Weapon._process` |
| `cycle_flask` | Q | LB | `Weapon._process` |
| `cycle_ammo` ("SHIFT") | Shift | Y | `Weapon._process`; also the next experiment step on a terminal (`InteractPrompt`) |
| `ammo_1` .. `ammo_4` | 1 .. 4 | D-pad up / right / down / left | `Weapon._process` |
| `interact` | E | X | `Player.interacted` (lab props, doors, notes, terminals), `Cubicle._room_input`, `WaitingRoom` (begin shift) |
| `toggle_flashlight` | T | L3 (left stick click) | `Player._unhandled_input` |
| `show_controls` | F1 | Back / Select | `ControlsOverlay` (toggle) |
| `ui_cancel` (pause / step away) | Esc | Start | `Player._input` releases play focus; `LabHud` then shows the pause panel; the cubicle opens the clock-out prompt |
| Capture the mouse / resume | Any mouse button | Start (lab), any button (cubicle) | `Player._unhandled_input`, `LabHud`, `Cubicle` |
| `toggle_fly` (dev only, `--dev`) | F | none | `Player._unhandled_input` |
| Fly fast (dev only) | Shift (raw key) | none | `Player._fly` |

Notes:

- Crouch is held, not toggled, on both devices.
- The right stick has a squared response (small deflections aim finely) and its own
  **Stick sensitivity** setting (section 3); the arrow keys follow the same speed
  (`Player.pad_look_speed`, 2.5 rad/s, which replaces the old `key_look_speed` of 2.2).
- Nothing is bound to R3. The dev keys (fly, fly fast) have no pad binding.

## 2. UI controls

Every menu in the game is keyboard-driven with raw keys (`match event.keycode`), not actions, so
the pad reaches them through a translation layer (section 4.2) that turns pad presses into the
keys below.

### 2.1 The cubicle's console (`Cubicle.handle_key`)

| Key | Gamepad | Does |
|---|---|---|
| Up / Down | D-pad / left stick up, down | Move the caret (`move_cursor`) |
| Left / Right | D-pad / left stick left, right | Step a choice (`step_choice`: size, start, orientation...) |
| Enter | A | Choose the line, submit a field (`press_enter`) |
| Shift | Y | SHIFT: sign in, select, advance the log (`press_shift`); in a field on a pad, step the caret to the next line (4.3) |
| Esc | B, Start | Back one page; from the top page, step away (`back`) |
| Backspace | X | Erase in a field; elsewhere, back |
| Typed characters | Arcade entry (section 4.3) | Fill a field (`type_text`) |

Pages with a field: SIGN IN (name), JOIN (address), NEW LEVEL (name). The SETTINGS page is the
shared `SettingsMenu` (2.4).

### 2.2 The orientation log and the email (`Cubicle._log_key`)

| Key | Gamepad | Does |
|---|---|---|
| Shift | Y | Next line of the log (`press_shift`) |
| Enter, E | A | Open the email once it has arrived (`open_email`) |
| A, Enter | A (email open) | Accept the transfer |
| D | X (email open) | Decline it |
| Esc | B | Abort orientation (log and dying, email closed) |
| Y, Enter / N, Esc | A / B | At "Would you like to go back and accept?": yes / no |
| F9 | none | Accept at once (dev) |
| LMB | none | Open the email; the ACCEPT / DECLINE buttons |

### 2.3 Clock-out prompt, notes, reader

| Where | Key | Gamepad | Does |
|---|---|---|---|
| Clock out (cubicle) | Y, Enter | A | Clock out |
| Clock out (cubicle) | N, Esc, Backspace | B | Stay |
| Reading a note (cubicle) | E, Esc, Backspace | X, B | Close it |
| Reader panel (lab, `InteractPrompt`) | Up / Down, PgUp / PgDn, wheel | D-pad / right stick up, down (not the left stick: it walks away) | Scroll |
| Reader panel (lab) | E | X | Close it (the lab's interact) |
| Terminal step (lab) | Shift | Y | Run the next experiment step |

### 2.4 Settings (`SettingsMenu.handle_key`, on the console and the pause panel)

| Key | Gamepad | Does |
|---|---|---|
| Up / Down, W / S | D-pad / left stick up, down | Choose a row |
| Left / Right, A / D | D-pad / left stick left, right | Change the value |
| Enter, Space | A | Flip a two-state row; on the console's Name row, open the name field |
| Esc, Backspace | B | Close |

### 2.5 The pause panel (`LabHud`)

Godot `Button`s: Resume, Settings, Invite (a co-op host), Leave shift, and Back on the invite
page. Mouse clicks today; on a pad the first button takes focus when the panel opens, the stick
and D-pad move focus (`ui_up` / `ui_down`), A presses (`ui_accept`), B goes back a page, Start
resumes. The hint under the title says "Click to resume." or "Press Start to resume." by device.

### 2.6 Overlays

| Where | Key | Gamepad | Does |
|---|---|---|---|
| Controls sheet | F1 | Back / Select | Toggle |
| Controls sheet | Esc | B, Start | Close |
| Waiting room terminal | E | X | Sign in, begin the shift (host) |
| Ending statement | none | none | It fades and leaves on its own |

## 3. Other categories

- **Settings.** `GameSettings` keys that are controls: `mouse_sensitivity` (0.5 to 3.0) and,
  new, `stick_sensitivity` (the same range, 1.0 default; a **Stick sensitivity** row under Mouse
  sensitivity in both settings menus). No rebinding and no invert-Y yet.
- **Text entry.** Three console fields (name, address, level name) take typed characters. On a
  pad they use arcade entry (4.3). A keyboard still types into them whatever device is active.
- **Developer keys.** F (fly, with `--dev`), Shift while flying, F9 (accept the transfer at
  once), the `--solo` / `--host` / `--join=` / `--edit` launch flags. Keyboard only.
- **Level editor.** `EDITOR_KEYS` and the mouse, through `EditorInput`. Keyboard and mouse only;
  the pad does nothing in builder view and its play-test uses the game bindings.
- **Web build.** Pads work through the browser's Gamepad API. The browser only grants pointer
  lock on a click or key, never on a pad press, which is why play focus is not the same thing as
  mouse capture (4.1).

## 4. The gamepad scheme

Xbox names below; the bindings are by position (Godot's `JOY_BUTTON_A` is the bottom face button
on every pad), so a PlayStation or Switch pad gets the same layout.

```
                 LT  throw flask                    RT  fire (hold)
                 LB  cycle flask                    RB  melee

          D-pad  ammo 1 (up)  2 (right)             Y  SHIFT (ammo / sign in / next)
                 3 (down)  4 (left)                 X  interact / erase / decline
                                                    B  crouch (hold) / back
          Left stick  move  (L3: flashlight)        A  jump / select / accept
          Right stick look

                 Back  controls sheet               Start  pause / resume / step away
```

### 4.1 Play focus

`InputSetup.is_playing()` was "the mouse is captured". It is now "the mouse is captured, or
`InputSetup.playing_on_pad`", a static flag:

- `InputSetup.resume_play()` captures the mouse and, when the pad is the device in use
  (`Pad.active`), sets the flag (capture may fail on the web build with no gesture; the flag
  still makes the game live). A mouse or keyboard resume leaves the flag clear, so a browser
  dropping pointer lock on its own still pauses the game as before.
- `InputSetup.release_play()` clears the flag and shows the mouse. Everything that used to set
  `Input.mouse_mode` to pause or resume (the player's Esc, its focus-out notification, the pause
  panel's Resume, the cubicle's zoom-in, panels and `_capture_mouse`, the ending) goes through
  these two, so pad and mouse never disagree.
- A mouse click still captures (and so resumes) as before. Mouse motion still only looks around
  while captured.
- The Player's Esc / Start releases play only while playing, and does not mark the event handled
  (the cubicle's `_unhandled_input` still needs it to open the clock-out prompt). The pause panel
  acts on Start only when it was already showing before the event (`_pause.visible` is last
  frame's) and marks the Start it takes handled, which the Player checks first, so one Start never
  both pauses and resumes, in either order.
- Headless runs count as playing (`InputSetup.headless_plays`, true by default, so the existing
  tests are unchanged); `tests/gamepad_test.gd` sets it false to see the paused game.

Resuming on a pad: in the lab, Start (or Esc) on the pause panel (its buttons page) or A on
Resume; in the cubicle, any pad button while the room is the player's and nothing is open ("Click
or press A to look around" when a pad is connected).

### 4.2 Pad input into the menus: `Pad` (autoload, `scripts/pad.gd`)

A small autoload that knows which device the player is using and translates pad presses for the
keyboard-driven menus:

- `Pad.active`: true once the last input event was a pad button or a stick past its deadzone,
  false again on any key, mouse button or mouse movement (past a couple of pixels). `Pad.connected`:
  a pad is plugged in. Signal `device_changed`. It watches the root window's `window_input`
  signal rather than `_input`: that sees every event before any node handles it, paused or not.
  `Pad.is_pad(event)` (static): a pad button or axis event.
- `Pad.to_key(event) -> InputEventKey`: a pressed pad button or stick edge as the key the menus
  expect (both `keycode` and `physical_keycode` set, so `is_action_pressed("ui_cancel")` matches
  too), or null for anything else: A → Enter, B → Escape, Start → Escape, Y → Shift,
  X → Backspace, D-pad → arrows, left stick → arrows on crossing 0.5 (released under 0.3, so a
  held stick is one press; the same event asked twice gives the same answer). Every `handle_key` (console, settings, reader, clock-out, log) runs
  its event through this first, so one table serves them all. Menus that need a pad button that
  has no key meaning (X declines the email) check the pad actions directly.
- Pad actions, for those checks and for tests: `pad_accept` (A), `pad_back` (B), `pad_alt` (X),
  `pad_shift` (Y), `pad_start`, `pad_up` / `pad_down` / `pad_left` / `pad_right` (D-pad and left
  stick).
- `Pad.text(s)`: the prompts' key tokens by device: "[E]" → "[X]", "[SHIFT]" → "[Y]", so
  `Interactables` and the story keep writing "[E] Open" and the HUD shows the right one. Footers
  and hints choose their wording by `Pad.active` ("A: select  B: back" against
  "SHIFT: select  Esc: back").
- `Pad.glyph(action)`: the pad name of an action's binding ("X", "RT", "Start") for the controls
  sheet, which lists pad bindings next to the keys ("LMB / RT") when a pad is connected.

`ui_cancel` loses any joypad B (B is crouch in play) and gains Start. The `ui_*` directions keep
Godot's D-pad and left stick, which is what moves focus on the pause panel's buttons. Godot 4.6's
`ui_accept` has no pad button at all, so `InputSetup` adds A to it (that presses the focused
button). `InputSetup.pad_name(event)` names a pad event Xbox style; `InputSetup.shows_pad()` is
"a pad is connected or active", which the controls sheet uses.

### 4.3 Arcade text entry

In a console field with a pad, as a high-score table: D-pad / stick up and down turn the last
character through space, A to Z, 0 to 9, period, hyphen, colon (an empty field starts at A);
right appends a character (an A); left or X erases the last one; A submits; B backs out. The
caret block shows the character being turned (it sits on the last character, drawn dark on it).
Each field turns through only the characters it takes (`Cubicle._field_allows`, which typing
uses too): the name has no period, hyphen or colon, a level name has the hyphen, an address all
three. Y steps the caret off the field to the next line, since up and down are taken: NEW LEVEL's
size, start and CREATE, JOIN's recent addresses (up from the line under the field comes back to
it). A keyboard types as before at any time.

### 4.4 Tests

`tests/gamepad_test.gd` (headless): every play action has a pad event and the `ui_cancel` swap
happened; `Pad.to_key` on each button and on stick edges; a pushed left stick walks the player and
a pushed right stick turns them, with the play-focus flag and no mouse capture; the pause panel's
Start toggle and first-button focus; `Pad.text` and the controls sheet's pad names.
`tests/pad_console_test.gd` (headless) plays the cubicle by pad: A for play focus in the room, X
on the computer, Y to SIGN IN, arcade entry to MAIN, the caret, SETTINGS and B back out, the pad
and key wordings, the log (Y), the email (A opens, X declines, A at the go-back prompt, A
accepts, B declines there), Start's clock-out prompt and B, X and B closing a note. The existing `controls_test`, `cubicle_test`, `controller_test`,
`ui_test`, `story_test` and `weapon_test` keep passing.
