extends Node
## Writes C-SAME's snapshot of the world (docs/EDITOR_SPEC.md, phase 1;
## tests/world_snapshot.gd says what's in it) to
## tests/fixtures/world_before_content.json, or to --out=PATH:
##
##   godot --headless --path . res://tools/snapshot_world.tscn [-- --out=user://w.json]
##
## A scene rather than a -s script because the area names come from the
## overworld's own _area_name(), and overworld.gd only compiles with the
## autoloads. The fixture in git was made by this BEFORE anything moved
## into content/ (the commit that adds this file), so it's the world as the
## code had it. Remake it only when the world is meant to change (an edit
## in content/ the owner wants), never to make C-SAME pass.

const WorldSnapshot := preload("res://tests/world_snapshot.gd")
const OUT := "res://tests/fixtures/world_before_content.json"


func _ready() -> void:
	var out := OUT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var ow: Node = load("res://src/world/overworld.gd").new()
	ow.set("state", GameState.new())
	var area_name := func(map_id: String, cell: Vector2i) -> String:
		ow.set("map", WorldMap.get_map(map_id))
		(ow.get("state") as GameState).cell = cell
		return ow.call("_area_name")
	var data := {"world": WorldSnapshot.build(area_name), "code_text": WorldSnapshot.code_text()}
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", true) + "\n")
	f.close()
	ow.free()
	print("wrote ", out)
	get_tree().quit()
