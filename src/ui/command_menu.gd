class_name CommandMenu
extends RefCounted
## Your turn's command menu: a 2x2 grid with a cursor, like a handheld RPG's
## battle menu, instead of a row of Godot Buttons.
##
##   CALL 20     RAISE 40
##   FOLD        HELP
##
## Why a grid: on a controller the D-pad then reaches every command in one
## press, and the cursor is a focus mark you can't miss (the Buttons' focus
## frame was the only thing saying which one A would press). Raise opens an
## amount picker (RaiseSizes) rather than raising at once, so a stray A on
## Raise never shoves chips in: two presses, the way picking a move is.
##
## Items you can't use (Fold when checking is free, Raise when you can only
## call) stay on the grid greyed out: moving the cursor never skips around.
## Pure state, no drawing, so tests can drive it.

enum Item { CALL, RAISE, FOLD, HELP }

const COLUMNS := 2
const ORDER := [Item.CALL, Item.RAISE, Item.FOLD, Item.HELP]

var cursor := 0  ## index into ORDER
var enabled := {Item.CALL: true, Item.RAISE: true, Item.FOLD: true, Item.HELP: true}


func current() -> Item:
	return ORDER[cursor]


func reset() -> void:
	cursor = 0


## Moves the cursor by a D-pad direction; stays put at the grid's edge.
func move(dir: Vector2i) -> void:
	var col := cursor % COLUMNS + dir.x
	var row := cursor / COLUMNS + dir.y
	var rows := ceili(ORDER.size() / float(COLUMNS))
	if col < 0 or col >= COLUMNS or row < 0 or row >= rows:
		return
	var next := row * COLUMNS + col
	if next < ORDER.size():
		cursor = next


## The item A picks, or -1 when the cursor is on one you can't use.
func choose() -> int:
	return current() if enabled[current()] else -1
