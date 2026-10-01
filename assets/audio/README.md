# Audio

Placeholder sound effects and a placeholder music loop, all synthesized by
`tools/make_sfx.py` (Python 3 standard library only), played through the
`Sfx` autoload (`src/audio/sfx.gd`). Nothing here was recorded or
downloaded, so there is no licence to track; every file can be rebuilt or
retuned from source.

```
python3 tools/make_sfx.py                     # rebuild every sound, print the check table
python3 tools/make_sfx.py --only chips fold   # just these
python3 tools/make_sfx.py --music             # also the lounge loop
python3 tools/make_sfx.py --check --preview /tmp/sfx_png   # measure, and draw each sound
godot --headless --path . --import            # after adding or renaming a file
```

Rebuilding is byte-identical (each sound seeds its own random generator from
its name), so a regenerated file only shows up in `git status` if its
recipe changed.

**None of these have been listened to.** They were written in a sandbox
with no audio device and checked by numbers and pictures instead (below).
The first job for a person with ears is a pass over all of them: some will
be wrong in ways no measurement shows.

## Using it

Register the autoload (project.godot, `[autoload]` section):

```
Sfx="*res://src/audio/sfx.gd"
```

Then, anywhere:

```gdscript
Sfx.play(&"chips")                    # small random pitch/volume change every time
Sfx.play(&"chips", -4.0)              # quieter for this call (dB)
Sfx.voice(animal.species)             # the species' blip; silent for a species without one
Sfx.voice(animal.species, 0.0, 0.94)  # a bigger, lower individual
Sfx.master_volume = 0.6               # linear 0..1, for a settings slider; applies live
```

`play()` returns the AudioStreamPlayer, or null when nothing played: under
the Dummy audio driver (headless, tests, CI, no sound device), when muted,
for an unknown name (warned once in the log), or when the same sound was
already started in the last 35 ms. Callers never need to check.

If the project adds an audio bus named `SFX`, the player uses it; otherwise
it plays on `Master`. Music should get its own `Music` bus so the two can
be balanced separately.

## The sounds

All 16-bit mono 44.1 kHz WAVs in `sfx/`. Takes: sounds that repeat back to
back have several renderings (`chips`, `chips_2`, `chips_3`); `Sfx` picks one
at random, never the same twice in a row. "Pitch" is the random detune per
play, in semitones either way (0 for anything tuned, so it stays in tune
with the music).

| Name | Takes | Length | Peak | Pitch | What it is | For |
| --- | --- | --- | --- | --- | --- | --- |
| `card_deal` | 3 | 0.14s | -6 dB | 1.5 | Soft flick of a card across felt, faint landing | Each hole card dealt |
| `card_flip` | 1 | 0.16s | -6 dB | 1.0 | Snap of a card turned face up | Each board card, showdown reveals |
| `chips` | 3 | 0.25-0.32s | -4 dB | 1.5 | Two to four clay chips onto a stack | Calls, raises, blinds |
| `chips_pot` | 1 | 0.85s | -3 dB | 0.5 | A stack's worth of clinks over a felt slide | Pot pushed to the winner |
| `check` | 1 | 0.30s | -4 dB | 1.0 | Two knuckle knocks on felt | Checks |
| `fold` | 1 | 0.34s | -5 dB | 1.0 | Airy toss, papery slap | Folds |
| `all_in` | 1 | 0.95s | -2 dB | 0 | Rising major arpeggio over a swelling shimmer | Anyone goes all-in |
| `win_pot` | 1 | 0.95s | -1.5 dB | 0 | Cheerful C-major bell chime | Your crew wins a pot / the match |
| `lose` | 1 | 0.90s | -5 dB | 0 | Three soft falling notes, "aw shucks" | Your crew loses the match (sparingly: not every lost pot) |
| `your_turn` | 1 | 0.55s | -5 dB | 0 | Gentle two-note ping | Action is on you |
| `signal` | 2 | 0.20s | -10 dB | 2.0 | A tiny rustle of fur | A signal from your side |
| `dealer_warning` | 1 | 0.90s | -3 dB | 0.3 | The dealer's desk bell, one ding | Heat warning (40) |
| `fine` | 1 | 0.85s | -3 dB | 0.3 | Cash register "ka-ching" with coins | Heat fine (70) |
| `ejection` | 1 | 0.90s | -4 dB | 0.3 | Referee whistle, short-long | Heat ejection (100) |
| `ui_move` | 1 | 0.035s | -12 dB | 0.5 | Cursor tick | Focus moves between buttons/menu items, raise size up/down |
| `ui_confirm` | 1 | 0.17s | -9 dB | 0 | Two blips up | Menu confirm, "next hand" |
| `ui_back` | 1 | 0.17s | -10 dB | 0 | Two softer blips down | Menu cancel/back |
| `step_grass` | 3 | 0.12s | -9 dB | 2.0 | Crunchy little crackle | Overworld footstep on grass/dirt |
| `step_wood` | 3 | 0.14s | -9 dB | 1.5 | Hollow floorboard knock | Overworld footstep indoors |
| `encounter` | 1 | 0.85s | -3 dB | 0 | Pop + fast rising arpeggio + held stab | A rival spots you ("!") |
| `voice_owl` | 1 | 0.62s | -9 dB | 1.0 | "Hoo-hooo" | Owl speaks / acts |
| `voice_goose` | 1 | 0.42s | -5 dB | 1.5 | Two nasal honks | Goose |
| `voice_cat` | 1 | 0.30s | -5 dB | 1.5 | Rolled, rising "mrrp?" | Cat |
| `voice_raccoon` | 1 | 0.48s | -5 dB | 1.5 | Quick uneven chitter of chirps | Raccoon |
| `voice_squirrel` | 1 | 0.56s | -4 dB | 1.5 | Fast "chk-chk-chk" chatter | Squirrel |
| `voice_possum` | 1 | 0.48s | -7 dB | 1.0 | Short soft hiss | Possum |

Plus `music/lounge_loop.wav`: 8 bars of swung lounge jazz at 92 bpm (a
ii-V-I-vi in F, twice: FM electric piano comping, walking bass, brushes and
ride), 20.9 s at 22.05 kHz mono, -3 dB peak. It loops sample-exactly (the
length is whole bars, tails wrap around to the start) and its `.import` sets
`edit/loop_mode=2` (forward), so an AudioStreamPlayer just plays it forever.
It's deliberately modest: background for a card room until a composer's
track replaces it. Play it on a `Music` bus around -10 dB under the effects.

## Where to trigger them

### The table (`src/ui/table_view.gd`)

Everything at the table already passes through a handful of functions, so
each hook is one line:

| Where | Sound |
| --- | --- |
| `_next_hand()`, after `match_.start_hand()` | `card_deal` once per hole card, staggered ~0.07s (e.g. a loop of `get_tree().create_timer(0.07 * i)`), or just two or three for the whole deal |
| `_next_hand()`, the match-over branch | `win_pot` if `w == 0` and you weren't thrown out, else `lose` |
| `_start_human_turn()` | `your_turn` |
| `_on_action(seat, action, amount)` | `fold` for `Action.FOLD`, `check` for `Action.CHECK`, `chips` for `CALL`/`RAISE`; `all_in` instead when `s.all_in` |
| `_on_action`, for a bot's seat | `Sfx.voice(setup[seat]["animal"].species)` on raises and all-ins (not every action: it gets chatty), maybe with a per-individual pitch (`0.94` to `1.06`) |
| `_on_street(street, board)` | `card_flip` for each new board card (three for the flop, staggered ~0.12s) |
| `_on_hand_finished(result)` | `card_flip` if `not result["uncontested"]` (the reveal), ~0.3s later `chips_pot`, and with it `win_pot` if any seat in `result["payouts"]` is on your crew (staggered so they don't land as one blob) |
| `_show_new_signals()`, for each bubble shown | `signal` (only your side's; the rival crew's stay silent like their bubbles) |
| `_new_match()`: the `heat.warned` handler | `dealer_warning` |
| `_new_match()`: the `heat.fined` handler | `fine` |
| `_new_match()`: the `heat.ejection_called` handler | `ejection` |
| `_make_button()` | connect `b.focus_entered` to `Sfx.play(&"ui_move")`; `_human_act()` needs nothing more (the action's own sound plays) |
| `_unhandled_input()`: `raise_more` / `raise_less` | `ui_move` |
| `_unhandled_input()`: `ui_accept` while `_waiting_for_next` | `ui_confirm` |

In a card room, start `music/lounge_loop.wav` when the table scene enters
the tree and fade it out when `finished` is emitted.

### The overworld (`src/world/`, not written yet when this was)

By event, whatever the functions end up called:

| Event | Sound |
| --- | --- |
| The player finishes a step onto a tile | `step_grass` or `step_wood` by the tile's terrain (a custom data layer on the TileSet, e.g. `"footstep": "wood"`); every step, the pitch/take variation keeps it from droning |
| A rival's line of sight catches the player (before they walk over) | `encounter`, at the moment the "!" appears |
| Talking to an animal, each new dialogue page | `Sfx.voice(animal.species)` (a blip per page reads as speech, EarthBound/Animal Crossing style) |
| Menu cursor moves / confirm / cancel | `ui_move` / `ui_confirm` / `ui_back` |
| Recruiting an animal | `win_pot` until there's a proper jingle |
| Entering a card room | start `music/lounge_loop.wav` |

## How these were checked (without hearing them)

`tools/make_sfx.py` prints, for every file: duration (all under 1 s),
peak (each at its target, nothing at full scale, no clipped samples), RMS,
DC offset (largest |mean| 0.0019, from the low thumps' single decaying
lobe, not an offset), the first quarter millisecond and the last 2 ms
(all under 0.01 of full scale: no clicks at the edges) and the spectral
centroid of the loudest 46 ms (chips and footsteps on grass sit at 4-10
kHz, knocks and the lose phrase at 0.4-1.6 kHz, as intended). For the loop
it checks the seam: the jump from the last sample to the first (0.008) is
smaller than 99% of ordinary sample-to-sample steps inside it (0.055).

`--preview DIR` draws each sound as a waveform over a log-frequency
spectrogram (50 Hz-16 kHz, -80..0 dB; faint lines at 1, 4 and 10 kHz and
every 100 ms), plus `_sheet.png` with all of them stacked at the same time
scale. Looking at them is what caught the first `all_in` still ringing at
-6 dB when the buffer ended (it now fades over its last quarter second),
the pot's felt slide drowning its chips and the grass steps' thump drowning
their crunch (both turned down), and
confirmed the chime is clean harmonic partials, the chips are short bright
transients, the goose a harmonic stack with formant bands and the whistle a
single line in breath noise. The voices were first all normalized to about
the same peak and measured 16 dB apart in RMS (the owl's sustained hoot
against the squirrel's sparse clicks), so their peaks were spread to bring
them within ~8 dB of each other.

`tests/test_sfx.gd` checks that every name in `Sfx.SOUNDS` has all its
takes, that each loads in Godot as a mono 44.1 kHz WAV under a second long,
that no file on disk is missing from the list, that every species in
`Species` has a voice, and the player's behaviour (pool reuse, pitch and
take variation, the repeat gap, the no-op paths, master volume) without an
audio device.

## Replacing them

Each sound is just a file name. To use a real recording, a sound library
or a composer's work:

1. Drop the file in `sfx/` with the same name (`chips.wav`; add `chips_2.wav`,
   `chips_3.wav`... for extra takes and set the count in `Sfx.SOUNDS`).
   Godot also imports `.ogg`, but `Sfx.paths()` looks for `.wav`: change the
   extension there if the whole set moves to Ogg Vorbis (smaller; fine for
   anything but very short, frequently retriggered sounds).
2. Delete that sound's entry from `SOUNDS` in `tools/make_sfx.py`, so a
   rebuild can't overwrite it.
3. Real recordings go through **Git LFS** like the rest of the project's
   source audio: remove or narrow the `assets/audio/sfx/*.wav` exception in
   `.gitattributes`, and add `lfs: true` to the checkout step in
   `.github/workflows/tests.yml`, or CI will load LFS pointer files. (The
   placeholders skip LFS because they're 2.2 MB together, rebuilt from
   source, and CI didn't fetch LFS objects.)
4. `godot --headless --path . --import`, then run the tests: they fail if a
   listed sound is missing or a file isn't listed.
5. Keep the levels roughly where the placeholders are (the Peak column),
   or adjust the third number in `Sfx.SOUNDS` (a dB offset per sound)
   rather than re-exporting.

For music, replace `music/lounge_loop.wav` and set its loop points in the
import dock (or `edit/loop_begin`/`edit/loop_end` in the `.import`, in
samples). A composer delivering Ogg loops would set `loop` and `loop_offset`
on the AudioStreamOggVorbis import instead.
