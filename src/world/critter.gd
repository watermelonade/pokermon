class_name Critter
extends Node2D
## Anyone walking around the overworld: you, your two teammates, rival
## crew members, townsfolk. It's a node (not just a cell in the map) so
## steps can be tweened smoothly between tiles while the rules stay on the
## grid: `cell` is where it logically is, `position` is where it's drawn.
##
## Draws the sprite from SpriteBank if one exists, else a placeholder made
## of a few rectangles per species (a mask for the raccoon, a beak for the
## goose...) so you can tell a crew apart at 16 pixels before any art
## exists. The placeholder painter is static so the title and party screens
## can draw the same animals.

const STEP_TIME := 0.16  ## seconds per tile; Pokemon walks about 4 tiles a second

## Placeholder palette per sprite id: body, detail.
const LOOKS := {
	"player": [Color("2f6f6a"), Color("f0c8a0")],
	"owl": [Color("8a6a48"), Color("e8c35a")],
	"raccoon": [Color("7d7a86"), Color("2a2830")],
	"goose": [Color("ece8de"), Color("e8873a")],
	"cat": [Color("d08a3a"), Color("6b3f1c")],
	"squirrel": [Color("b0603a"), Color("e8b48a")],
	"possum": [Color("c4bcb6"), Color("e89aa8")],
	"npc_cook": [Color("f4ecd8"), Color("c0503a")],
	"npc_badger": [Color("4a4650"), Color("f4ecd8")],
	"npc_kid": [Color("e8c35a"), Color("f0c8a0")],
	"npc_dealer": [Color("2b2b33"), Color("2b5b3a")],
}
const INK := Color("1d1a24")

var sprite_id := "player"
var cell := Vector2i.ZERO
var facing := Vector2i.DOWN
var alert := false  ## the "!" when a crew spots you
var asleep := false  ## a dealer who's dozed off
var _walking := false
var _bob := 0.0


static func make(id: String, at: Vector2i, face := Vector2i.DOWN) -> Critter:
	var c := Critter.new()
	c.sprite_id = id
	c.place(at, face)
	return c


func place(at: Vector2i, face := facing) -> void:
	cell = at
	facing = face
	position = Vector2(at * WorldMap.TILE)
	queue_redraw()


func face(dir: Vector2i) -> void:
	if dir != Vector2i.ZERO and dir != facing:
		facing = dir
		queue_redraw()


## Walks one tile (or any distance in one go, for followers catching up).
## Awaitable: `await critter.step_to(cell)`.
func step_to(target: Vector2i, time := STEP_TIME) -> void:
	if target != cell:
		var d := target - cell
		if absi(d.x) + absi(d.y) == 1:
			face(d)
	cell = target
	_walking = true
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(target * WorldMap.TILE), time)
	await tw.finished
	_walking = false
	_bob = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _walking or asleep:
		_bob += delta
		queue_redraw()


func _draw() -> void:
	var lift := 0.0
	if _walking and int(_bob / 0.08) % 2 == 1:
		lift = -1.0
	var tex := SpriteBank.character(sprite_id)
	if tex:
		var region := SpriteBank.character_region(tex)
		var at := Vector2(int((WorldMap.TILE - region.size.x) / 2), WorldMap.TILE - region.size.y + lift)
		draw_texture_rect_region(tex, Rect2(at, region.size), region)
	else:
		Critter.paint(self, sprite_id, facing, Vector2(0, lift))
	if alert:
		draw_rect(Rect2(4, -14, 9, 12), Color("f4ecd8"))
		draw_rect(Rect2(4, -14, 9, 12), INK, false)
		draw_rect(Rect2(7.5, -12, 2, 6), Color("d9603b"))
		draw_rect(Rect2(7.5, -5, 2, 2), Color("d9603b"))
	if asleep:
		var k := int(_bob * 1.5) % 3
		var font := ThemeDB.fallback_font
		for i in k + 1:
			draw_string(font, Vector2(11 + i * 3, -1 - i * 4), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("f4ecd8"))


## A placeholder of `id` in a 16x16 box at `at`, scaled by `s` (the party
## screen draws them bigger). Rough on purpose: shapes that read at 16px.
static func paint(ci: CanvasItem, id: String, dir: Vector2i, at := Vector2.ZERO, s := 1.0) -> void:
	var look: Array = LOOKS.get(id, [Color("888888"), Color("cccccc")])
	var body: Color = look[0]
	var detail: Color = look[1]
	var r := func(x: float, y: float, w: float, h: float, c: Color) -> void:
		ci.draw_rect(Rect2(at + Vector2(x, y) * s, Vector2(w, h) * s), c)
	# Shadow.
	r.call(3, 14, 10, 2, Color(0, 0, 0, 0.25))
	var human := id == "player" or id == "npc_cook" or id == "npc_kid" or id == "npc_dealer"
	if human:
		var top := 1.0 if id != "npc_kid" else 4.0
		r.call(4, top + 5, 8, 15 - top - 5, body)  # coat
		r.call(5, top, 6, 6, detail if id != "npc_dealer" else Color("f0c8a0"))  # head
		match id:
			"player":
				r.call(4, top - 1, 8, 2, Color("e8c35a"))  # a gold cap
				r.call(3, top, 2, 1, Color("e8c35a"))
			"npc_cook":
				r.call(5, top - 2, 6, 3, Color("ffffff"))  # chef's hat
				r.call(5, top + 6, 6, 7, Color("ffffff"))  # apron
			"npc_dealer":
				r.call(4, top, 8, 2, detail)  # green visor
				r.call(6, top + 6, 4, 2, Color("ffffff"))  # shirt collar
			"npc_kid":
				r.call(5, top, 6, 2, Color("6b3f1c"))
		if dir != Vector2i.UP:
			var ex := 6.0 if dir != Vector2i.RIGHT else 7.0
			if dir == Vector2i.LEFT:
				ex = 5.0
			r.call(ex, top + 3, 1, 1, INK)
			if dir == Vector2i.DOWN:
				r.call(ex + 3, top + 3, 1, 1, INK)
		return
	# Animals: a round body, a head, and one feature each.
	r.call(3, 7, 10, 7, body)
	r.call(4, 3, 8, 6, body)
	match id:
		"owl":
			r.call(4, 2, 2, 2, body); r.call(10, 2, 2, 2, body)  # ear tufts
			r.call(5, 9, 6, 4, detail.lightened(0.5))  # belly
			if dir != Vector2i.UP:
				r.call(5, 4, 2, 2, detail); r.call(9, 4, 2, 2, detail)
				r.call(7, 6, 2, 1, Color("e8873a"))
		"raccoon":
			r.call(4, 1, 2, 2, body); r.call(10, 1, 2, 2, body)
			if dir != Vector2i.UP:
				r.call(4, 4, 8, 2, detail)  # mask
				r.call(5, 4, 1, 1, Color("f4ecd8")); r.call(10, 4, 1, 1, Color("f4ecd8"))
			var tx := 12.0 if dir != Vector2i.RIGHT else 0.0
			for k in 3:
				r.call(tx, 8 + k * 2, 3, 1, detail if k % 2 == 0 else body)
		"goose":
			r.call(6, 0, 4, 7, body)  # long neck
			if dir != Vector2i.UP:
				var bx := 6.0 if dir == Vector2i.LEFT else (8.0 if dir == Vector2i.RIGHT else 6.5)
				r.call(bx, 3, 3, 2, detail)
				r.call(7, 1, 1, 1, INK)
		"cat":
			r.call(4, 1, 2, 3, body); r.call(10, 1, 2, 3, body)  # pointed ears
			r.call(3, 9, 2, 1, detail)
			if dir != Vector2i.UP:
				r.call(5, 5, 2, 1, Color("6fbf5a")); r.call(9, 5, 2, 1, Color("6fbf5a"))
		"squirrel":
			var sx := 11.0 if dir != Vector2i.RIGHT else 0.0
			r.call(sx, 2, 5, 11, detail.darkened(0.2))  # the big tail
			r.call(5, 9, 6, 4, detail)
			if dir != Vector2i.UP:
				r.call(5, 5, 1, 1, INK); r.call(10, 5, 1, 1, INK)
		"possum":
			r.call(4, 2, 2, 2, detail); r.call(10, 2, 2, 2, detail)  # pink ears
			if dir != Vector2i.UP:
				r.call(5, 5, 1, 1, INK); r.call(10, 5, 1, 1, INK)
				r.call(7, 7, 2, 1, detail)
			r.call(13, 11, 3, 1, detail)  # bare tail
		"npc_badger":
			r.call(7, 3, 2, 6, detail)  # the white stripe
			if dir != Vector2i.UP:
				r.call(5, 5, 1, 1, Color("f4ecd8")); r.call(10, 5, 1, 1, Color("f4ecd8"))
		_:
			if dir != Vector2i.UP:
				r.call(5, 5, 1, 1, INK); r.call(10, 5, 1, 1, INK)
