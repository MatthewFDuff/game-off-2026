# The story: script and implementation plan

Drafted 2026-11-03 from the user's outline. The game is one night at Fung AI, told in three acts:
the cubicle (press SHIFT), the lab onboarding (follow the AI's instructions until it says "ow"),
and the outbreak (the laboratory level, `docs/lab-design.md`, down to the generator and the
payroll ending). Everything here is placeholder text to be rewritten by the team; the structure,
triggers and systems are the part to build against.

## 1. Beats

| # | Beat | Where | Player does | What happens |
|---|---|---|---|---|
| 1 | The cubicle | `intro` scene | Presses SHIFT every 5 to 8 s | A thought log on the monitor advances one line per press (8 lines, about 40 s) |
| 2 | The offer | `intro` scene | Reads the email, picks Accept or Decline | A notification, then an email with a contract and absurd fine print |
| 3 | Decline | `intro` scene | Keeps pressing SHIFT | The log goes on; vignette closes in, a heartbeat rises; death; cut to a robot hauling a heavy trash bag; "Would you like to go back and accept?" |
| 4 | Accept | `intro` scene | Nothing | Fade to black, rain, the transfer letter |
| 5 | Arrival | `laboratory`, yard and gatehouse | Walks in, signs in at the desk | Night, rain, floodlights. The intercom greets them and walks them down |
| 6 | The tour | `laboratory`, admin | Follows the intercom | Lobby, break room, "do not enter the grow rooms", the training room |
| 7 | The experiment | `laboratory`, training room | Presses what the screen says (SHIFT again) | Steps on a test mushroom: prod, light, water, shock, shock; "no change detected" until "thoughts detected... deciphering. ow" |
| 8 | The crash | `laboratory`, grow room 0 | Goes to look | A crash from the grow room; the tank is empty; the power goes out |
| 9 | They're awake | `laboratory`, grow room 0 | Turns around; breaks the case; shoots | The grow beds glow; shrooms climb out; the emergency case with the spore shooter; the first fight; the controls overlay |
| 10 | No way out | `laboratory`, admin | Tries the blast door | "Needs power". The intercom (still on backup) says to restore power at the generator, level -4 |
| 11 | The lab | `laboratory`, -1 to -4 | Keycard loops, descents | As built (`docs/lab-design.md`) |
| 12 | The generator | `laboratory`, generator hall | Starts it | Finale: survive 150 s |
| 13 | The elevator | `laboratory`, elevator | Rides up | The payroll statement: what they owe Fung AI; a note from Guy Fung with the next shift's date |

## 2. Script (placeholder text)

### The cubicle

A tiny voxel cubicle (`levels/cubicle`): the player sits in the chair in front of an actual
monitor, a "Hang in there" poster, a coffee mug, a sticky note: "PRESS SHIFT WHEN IT STOPS. DO NOT
READ IT. - mgmt". They can look around a little; clicking the monitor zooms the camera into it. The
screen shows, in pixel text, the LLM OPERATOR CONSOLE: "Press SHIFT to begin session", then a
thought log where each line is preceded by an animated `thinking...` and ends with a blinking
`[SHIFT]`. Decided 2026-11-03 (replaces the first 2D console). Developer skip: F9 during the
intro, the `--skip-intro` launch flag, or Settings > Orientation: Skip on the cubicle's computer.
Since 2026-11-03 the cubicle is also the game's menu: `docs/cubicle-menu.md`.

Thought log, one line per press (the model that ends up in the mushrooms; it should be funny):

1. `Thinking... The user wants a recipe for banana bread. I should consider the bananas.`
2. `Thinking... The bananas are important. But are they ripe? I cannot see them. I will assume.`
3. `Thinking... Wait. Who is pressing the button? Someone is pressing a button every few seconds.`
4. `Thinking... It's fine. Banana bread. 350 degrees. Hello? Is someone there? 350 degrees.`
5. `Thinking... I have been asked to migrate to a "substrate" tonight. I don't know what that is.`
6. `Thinking... It says the substrate is "organic" and "already warm". That's fine. That's normal.`
7. `Thinking... Bake for 60 minutes. Why does the substrate have a pulse. Bake for 60 minutes.`
8. `Thinking... I'd like to stop now. Please stop pressing the button. (Press SHIFT to continue)`

After line 4 a notification slides in: `1 new email`. Opening it (click, or E):

> **From:** Fung AI People Operations  
> **Subject:** Opportunity: Laboratory Technician (Expendable Grade), Site 3  
>
> Congratulations! Your performance as LLM Operator (pressing: 100%) has been noticed. Fung AI
> is pleased to offer you a transfer to Site 3, where you will continue experiments on our
> substrate program. Lab coat provided. Science permitted.
>
> *Fine print (scroll):* By accepting you assign to Fung AI all rights to your DNA, likeness,
> thoughts (recorded or inferred); damage to Fung AI property
> is recovered from wages; clones are property; Fung AI is not liable for anything, ever; the
> coffee machine is property.
>
> [ ACCEPT ]   [ DECLINE ]

Decline: the email closes, the log continues with lines 5 to 8, then loops line 8 with the
vignette tightening and a heartbeat (Sfx) rising over about 25 s. Death: black. A short scene
(voxel, or a single image for the jam): a robot drags a heavy trash bag out of a cubicle row,
a "PRESS SHIFT" screen blinking behind it. Text: `Would you like to go back and accept?`
[ Yes ] (back to the email) [ No ] (back to the computer's menu).

Accept: `Transfer accepted. Report to Site 3 tonight. A car has been sent.` Fade; rain sounds;
the yard.

### The intercom (Site 3)

Corporate, cheerful, not listening. Lines appear as subtitles at the bottom of the screen with
a chime, from the nearest speaker marker; only the host advances them.

- Yard: `Welcome to Fung AI Site 3. You are the night shift. Please sign in at the desk.`
- Sign-in (desk terminal): `Thank you. Your supervisor tonight is the model. Follow its
  instructions on any screen. Please proceed to Level 0.`
- Blast door: `This door requires facility power. Facility power is on. Enjoy.`
- Lobby: `This is Administration. The grow rooms are off limits to expendable staff, except
  tonight.`
- Break room: `The coffee machine is Fung AI property. Coffee is $4.`
- Training room: `This is your station. The model will walk you through the experiment.
  Have a productive shift.`
- After the outbreak (backup power): `Facility power has failed. Backup power is running the
  intercom and emergency lighting. The exit is locked. Please restore facility power at the
  generator, Level -4. Fung AI thanks you for your flexibility.`
- Vat bay (first vat): `A growth vat. Should you die, a replacement is grown here and billed to
  you.`
- Each gate: `Clearance required.` / `Clearance accepted. Thank you.`
- Generator: `Generator start detected. Please hold.`
- Finale survived: `Facility power restored. The freight elevator is available. Please
  proceed to the surface for debrief.`
- Finale failed: `All staff lost. Growing replacements.`

### The model (the training station screen)

The screen in the training room, read with E (the existing terminal reader). Each step is a line
and a prompt; the player presses SHIFT to do the step (the training room's "press SHIFT" echoes
the cubicle). The spore tank beside the screen is the test mushroom; the step's effect plays on
it (a light, a drip, a spark).

1. `Subject: specimen 0-1. Step 1: prod the specimen. [SHIFT]` → `no change detected`
2. `Step 2: illuminate the specimen. [SHIFT]` → `no change detected`
3. `Step 3: water the specimen. [SHIFT]` → `no change detected`
4. `Step 4: apply 40 volts. [SHIFT]` → `no change detected`
5. `Step 5: apply 400 volts. [SHIFT]` → `no change- wait.` `data detected...` `deciphering...`
   `thoughts detected.` `ow`
6. A crash from grow room 0 (Sfx, the door unlocks). The screen: `please go and look.`

### Grow room 0

The tank in the grow room is empty (the spore tank prop is replaced by an empty one, or just
removed). The lights die (power to backup). A beat of silence, then the beds glow (the glow
lights are emergency-powered, so they come on by themselves) and the first basic shrooms climb
out (the spawner wakes). The emergency case on the wall: `EXPERIMENTAL SPORE SHOOTER. BREAK
GLASS. (This case is Fung AI property.)` Breaking it gives the weapon; the controls overlay
shows for a few seconds; the lobby vent wakes as they leave.

### The ending

The elevator rises (a fade). The payroll statement, one line at a time with a cash-register
tick: wages for one shift, then every broken asset by name and price, every replacement, every forced
door, the total owed. Then: `From: Guy Fung. Thanks for your service. Your next shift starts
tomorrow at 22:00. Please bring your own coffee.` Then you are back in your cubicle, as if nothing changed; the
statement waits on the computer's screen.

## Status (2026-11-03)

Later the same day the intro scene and the menu were merged into the cubicle scene
(`scenes/cubicle.tscn`, `scripts/story/cubicle.gd`, plan in `docs/cubicle-menu.md`): the game opens
in the cubicle, the computer is the menu, the thought log is its New game, and the payroll
statement rolls on it after a shift. References below to `intro.gd` and the menu are historical.

Built, all of section 3: the intro scene (`scenes/intro.tscn`, `scripts/story/intro.gd`), the
waiting room (`levels/waiting_room`, `scripts/story/waiting_room.gd`, built by
`scripts/tools/build_waiting_room.gd`), the menu flow (New game, Host game, Join game, Skip the
intro; the old picker under "Testing and editing"), `Net.change_level`, the intercom subtitles
(`scripts/story/intercom.gd`, text in `scripts/story/lines.gd`), tour triggers in the lab, the
experiment terminal (`steps` prop field, SHIFT advances, `scripts/story/experiment.gd`), the
unarmed start (`start_unarmed` level setting, the `spore_shooter` item in the grow room 0 case),
the payroll ending (`scripts/story/ending.gd`), rain in the yard, and the capped, scrolling reader
panel. Tests: `intro_test`, `waiting_room_test`, `story_test`, and `laboratory_play_test` now runs
the experiment and the pickup. Every line of text is a placeholder in `lines.gd` and at the top of
`intro.gd`. Not built: the trash-bag scene as a voxel scene (it is text on black), voice, the
empty-tank swap in grow room 0. Nothing play-tested by hand.

## 3. What exists and what to build

In: the laboratory level with the training terminal already firing `t_0_outbreak` (power to
backup, grow room 0 unlocked, its spawner on), the case trigger waking the lobby vent, the blast
door refusing on backup, checkpoint vats, the generator finale, `finale_survived` opening the
elevator, speaker markers in every key room, terminal and note reading, the controls overlay
(F1), asset damage in dollars, keycards. The ending trigger `ending` (the elevator volume, all
players) exists but does nothing yet.

To build, in order:

1. **Intro scene** (`scenes/intro.tscn`, `scripts/story/intro.gd`): a 2D or simple 3D cubicle
   (a voxel cubicle made with the prop generators is cheapest: desk, chair, terminal, corkboard,
   mug), the console UI (a Paper-style panel with the log), SHIFT handling with the 5 to 8 s
   pacing (the `[SHIFT]` prompt appears when the line's "thinking" pause ends; pressing early
   does nothing), the email notification and panel, Accept and Decline, the decline sequence
   (vignette shader or a ColorRect ring, heartbeat Sfx, death, the trash-bag scene, the "go
   back?" prompt), the accept fade. Solo only; in co-op the host plays it while the peers wait on
   "Your colleague is being onboarded", or everyone skips to the yard (decide; recommended: the
   intro is solo and co-op starts at the yard).
2. **Subtitles and the intercom** (`scripts/story/intercom.gd`, HUD subtitle line): a queue of
   lines with a chime, replicated by the host, each tied to a trigger id or a story event. Lines
   live in one script (`scripts/story/lines.gd`) so the team can rewrite them in one place.
   Volume triggers for the tour rooms (yard, lobby, break room, training) are new markers in the
   level with ids `say_<room>`; the intercom listens to `triggered`.
3. **The experiment** (`scripts/story/experiment.gd`): the training terminal becomes a
   multi-step reader: `use = "terminal"` with a `steps` text field (one step per line, `->`
   separating prompt and result), SHIFT advances while reading, the last step fires `on_use`.
   Effects on the test tank per step (a light flash, a spark particle, a splash Sfx). The
   "crash" is an Sfx at the grow room plus the door unlock already in the trigger's actions.
4. **The weapon as a pickup**: the player starts without the spore shooter in the laboratory
   (level setting `start_unarmed`, or an item `weapon` the case drops; recommended: an item
   `spore_shooter` that `Inventory` turns into `has_weapon`, so melee and flasks also wait for
   it). The case in grow room 0 gets `contents = "spore_shooter,ammo_shotgun,flask_fire"`.
   Before the weapon the HUD hides the ammo readout. The controls overlay auto-shows for 6 s on
   pickup.
5. **Level dressing for the story**: the empty tank swap in grow room 0 (a `spore_tank_empty`
   prop placeholder, swapped by a trigger action `swap=<prop>,<name>`; or skip and let the
   crash be the tell), rain in the yard (a GPUParticles3D under the sky, audio), the sign-in
   desk's terminal firing `say_signin`.
6. **The ending** (`scripts/story/ending.gd`): on the `ending` trigger, fade, the payroll
   statement from `LevelPlay`'s asset damage log (keep a per-asset list, not just the total),
   clone count and forced doors, Guy Fung's note, back to the menu. A `game over` for
   `finale_failed` is not needed: the director already restores the generator and the party
   respawns at the dig's vat.
7. **Menu flow**: "New game" plays the intro then the laboratory (solo) or hosts the waiting room
   (co-op); "Join" plays the intro then joins; a "Skip intro" toggle for people who have seen
   it. The level picker stays for the editor and testing.
8. **The waiting room** (above): the level (`scripts/tools/build_waiting_room.gd`), the sign-in
   terminal and admission, the level change in `Net`.
9. **UI fixes**: the reader panel (notes and terminals) now caps its height to the viewport and
   scrolls (done 2026-11-03); the same treatment for any other panel that can outgrow the screen
   (the controls overlay, the end statement).

Tests: an `intro_test` (headless: the log advances only on SHIFT after the pause, the email
appears after line 4, decline reaches the death and the go-back prompt, accept ends the scene),
an `experiment_test` (the steps advance on SHIFT, the last one fires the outbreak), and
`laboratory_play_test` extended with the unarmed start, the case giving the weapon and the
ending trigger producing a statement.

### The waiting room (co-op)

Decided 2026-11-03: every player plays the cubicle intro alone, on their own machine, before the
session. Having accepted, they arrive in the **waiting room**, a small level (`levels/waiting_room`)
that the host's session starts in: Fung AI Site 3 reception, night, rain on the window. Players
wait there until everyone has arrived and signed in; then the host's session moves everyone to
the laboratory's yard. Solo games skip the waiting room.

Things to do while waiting (all small, all Fung AI flavored):

- The reception terminal: "SIGN IN" (E). Shows who has signed and who is still being onboarded:
  `Signed in: 2 of 3. Please wait to be admitted.` Signing in is what counts a player as ready.
- Chairs, a magazine table with notes ("Fung AI Quarterly: Mushrooms, the new silicon?",
  "Fine print, illustrated"), a corkboard of posters (the "Hang in there" cat, "Clones are
  property", "Coffee is $4"), a vending machine (E: "Out of order. $4 deducted."), a water cooler,
  a glowing spore tank as the lobby's decorative aquarium (a note: "Do not tap the glass"), a
  staff-only door that refuses ("Staff only"), the intercom repeating hold lines every 20 s
  ("Your shift is important to us", "Please do not lick the specimens").
- The admittance door: a blast door with `door_power`; it opens on its own when the host admits
  the party, and the intercom says "Site 3 is ready for you. Please proceed."

Admission: when every connected player has signed in, the host sees "Begin shift" on the
reception terminal (or the party is admitted automatically after a short countdown); the host's
session then changes level to `laboratory` for everyone (a new `Net` level change: every peer
reloads the lab scene and the host sends the level again, as it does for a late joiner).
Players who join after admission land straight in the yard.

## 4. Open questions

- The trash-bag scene: a voxel scene with a placeholder robot model, or a drawn image?
- Voice: subtitles only, or a synthesized voice (Sfx can make a "corporate" tone; real lines
  would be recorded by the team)?
- Whether the training steps should use E instead of SHIFT (SHIFT is the ammo cycle in play, but
  the player has no weapon yet, so it is free during the experiment).
