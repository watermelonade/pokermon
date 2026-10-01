class_name PartyScreen
extends Control
## The pause screen: your roster, and which two sit with you at the next
## table. A toggles an animal in or out; B (or Start) closes, but only once
## both seats are filled, so you can never walk into a match short-handed.
## Also shows money and bracelets, the run's only other numbers.
##
## Each row shows what matters at the table: the play style (the type
## chart: Bluffer > Rock > Maniac > Shark > Calling Station > Bluffer), the
## species' tell, and bond (how reliably it reads your signals; recruits
## start lower than your first two).

signal closed

const ROW_H := 40.0
const VISIBLE_ROWS := 7

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
	UiKit.text(self, Vector2(22, 30), "Your crew", 16, UiKit.GOLD)
	UiKit.text(self, Vector2(size.x - 22, 30), "$%d" % state.money, 16, UiKit.TEXT, 2)
	var bracelets := "Bracelets: %d" % state.bracelets.size()
	UiKit.text(self, Vector2(size.x - 22, 44), bracelets, 8, UiKit.QUIET, 2)
	UiKit.text(self, Vector2(22, 44), "The two marked sit with you at the next table.", 8, UiKit.QUIET)
	var top := 54.0
	for row in mini(VISIBLE_ROWS, state.roster.size() - _scroll):
		var i := row + _scroll
		_draw_row(i, Rect2(18, top + row * ROW_H, size.x - 36, ROW_H - 4))
	if _scroll > 0:
		UiKit.text(self, Vector2(size.x / 2, top - 1), "more above", 8, UiKit.QUIET, 1)
	if _scroll + VISIBLE_ROWS < state.roster.size():
		UiKit.text(self, Vector2(size.x / 2, top + VISIBLE_ROWS * ROW_H + 2), "more below", 8, UiKit.QUIET, 1)
	var foot := size.y - 22
	UiKit.text(self, Vector2(22, foot), "A: sit down / stand up     B or Start: done", 8, UiKit.QUIET)
	if _message:
		UiKit.text(self, Vector2(size.x - 22, foot), _message, 8, UiKit.HOT, 2)


func _draw_row(i: int, r: Rect2) -> void:
	var a: Animal = state.roster[i]
	var seated := state.party.has(i)
	draw_rect(r, UiKit.TEAL.darkened(0.3) if seated else UiKit.PANEL.lightened(0.04))
	if i == _cursor:
		draw_rect(r.grow(1), UiKit.GOLD, false)
	draw_rect(Rect2(r.position + Vector2(4, 2), Vector2(32, 32)), UiKit.BG)
	Critter.paint(self, String(a.species), Vector2i.DOWN, r.position + Vector2(4, 2), 2.0)
	var info := Species.get_info(a.species)
	var style: String = PlayStyle.KIND_NAMES[a.style_kind()]
	var x := r.position.x + 44
	UiKit.text(self, Vector2(x, r.position.y + 13), a.name, 10, UiKit.TEXT)
	UiKit.text(self, Vector2(x + 70, r.position.y + 13), "%s, %s" % [info["display"], style], 8, UiKit.GOLD)
	UiKit.text(self, Vector2(x, r.position.y + 27), "Tell: " + str(info["tell"]).to_lower(), 8, UiKit.QUIET)
	# Bond bar.
	var bar := Rect2(r.end.x - 170, r.position.y + 7, 60, 6)
	UiKit.text(self, Vector2(bar.position.x - 6, bar.position.y + 6), "Bond", 8, UiKit.QUIET, 2)
	draw_rect(bar, UiKit.BG)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(a.bond, 0, 1), bar.size.y)), UiKit.GOLD)
	if seated:
		var seat := state.party.find(i) + 1
		UiKit.text(self, Vector2(r.end.x - 8, r.position.y + 13), "SEAT %d" % seat, 10, UiKit.TEXT, 2)
