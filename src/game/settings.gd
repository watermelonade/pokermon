class_name Settings
extends RefCounted
## Player options from the start menu: text speed and volume. Kept in
## user://settings.cfg, apart from the save, so starting a new game (which
## replaces the one save) doesn't reset them, and so they're already right
## on the title screen.

const PATH := "user://settings.cfg"
const TEXT_SPEEDS := ["Slow", "Normal", "Fast"]
const CHARS_PER_SECOND := [30.0, 60.0, 140.0]

var text_speed := 1  ## index into TEXT_SPEEDS
var volume := 8  ## 0..10, the master bus


static func load_from(path := PATH) -> Settings:
	var s := Settings.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		s.text_speed = clampi(int(cfg.get_value("text", "speed", 1)), 0, TEXT_SPEEDS.size() - 1)
		s.volume = clampi(int(cfg.get_value("audio", "volume", 8)), 0, 10)
	return s


func save_to(path := PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("text", "speed", text_speed)
	cfg.set_value("audio", "volume", volume)
	return cfg.save(path)


func chars_per_second() -> float:
	return CHARS_PER_SECOND[text_speed]


## Sets the master bus to the chosen volume (0 is muted).
func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, volume == 0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(volume / 10.0) if volume > 0 else -80.0)
