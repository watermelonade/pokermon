extends Node
## The Game autoload: holds the run's GameState, saves it, and switches
## between the title and the overworld. Registered in project.godot as
## `Game` (no class_name, since an autoload's name is already global).
##
## Saving: SaveFile writes atomically, and the overworld calls save() after
## every match, on every door, and this node saves again when the window
## loses focus or is closed. A Steam Deck suspend just freezes the process
## (no notification is guaranteed), so frequent saves are the real
## protection: at worst you lose the walk since the last door or match.
##
## Dev flags (after `--`), for scripted runs and screenshots without a
## display:
##   --save-slot=NAME      use user://NAME.json instead of the real save
##   --new / --continue    skip the title
##   --auto                dialogs and menus advance by themselves
##   --choice=N            ...picking option N in menus (default 0)
##   --match-result=win|lose   skip the poker table, as if it ended so
##   --chips=N             starting chips at real tables (shorter matches)
##   --walk=R12U3A         scripted input: a direction (U D L R) and steps,
##                         A to press confirm, M for the menu, W to wait
##   --at=map,x,y          start there; --beaten=all or id,id; --money=N;
##                         --recruit=cat:0,goose:1 adds roster animals
##   --show=party|demo_complete   open a screen once the world is up
##   --screenshot=/abs.png --shot-after=SECONDS   save the screen and quit
## The table's own flags (--autoplay, --dealer=) still reach an embedded
## table, so --autoplay lets a bot play your seat in a scripted run.

const TITLE_SCENE := "res://scenes/title.tscn"
const WORLD_SCENE := "res://scenes/world/overworld.tscn"
const TABLE_SCENE := "res://scenes/table.tscn"

signal saved

var state: GameState
var save_path := SaveFile.DEFAULT_PATH
var dev_auto := false
var dev_choice := 0
var dev_args := {}  ## flag name (without --) -> value ("" for bare flags)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv := arg.substr(2).split("=", true, 1)
		dev_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if dev_args.has("save-slot"):
		save_path = "user://%s.json" % dev_args["save-slot"]
	dev_auto = dev_args.has("auto")
	dev_choice = int(dev_args.get("choice", "0"))
	_screenshot_if_asked.call_deferred()


func dev(flag: String, fallback := "") -> String:
	return dev_args.get(flag, fallback)


## Prints a line in dev runs (any dev flag given), for following a scripted
## run from the terminal; silent in normal play.
func dev_log(line: String) -> void:
	if dev_args:
		print("[game] ", line)


func new_game() -> void:
	state = GameState.fresh()
	save()


func has_save() -> bool:
	return SaveFile.exists(save_path)


func continue_game() -> bool:
	var s := SaveFile.read(save_path)
	if s:
		state = s
	return s != null


func save() -> void:
	if state == null:
		return
	var err := SaveFile.write(state, save_path)
	if err != OK:
		push_warning("save failed: %s" % error_string(err))
		return
	dev_log("saved: %s at %s %s, $%d, beaten %s" % [save_path, state.map_id, state.cell, state.money, state.beaten.keys()])
	saved.emit()


func goto_world() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


func goto_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


## Applies the dev flags that change the run (position, money, roster...),
## once, when the overworld first starts.
func apply_dev_state() -> void:
	if state == null:
		return
	if dev_args.has("at"):
		var p := dev("at").split(",")
		if p.size() == 3:
			state.map_id = p[0]
			state.cell = Vector2i(int(p[1]), int(p[2]))
	if dev_args.has("money"):
		state.money = int(dev("money"))
	if dev_args.has("beaten"):
		for map_id: String in WorldMap.ids():
			for c: Dictionary in WorldMap.get_map(map_id).crews:
				if dev("beaten") == "all" or c["id"] in dev("beaten").split(","):
					state.beaten[c["id"]] = true
	if dev_args.has("recruit"):
		for entry in dev("recruit").split(","):
			var p := entry.split(":")
			if p.size() == 2 and Species.CATALOG.has(StringName(p[0])):
				state.recruit(Species.individual(StringName(p[0]), int(p[1])))
	state.seen_intro = state.seen_intro or dev_args.has("skip-intro")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		save()


func _screenshot_if_asked() -> void:
	var path := dev("screenshot")
	if path == "":
		return
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path == TABLE_SCENE:
		return  # the table takes its own
	await get_tree().create_timer(float(dev("shot-after", "2.5"))).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot saved: ", path)
	get_tree().quit()
