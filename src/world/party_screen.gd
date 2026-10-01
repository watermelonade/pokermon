class_name PartyScreen
extends Control
## The pause screen: your roster, and which two sit with you at the next
## table. A toggles an animal in or out; B (or Start) closes, but only once
## both seats are filled, so you can never walk into a match short-handed.
## Also shows money and bracelets, the run's only other numbers.
##
## Laid out like a handheld RPG's party screen: the roster as a list on the
## left (portrait, name, species and style, bond hearts, seat), and on the
## right the table as it will be (you and your two seats) above the
## highlighted animal's details: where its style sits in the type chart
## (Bluffer > Rock > Maniac > Shark > Calling Station > Bluffer), its tell,
## and bond, which is how reliably it reads your signals (recruits start
## lower than your first two, and it grows each match it sits through, see
## GameState.grow_bonds). The earlier version was a single list with all of
## that on each row; with the walk sprite at 2x it was hard to tell the
## animals apart, and the tell text ran into the bond bar.

signal closed

const ROW_H := 38.0
const VISIBLE_ROWS := 8
const LIST := Rect2(18, 50, 300, 0)  ## x, y, width (height from the rows)

var state: GameState
var _cursor := 0
var _scroll := 0
var _message := ""
var _opened_frame := 0
var _auto_at := 0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(s: GameState) -> void:
	state = s
	_cursor = 0
	_scroll = 0
	_message = ""
	_opened_frame = Engine.get_process_frames()
	_auto_at = Time.get_ticks_msec() + 1200
	visible = true
	queue_redraw()
	await closed
	visible = false


func _process(_delta: float) -> void:
	if visible and Game.dev_auto and Time.get_ticks_msec() > _auto_at and state.party_ready():
		_auto_at = 1 << 62
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	var d := UiKit.menu_dir(event)
	if d.y != 0:
		_cursor = wrapi(_cursor + d.y, 0, state.roster.size())
		_scroll = clampi(_scroll, _cursor - VISIBLE_ROWS + 1, _cursor)
		_message = ""
	elif UiKit.accept(event):
		if not state.toggle_party(_cursor):
			_message = "Both seats are taken. Stand someone up first."
		else:
			_message = ""
	elif UiKit.cancel(event):
		if state.party_ready():
			closed.emit()
		else:
			_message = "Pick %d animals to sit with you." % mini(GameState.PARTY_SIZE, state.roster.size())
	else:
		return
	queue_redraw()
	get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.BG)
	UiKit.panel(self, Rect2(8, 8, size.x - 16, size.y - 16))
	UiKit.text(self, Vector2(22, 32), "Your crew", 16, UiKit.GOLD)
	UiKit.text(self, Vector2(size.x - 22, 32), "$%d" % state.money, 16, UiKit.TEXT, 2)
	var bracelets := "Bracelets: %d" % state.bracelets.size()
	var money_w := UiKit.text_width("$%d" % state.money, 16)
	UiKit.text(self, Vector2(size.x - 30 - money_w, 32), bracelets, 8, UiKit.QUIET, 2)
	var top := LIST.position.y
	for row in mini(VISIBLE_ROWS, state.roster.size() - _scroll):
		var i := row + _scroll
		_draw_row(i, Rect2(LIST.position.x, top + row * ROW_H, LIST.size.x, ROW_H - 4))
	if _scroll > 0:
		UiKit.text(self, Vector2(LIST.position.x + LIST.size.x / 2, top - 2), "more above", 8, UiKit.QUIET, 1)
	if _scroll + VISIBLE_ROWS < state.roster.size():
		UiKit.text(self, Vector2(LIST.position.x + LIST.size.x / 2, top + VISIBLE_ROWS * ROW_H + 4), "more below", 8, UiKit.QUIET, 1)
	_draw_side(Rect2(LIST.end.x + 10, 46, size.x - LIST.end.x - 10 - 22, 318))
	var foot := size.y - 22
	UiKit.text(self, Vector2(22, foot), "A: sit down / stand up     B or Start: done", 8, UiKit.QUIET)
	if _message:
		UiKit.text(self, Vector2(size.x - 22, foot), _message, 8, UiKit.HOT, 2)


func _draw_row(i: int, r: Rect2) -> void:
	var a: Animal = state.roster[i]
	var seated := state.party.has(i)
	draw_rect(r, UiKit.TEAL.darkened(0.3) if seated else UiKit.PANEL.lightened(0.04))
	if i == _cursor:
		draw_rect(r.grow(1), UiKit.GOLD, false, 2.0)
	PocketArt.portrait(self, a.species, Rect2(r.position + Vector2(2, 1), Vector2(32, 32)))
	var info := Species.get_info(a.species)
	var x := r.position.x + 42
	UiKit.text(self, Vector2(x, r.position.y + 14), a.name, 10, UiKit.TEXT)
	UiKit.text(self, Vector2(x, r.position.y + 28), "%s, %s" % [info["display"], PlayStyle.KIND_NAMES[a.style_kind()]], 8, UiKit.GOLD)
	PocketArt.hearts(self, Vector2(r.end.x - PocketArt.hearts_width() - 6, r.position.y + 6), a.bond)
	if seated:
		UiKit.text(self, Vector2(r.end.x - 6, r.position.y + 28), "SEAT %d" % (state.party.find(i) + 1), 8, UiKit.TEXT, 2)


## The table as it'll be (you and your two seats), then the highlighted
## animal up close.
func _draw_side(p: Rect2) -> void:
	UiKit.panel(self, p, UiKit.QUIET)
	var x := p.position.x + 12
	var y := p.position.y
	UiKit.text(self, Vector2(x, y + 20), "At the next table", 8, UiKit.GOLD)
	var box_w := (p.size.x - 24 - 12) / 3.0
	for seat in 3:
		var box := Rect2(x + seat * (box_w + 6), y + 26, box_w, 62)
		draw_rect(box, UiKit.BG)
		var mid := box.position.x + box_w / 2
		if seat == 0:
			var you := Sprites.player()
			if you:
				draw_texture_rect(you, Rect2(mid - 12, box.position.y + 4, 24, 36), false)
			UiKit.text(self, Vector2(mid, box.end.y - 8), "You", 8, UiKit.TEXT, 1)
		elif seat - 1 < state.party.size():
			var a: Animal = state.roster[state.party[seat - 1]]
			PocketArt.portrait(self, a.species, Rect2(mid - 16, box.position.y + 6, 32, 32))
			UiKit.text(self, Vector2(mid, box.end.y - 8), a.name, 8, UiKit.TEXT, 1)
		else:
			UiKit.text(self, Vector2(mid, box.position.y + 28), "empty", 8, UiKit.HOT, 1)
			UiKit.text(self, Vector2(mid, box.end.y - 8), "Seat %d" % seat, 8, UiKit.QUIET, 1)
	draw_rect(Rect2(x, y + 98, p.size.x - 24, 1), UiKit.QUIET.darkened(0.5))
	if state.roster.is_empty():
		return
	var a: Animal = state.roster[_cursor]
	var info := Species.get_info(a.species)
	var kind := a.style_kind()
	var frame := Rect2(x, y + 108, 72, 72)
	draw_rect(frame, UiKit.BG)
	PocketArt.portrait(self, a.species, Rect2(frame.position + Vector2(4, 4), Vector2(64, 64)))
	var tx := x + 84
	UiKit.text(self, Vector2(tx, y + 126), a.name, 16, UiKit.TEXT)
	UiKit.text(self, Vector2(tx, y + 143), "%s, %s" % [info["display"], PlayStyle.KIND_NAMES[kind]], 10, UiKit.GOLD)
	UiKit.text(self, Vector2(tx, y + 158), "Beats %s." % PlayStyle.KIND_NAMES[Binder.beats(kind)], 8, UiKit.QUIET)
	UiKit.text(self, Vector2(tx, y + 170), "Wary of %s." % PlayStyle.KIND_NAMES[Binder.loses_to(kind)], 8, UiKit.QUIET)
	var seat := state.party.find(_cursor)
	UiKit.text(self, Vector2(tx, y + 182), "Sits in seat %d" % (seat + 1) if seat >= 0 else "On the bench", 8, UiKit.TEXT)
	var fy := y + 200
	UiKit.text(self, Vector2(x, fy + 10), "Bond", 8, UiKit.GOLD)
	PocketArt.hearts(self, Vector2(x + 44, fy), a.bond, 2.0)
	UiKit.text(self, Vector2(x + 44, fy + 26), "Reads %s." % _reads(a.bond), 8, UiKit.QUIET)
	UiKit.text(self, Vector2(x, fy + 46), "Tell", 8, UiKit.GOLD)
	UiKit.wrapped(self, Vector2(x + 44, fy + 46), str(info["tell"]) + ".", p.size.x - 24 - 44, 10, UiKit.TEXT, 3)


## Bond as what it does: TableTalk.read_from misreads a signal with chance
## (1 - bond) / 2, so 0.2 reads 60% right and full bond every one.
static func _reads(bond: float) -> String:
	return "%d%% of your signals right" % roundi(100.0 * (1.0 - (1.0 - clampf(bond, 0.0, 1.0)) * 0.5))
