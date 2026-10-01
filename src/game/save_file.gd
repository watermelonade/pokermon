class_name SaveFile
extends RefCounted
## Reads and writes a GameState as JSON under user://.
##
## Writes go to a temporary file first and are then renamed over the save,
## so a Steam Deck that suspends or loses power mid-write leaves the old save
## intact instead of half a file. The game autosaves often (after every
## match, on entering a building, when the window loses focus), so this has
## to be safe to do at any moment.

const DEFAULT_PATH := "user://save.json"


static func write(state: GameState, path := DEFAULT_PATH) -> Error:
	var tmp := path + ".part"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(state.to_dict(), "\t"))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return DirAccess.get_open_error()
	# Rename over the old save (atomic on Linux, so on the Deck); if the
	# platform refuses to replace a file, remove it first.
	var err := dir.rename(tmp.get_file(), path.get_file())
	if err != OK and dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
		err = dir.rename(tmp.get_file(), path.get_file())
	return err


## The saved state, or null if there's no save or it can't be read.
static func read(path := DEFAULT_PATH) -> GameState:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()  # an instance, not JSON.parse_string: that logs an error for a damaged file
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return null
	return GameState.from_dict(json.data)


static func exists(path := DEFAULT_PATH) -> bool:
	return read(path) != null


static func erase(path := DEFAULT_PATH) -> void:
	for p in [path, path + ".part"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
