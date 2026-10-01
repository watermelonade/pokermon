extends Node
## Plays the game's sound effects by name: `Sfx.play(&"chips")`.
##
## Meant to be an autoload named `Sfx` (in project.godot's [autoload]
## section: `Sfx="*res://src/audio/sfx.gd"`), so no class_name: a global
## class and an autoload can't share a name. The sounds, what each is for
## and where to trigger it are listed in assets/audio/README.md; the files
## come from tools/make_sfx.py.
##
## Why it's built this way:
##
## - A fixed pool of AudioStreamPlayers, made once, instead of a new player
##   per sound: chips, cards and voices overlap at the table, and creating
##   and freeing nodes every bet is churn for nothing. When all are busy the
##   one that started longest ago is reused (its sound is nearly over).
## - Every play nudges pitch and volume a little (per sound: footsteps and
##   rustles a lot, jingles not at all, since a detuned chime sounds wrong
##   next to music) and rotates between the recorded takes of sounds that
##   have several (name, name_2, name_3...), never the same take twice in a
##   row. Ten identical chip clinks in a hand is what makes placeholder
##   audio sound robotic.
## - The same sound asked for twice within `repeat_gap_msec` plays once: when
##   several things happen in one frame (three seats busting, a pot split
##   three ways) a stack of identical sounds is just louder, not richer.
## - Under the Dummy audio driver (headless runs, tests, CI, a machine with
##   no sound device) play() does nothing and returns null, so callers never
##   need to check. Unknown names warn once and are skipped, so a typo shows
##   up in the log without breaking the game.
## - `master_volume` is linear 0..1 for a settings slider; it applies to
##   sounds already playing too. If the project ever adds an "SFX" bus the
##   pool uses it, so music and effects can be mixed separately there.

const DIR := "res://assets/audio/sfx/"
const POOL_SIZE := 10
const VOLUME_JITTER_DB := 1.5

## name -> [takes on disk, pitch jitter (+- semitones), volume offset dB].
## Keep in step with SOUNDS in tools/make_sfx.py (tests/test_sfx.gd checks
## that every file here exists and every file on disk is listed).
const SOUNDS := {
	&"card_deal": [3, 1.5, 0.0],
	&"card_flip": [1, 1.0, 0.0],
	&"chips": [3, 1.5, 0.0],
	&"chips_pot": [1, 0.5, 0.0],
	&"check": [1, 1.0, 0.0],
	&"fold": [1, 1.0, 0.0],
	&"all_in": [1, 0.0, 0.0],
	&"win_pot": [1, 0.0, 0.0],
	&"lose": [1, 0.0, 0.0],
	&"your_turn": [1, 0.0, 0.0],
	&"signal": [2, 2.0, 0.0],
	&"dealer_warning": [1, 0.3, 0.0],
	&"fine": [1, 0.3, 0.0],
	&"ejection": [1, 0.3, 0.0],
	&"ui_move": [1, 0.5, 0.0],
	&"ui_confirm": [1, 0.0, 0.0],
	&"ui_back": [1, 0.0, 0.0],
	&"step_grass": [3, 2.0, 0.0],
	&"step_wood": [3, 1.5, 0.0],
	&"encounter": [1, 0.0, 0.0],
	&"voice_owl": [1, 1.0, 0.0],
	&"voice_goose": [1, 1.5, 0.0],
	&"voice_cat": [1, 1.5, 0.0],
	&"voice_raccoon": [1, 1.5, 0.0],
	&"voice_squirrel": [1, 1.5, 0.0],
	&"voice_possum": [1, 1.0, 0.0],
}

## Linear, 0..1. 0 mutes (play() returns null).
var master_volume := 1.0:
	set = set_master_volume
## False under the Dummy audio driver; play() is then a no-op. Tests set it
## true to exercise the pool (the dummy driver accepts playback silently).
var available := true
var warn_unknown := true
var repeat_gap_msec := 35

var _streams := {}  ## name -> Array of AudioStream, one per take
var _players: Array[AudioStreamPlayer] = []
var _last_take := {}  ## name -> index of the take played last
var _last_played := {}  ## name -> ticks_msec
var _warned := {}
var _serial := 0  ## counts plays, to find the player that started longest ago
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	setup()


## Loads the sounds and builds the pool. _ready() calls it; tests call it
## directly, since the test runner has no scene tree to add the node to (and
## then nothing is actually started: see play()).
func setup() -> void:
	if _players:
		return
	available = AudioServer.get_driver_name() != "Dummy"
	_rng.randomize()
	var bus := &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	for name: StringName in SOUNDS:
		var takes: Array[AudioStream] = []
		for path in paths(name):
			if ResourceLoader.exists(path):
				var stream := load(path) as AudioStream
				if stream:
					takes.append(stream)
		if takes:
			_streams[name] = takes
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.set_meta(&"serial", -1)
		p.set_meta(&"ends_at", 0)
		p.set_meta(&"base_db", 0.0)
		add_child(p)
		_players.append(p)


## The files behind a sound name, one per take.
static func paths(name: StringName) -> Array[String]:
	var out: Array[String] = [DIR + name + ".wav"]
	var takes: int = SOUNDS.get(name, [1])[0]
	for k in range(2, takes + 1):
		out.append("%s%s_%d.wav" % [DIR, name, k])
	return out


func has_sound(name: StringName) -> bool:
	return _streams.has(name)


## Plays `name` with a little random pitch and volume, on top of the caller's
## own `volume_db` and `pitch` (e.g. a bigger animal's voice a bit lower).
## Returns the player, or null if nothing played.
func play(name: StringName, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	if not available or master_volume <= 0.0:
		return null
	var takes: Array = _streams.get(name, [])
	if takes.is_empty():
		if warn_unknown and not _warned.has(name):
			_warned[name] = true
			push_warning("Sfx: no sound named %s" % name)
		return null
	var now := Time.get_ticks_msec()
	if _last_played.has(name) and now - int(_last_played[name]) < repeat_gap_msec:
		return null
	_last_played[name] = now
	var spec: Array = SOUNDS[name]
	var jitter: float = spec[1]
	var player := _next_player()
	player.stream = takes[_pick_take(name, takes.size())]
	player.pitch_scale = pitch * pow(2.0, _rng.randf_range(-jitter, jitter) / 12.0)
	var base_db: float = volume_db + float(spec[2]) - _rng.randf_range(0.0, VOLUME_JITTER_DB)
	player.set_meta(&"base_db", base_db)
	_serial += 1
	player.set_meta(&"serial", _serial)
	player.set_meta(&"ends_at", now + int(1000.0 * player.stream.get_length() / player.pitch_scale))
	player.volume_db = base_db + linear_to_db(master_volume)
	if player.is_inside_tree():
		player.play()
	return player


## The species' voice blip (voice_owl...), or nothing for a species without
## one yet: the full game has ~25 species and the placeholders cover six, so
## this stays quiet instead of warning.
func voice(species_id: StringName, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var name := StringName("voice_%s" % species_id)
	if not _streams.has(name):
		return null
	return play(name, volume_db, pitch)


func stop_all() -> void:
	for p in _players:
		p.stop()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	for p in _players:
		if master_volume <= 0.0:
			p.stop()
		else:
			p.volume_db = float(p.get_meta(&"base_db")) + linear_to_db(master_volume)


## A free player, or the one that started longest ago. "Free" goes by the
## expected end time as well as `playing`, so the choice is the same with
## or without a running audio server (and testable without one).
func _next_player() -> AudioStreamPlayer:
	var now := Time.get_ticks_msec()
	var oldest := _players[0]
	for p in _players:
		if not p.playing and int(p.get_meta(&"ends_at")) <= now:
			return p
		if int(p.get_meta(&"serial")) < int(oldest.get_meta(&"serial")):
			oldest = p
	return oldest


func _pick_take(name: StringName, count: int) -> int:
	if count == 1:
		return 0
	var last: int = _last_take.get(name, -1)
	var pick := _rng.randi_range(0, count - 1)
	if last >= 0:
		pick = _rng.randi_range(0, count - 2)
		if pick >= last:
			pick += 1  # skip the take played last time
	_last_take[name] = pick
	return pick
