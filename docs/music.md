# Music

Two 8-bit loops, generated with Matthew's procedural music studio (`E:\AI\procgenmusic`, Imbrelle studio v0.6.0). Nothing is sampled; every sound is synthesized (pulse waves, a 4-bit triangle, LFSR noise drums), so the files are ours to ship.

| File | Use | Seed | Tempo / key | Length | Loudness |
|---|---|---|---|---|---|
| `assets/audio/music/noir_loop.ogg` | calm, broody: cubicle, menus, quiet exploration | `noir` · `shadow-512` · mood 0.2,0.2 | 72 BPM, C minor, swung | 106.7 s | −18.9 LUFS |
| `assets/audio/music/action_loop.ogg` | fast retro action: combat, chases | `action` · `siren-250` · mood 0.35,0.95 | 172 BPM, A minor | 55.8 s | −15.4 LUFS |

Both are seamless loops: the form has no intro or ending, and the reverb/delay tail of the last bar is folded onto the start. The `.import` files set **Loop** on.

## The player

`scripts/audio/music.gd` (class `Music`, autoload `MusicBox`) plays them and needs no cues: four times a second it looks at the current scene.

- **Cubicle** and a **lab in play**: the noir loop. It carries on across the scene change from the cubicle into the shift.
- **Combat**: the action loop while a living shroom (done emerging) within `DANGER_RANGE` (16 m) of the local player is a threat, or while the generator finale runs (`HordeDirector.finale_event`, which reaches every peer). A shroom in range is a threat when it stands on the player's floor (less than `SAME_FLOOR`, 2 m, above or below: stairs count, a storey is 3.3 m floor to floor) or when the player's camera has a line of sight to its body (`Combat.can_see_box`: through a hole, a window or over a mezzanine rail, not through a slab or a wall). One a floor up behind the slab is no threat until it shows. The noir comes back `CALM_SECONDS` (8 s) after the last threat, resuming where it left off; the action loop always starts from its top.
- **Edit mode**, the waiting room and anything else: silence.
- **Ending**: `Ending._show` calls `Music.hold()`, which fades out and stays silent until the next scene (the cubicle, where the statement rolls over the noir again) or `Music.release()` (a replay).

Changes crossfade (`FADE_IN` 1.5 s, `FADE_OUT` 2.5 s). The Music setting is applied by GameSettings through `Music.set_volume_db` on top of each loop's own level (`LEVELS`: the action loop renders hotter, so it sits 3 dB lower). Music keeps playing while the tree is paused. Test: `tests/music_test.gd`.

## Re-render or change them

From the procgenmusic folder:

```
node render/render-song.js --style noir --seed shadow-512 --mood 0.2,0.2 --name noir-loop --master 50
node render/render-song.js --style action --seed siren-250 --mood 0.35,0.95 --name action-loop --master 60
node dev/song-peek.js --style action --mood 0.35,0.95 --seeds a,b,c   # compare seeds without rendering
```

Outputs land in `renders/music/` as `.wav`, `.ogg` and a `.json` with the exact command. Copy the `.ogg` over the file here. A different seed gives a different tune in the same style; the mood pad (`v,e` = positivity, energy) changes mode, tempo and density. The styles themselves (`STYLE_NOIR`, `STYLE_ACTION` in `studio/index.html`) hold the tempo ranges, progressions, forms and track levels.
