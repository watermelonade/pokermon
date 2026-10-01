class_name BinderScreen
extends Control
## The Binder (Start menu > Binder): the collection, as a trading-card
## binder in place of a Pokedex. A 5x5 page of card pockets on the left,
## one per species slot (Binder.TOTAL), and the card under the cursor on
## the right, front (portrait, name, style and where it sits in the type
## chart) and back (where you found one, its tell, its favourite snack, and
## the four named individuals: who you've met, who's in your crew, and
## their bond). The counter in the corner is species recruited of 25.
##
## What's shown depends on what you know (Binder.status): an unseen
## species is a flat silhouette, a seen one is greyed with what you saw at
## the table, a recruited one is in full colour. The 18 locked slots are
## the full game's species; the last is the dogs' silhouette. All the
## knowing lives in Binder and GameState so it's tested headless; this
## only draws.
##
## Controller first, like every overworld screen: the D-pad moves through
## the pockets (wrapping), B or Start closes. A 5x5 grid fits all 25 on
## one page at 640x400, so there's no paging to learn.

signal closed

const COLS := 5
const CELL := Vector2(46, 56)
const GAP := 4.0
const GRID_AT := Vector2(20, 50)

var state: GameState
var _cursor := 0  ## slot index, 0..TOTAL-1 (slot number - 1)
var _opened_frame := 0
var _auto_at := 0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(s: GameState) -> void:
	state = s
	_cursor = clampi(int(Game.dev("binder-at", "1")) - 1, 0, Binder.TOTAL - 1)
	_opened_frame = Engine.get_process_frames()
	_auto_at = Time.get_ticks_msec() + 1500
	visible = true
	queue_redraw()
	await closed
	visible = false


func _process(_delta: float) -> void:
	if visible and Game.dev_auto and Time.get_ticks_msec() > _auto_at:
		_auto_at = 1 << 62
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	var d := UiKit.menu_dir(event)
	if d.x != 0:
		var row := _cursor / COLS
		_cursor = row * COLS + wrapi(_cursor % COLS + d.x, 0, COLS)
	elif d.y != 0:
		_cursor = wrapi(_cursor + d.y * COLS, 0, Binder.TOTAL)
	elif UiKit.cancel(event):
		closed.emit()
	else:
		return
	queue_redraw()
	get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.BG)
	UiKit.panel(self, Rect2(8, 8, size.x - 16, size.y - 16))
	UiKit.text(self, Vector2(22, 32), "Binder", 16, UiKit.GOLD)
	var right := size.x - 22
	UiKit.text(self, Vector2(right, 32), Binder.completion(state), 16, UiKit.TEXT, 2)
	var w := UiKit.text_width(Binder.completion(state), 16)
	UiKit.text(self, Vector2(right - w - 8, 32), "Recruited", 8, UiKit.QUIET, 2)
	var seen := "Seen %d" % Binder.seen_count(state)
	UiKit.text(self, Vector2(right - w - 8 - UiKit.text_width("Recruited", 8) - 14, 32), seen, 8, UiKit.QUIET, 2)
	for i in Binder.TOTAL:
		_draw_pocket(i)
	_draw_card(Rect2(278, 46, size.x - 278 - 22, 318))
	UiKit.text(self, Vector2(22, size.y - 22), "D-pad: browse     B or Start: back", 8, UiKit.QUIET)


func _pocket_rect(i: int) -> Rect2:
	return Rect2(GRID_AT + Vector2(i % COLS, i / COLS) * (CELL + Vector2(GAP, GAP)), CELL)


func _draw_pocket(i: int) -> void:
	var r := _pocket_rect(i)
	var number := i + 1
	var st := Binder.status(state, number)
	var bg: Color = {
		Binder.Status.LOCKED: UiKit.BG.lightened(0.03),
		Binder.Status.UNSEEN: UiKit.PANEL.lightened(0.05),
		Binder.Status.SEEN: UiKit.PANEL.lightened(0.1),
		Binder.Status.RECRUITED: UiKit.TEAL.darkened(0.15),
		Binder.Status.DOGS: UiKit.RUST.darkened(0.35),
	}[st]
	draw_rect(r, bg)
	draw_rect(r, UiKit.QUIET.darkened(0.55), false)
	var pic := Rect2(r.position + Vector2((CELL.x - 32) / 2, 16), Vector2(32, 32))
	match st:
		Binder.Status.LOCKED:
			UiKit.text(self, r.position + Vector2(CELL.x / 2, 38), "?", 16, UiKit.QUIET.darkened(0.4), 1)
		Binder.Status.DOGS:
			PocketArt.dog(self, pic, UiKit.BG)
		_:
			var look := PocketArt.Look.FULL if st == Binder.Status.RECRUITED else (PocketArt.Look.GREY if st == Binder.Status.SEEN else PocketArt.Look.SHADOW)
			PocketArt.portrait(self, Binder.species_at(number), pic, look)
	UiKit.text(self, r.position + Vector2(4, 11), "%03d" % number, 8, UiKit.QUIET if st != Binder.Status.LOCKED else UiKit.QUIET.darkened(0.4))
	if st == Binder.Status.RECRUITED:
		_chip(r.position + Vector2(CELL.x - 8, 8))
	if i == _cursor:
		draw_rect(r.grow(1), UiKit.GOLD, false, 2.0)


## A poker chip: the Binder's "owned" mark, as the Pokedex used a ball.
func _chip(c: Vector2) -> void:
	draw_circle(c, 4.5, UiKit.HOT)
	draw_circle(c, 2.5, UiKit.TEXT)
	draw_circle(c, 1.5, UiKit.HOT)


func _draw_card(p: Rect2) -> void:
	var number := _cursor + 1
	var st := Binder.status(state, number)
	var id := Binder.species_at(number)
	UiKit.panel(self, p, UiKit.GOLD if st == Binder.Status.RECRUITED else UiKit.QUIET)
	var frame := Rect2(p.position + Vector2(12, 12), Vector2(72, 72))
	draw_rect(frame, UiKit.BG)
	draw_rect(frame, UiKit.QUIET.darkened(0.4), false)
	var pic := Rect2(frame.position + Vector2(4, 4), Vector2(64, 64))
	var x := p.position.x + 96
	var y := p.position.y
	UiKit.text(self, Vector2(x, y + 24), "No. %03d" % number, 8, UiKit.QUIET)
	var body := Vector2(p.position.x + 14, y + 112)
	var width := p.size.x - 28
	match st:
		Binder.Status.LOCKED:
			UiKit.text(self, pic.get_center() + Vector2(0, 10), "?", 32, UiKit.QUIET.darkened(0.4), 1)
			UiKit.text(self, Vector2(x, y + 44), "?????", 16, UiKit.QUIET)
			UiKit.wrapped(self, body, "This species lives far beyond Mossbank. Its card waits for the full game.", width, 10, UiKit.QUIET)
			return
		Binder.Status.DOGS:
			PocketArt.dog(self, pic, PocketArt.SHADOW)
			UiKit.text(self, Vector2(x, y + 44), "?????", 16, UiKit.QUIET)
			UiKit.text(self, Vector2(x, y + 62), Binder.DOG_LINE, 10, UiKit.HOT)
			UiKit.wrapped(self, body, "They keep their own table, and they've never dealt anyone in. Some say they're waiting for a game worth painting.", width, 10, UiKit.QUIET)
			return
		Binder.Status.UNSEEN:
			PocketArt.portrait(self, id, pic, PocketArt.Look.SHADOW)
			UiKit.text(self, Vector2(x, y + 44), "?????", 16, UiKit.QUIET)
			UiKit.wrapped(self, body, "Not seen yet. Sit across a table from one and its card starts to fill in.", width, 10, UiKit.QUIET)
			return
	var info := Species.get_info(id)
	var kind: PlayStyle.Kind = info["style"]
	var recruited := st == Binder.Status.RECRUITED
	PocketArt.portrait(self, id, pic, PocketArt.Look.FULL if recruited else PocketArt.Look.GREY)
	UiKit.text(self, Vector2(x, y + 44), str(info["display"]), 16, UiKit.TEXT)
	UiKit.text(self, Vector2(x, y + 61), PlayStyle.KIND_NAMES[kind], 10, UiKit.GOLD)
	UiKit.text(self, Vector2(x, y + 76), "Beats %s. Wary of %s." % [
		PlayStyle.KIND_NAMES[Binder.beats(kind)], PlayStyle.KIND_NAMES[Binder.loses_to(kind)]], 8, UiKit.QUIET)
	draw_rect(Rect2(p.position.x + 12, y + 94, p.size.x - 24, 1), UiKit.QUIET.darkened(0.5))
	var label_w := 44.0
	var facts := [
		["Found", str(state.found_at.get(String(id), "On the road"))],
		["Tell", str(info["tell"]) if recruited else "??? Play alongside one to learn it."],
		["Snack", str(Binder.SNACKS.get(id, "?")) if recruited else "???"],
	]
	var fy := y + 110
	for f: Array in facts:
		UiKit.text(self, Vector2(body.x, fy), f[0], 8, UiKit.GOLD)
		var lines := 2 if UiKit.text_width(f[1], 10) > width - label_w else 1
		UiKit.wrapped(self, Vector2(body.x + label_w, fy), f[1], width - label_w, 10, UiKit.TEXT if recruited or f[0] == "Found" else UiKit.QUIET, lines)
		fy += 14 * lines + 6
	draw_rect(Rect2(p.position.x + 12, fy - 4, p.size.x - 24, 1), UiKit.QUIET.darkened(0.5))
	UiKit.text(self, Vector2(body.x, fy + 12), "Individuals", 8, UiKit.GOLD)
	fy += 16
	# Two lines each: name, tag and bond; then the bio (Bios) once met.
	for ind: Dictionary in Binder.individuals(state, id):
		var row := Rect2(body.x - 2, fy, width + 4, 25)
		var a: Animal = ind["animal"]
		if a:
			draw_rect(row, UiKit.TEAL.darkened(0.35))
		UiKit.text(self, Vector2(body.x + 2, fy + 11), ind["name"], 10, UiKit.TEXT if ind["met"] else UiKit.QUIET)
		if a:
			var tag := "IN YOUR CREW" if not state.party.has(state.roster.find(a)) else "SITS WITH YOU"
			UiKit.text(self, Vector2(body.x + 74, fy + 11), tag, 8, UiKit.GOLD)
			PocketArt.hearts(self, Vector2(row.end.x - PocketArt.hearts_width() - 6, fy + 4), a.bond)
		elif ind["met"]:
			UiKit.text(self, Vector2(body.x + 74, fy + 11), "met at the table", 8, UiKit.QUIET)
		if ind["met"]:
			UiKit.text(self, Vector2(body.x + 2, fy + 22), Bios.bio(id, ind["real_name"]), 8, UiKit.QUIET)
		fy += 27
