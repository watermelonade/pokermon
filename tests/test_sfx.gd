extends TestCase
## The sound player (src/audio/sfx.gd) and the files behind it. These run
## under the Dummy audio driver, so nothing is heard: they check that every
## listed sound exists and loads as a short mono WAV, that nothing on disk is
## forgotten, and that the player's pool, variation and no-op paths behave.

const SfxScript := preload("res://src/audio/sfx.gd")


## The runner has no scene tree yet (tests run in SceneTree._init), so the
## player is set up by hand and plays decide everything but don't start.
func _make() -> Node:
	var sfx: Node = SfxScript.new()
	sfx.setup()
	return sfx


func test_every_sound_has_files_that_load() -> void:
	for name: StringName in SfxScript.SOUNDS:
		for path in SfxScript.paths(name):
			if not check(ResourceLoader.exists(path), "%s missing (run python3 tools/make_sfx.py)" % path):
				continue
			var stream := load(path) as AudioStreamWAV
			if not check(stream != null, "%s loads as a WAV" % path):
				continue
			check(not stream.stereo, "%s is mono" % path)
			check_eq(stream.mix_rate, 44100, "%s mix rate" % path)
			var length := stream.get_length()
			check(length > 0.02 and length <= 1.0, "%s is %.3fs, want under a second" % [path, length])


func test_every_file_on_disk_is_listed() -> void:
	var listed := {}
	for name: StringName in SfxScript.SOUNDS:
		for path in SfxScript.paths(name):
			listed[path.get_file()] = true
	for file in DirAccess.get_files_at(SfxScript.DIR):
		if file.ends_with(".wav"):
			check(listed.has(file), "%s is on disk but not in Sfx.SOUNDS" % file)


func test_every_species_has_a_voice() -> void:
	for id: StringName in Species.ids():
		check(SfxScript.SOUNDS.has(StringName("voice_%s" % id)), "%s has a voice blip" % id)


func test_plays_from_a_pool_with_variation() -> void:
	var sfx := _make()
	sfx.available = true  # the dummy driver accepts playback silently
	sfx.repeat_gap_msec = 0
	var pitches := {}
	var streams := {}
	var players := {}
	for i in 12:
		var p: AudioStreamPlayer = sfx.play(&"chips")
		if not check(p != null, "chips played"):
			break
		pitches[snappedf(p.pitch_scale, 0.0001)] = true
		streams[p.stream] = true
		players[p] = true
		check(absf(12.0 * log(p.pitch_scale) / log(2.0)) <= 1.5 + 1e-4, "pitch jitter within 1.5 semitones")
		check(p.volume_db <= 0.0 and p.volume_db >= -1.5 - 1e-4, "volume jitter within 1.5 dB")
	check(pitches.size() > 1, "pitch varies between plays")
	check_eq(streams.size(), 3, "all three chip takes get used")
	check_eq(players.size(), SfxScript.POOL_SIZE, "twelve overlapping plays use the whole pool, then reuse")
	var chime: AudioStreamPlayer = sfx.play(&"win_pot")
	check_eq(chime.pitch_scale, 1.0, "jingles aren't detuned")
	sfx.free()


func test_never_the_same_take_twice_in_a_row() -> void:
	var sfx := _make()
	sfx.available = true
	sfx.repeat_gap_msec = 0
	var last: AudioStream = null
	for i in 20:
		var p: AudioStreamPlayer = sfx.play(&"step_grass")
		check(p.stream != last, "take repeated on play %d" % i)
		last = p.stream
	sfx.free()


func test_repeats_within_the_gap_play_once() -> void:
	var sfx := _make()
	sfx.available = true
	sfx.repeat_gap_msec = 10000
	check(sfx.play(&"fold") != null, "first fold plays")
	check(sfx.play(&"fold") == null, "the same sound in the same instant doesn't stack")
	check(sfx.play(&"check") != null, "a different sound still plays")
	sfx.free()


func test_no_ops() -> void:
	var sfx := _make()
	check_eq(sfx.available, false, "headless runs use the Dummy driver, so sound is off")
	check(sfx.play(&"chips") == null, "no-op without an audio device")
	sfx.available = true
	sfx.warn_unknown = false
	check(sfx.play(&"no_such_sound") == null, "unknown names are skipped")
	check(sfx.voice(&"dog") == null, "species without a voice stay quiet")
	check(sfx.voice(&"owl") != null, "the owl hoots")
	sfx.master_volume = 0.0
	check(sfx.play(&"chips") == null, "muted")
	sfx.free()


func test_master_volume_scales_playing_sounds() -> void:
	var sfx := _make()
	sfx.available = true
	var p: AudioStreamPlayer = sfx.play(&"lose")
	var full := p.volume_db
	sfx.master_volume = 0.5
	check(absf(p.volume_db - (full + linear_to_db(0.5))) < 0.01, "half volume is about -6 dB, applied live")
	sfx.master_volume = 3.0
	check_eq(sfx.master_volume, 1.0, "clamped to 1")
	sfx.free()


func test_lounge_loop_loops() -> void:
	var music := load("res://assets/audio/music/lounge_loop.wav") as AudioStreamWAV
	if check(music != null, "the placeholder lounge loop loads"):
		check_eq(music.loop_mode, AudioStreamWAV.LOOP_FORWARD, "loops (edit/loop_mode=2 in its .import)")
		check(music.get_length() > 10.0, "a loop of several bars")
