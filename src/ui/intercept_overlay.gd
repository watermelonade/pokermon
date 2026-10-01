class_name InterceptOverlay
extends Control
## What your crew catches of the rival crew's signals, drawn over the table
## (src/ui/table_view.gd) as its own Control, so the table's code only
## creates it and hands it the match (the lines marked `# interception:`).
## The rules live in Interception; this only shows them:
##
## - A rival signal your crew noticed pops up over the rival's seat, in the
##   rival's colour with an eye: just the gesture ("ear ?") until your crew
##   has learned what that crew means by it, then the meaning ("ear: weak").
## - The code panel (top left) is what you've learned of their code, gesture
##   by gesture, and which of your gestures they've cracked: those are the
##   ones a fake will sell. A row flashes when it's learned, and the text
##   box says so when the showdown that taught it turns over.
## - When a rival spots one of your crew's signals, eyes flash over it ("!"
##   if it understood, "?" if not), so you can tell whether a fake landed.
## - Your fakes (hold LB or Shift with a signal button: `is_fake_press`)
##   get a "for show" tag next to your bubble.
##
## It reads the seat layout through the table's `_seat_geom(i)` and pauses
## while its help card is open (`_help_open`); both are looked up by name
## and skipped if missing, so a table change can hide the bubbles but can't
## break the match. Times are on the table's clock (ticks / 1000).

const BUBBLE_TIME := 2.5
const EYES_TIME := 1.4
const FLASH_TIME := 2.5
const SHORT_GESTURES := ["Nose", "Ear", "Chips", "Hat"]
const SHORT_MEANINGS := ["strong", "weak", "raise behind", "my pot"]
const DOING := ["touch their noses", "scratch an ear", "stack their chips", "tip their hats"]  ## "when the rivals ..."
const RIVAL := Color("d0603f")
const CREW := Color("3f9a8f")
const GOLD := Color("e8c35a")
const PANEL := Color("14121a")
const S := UiFont.SMALL_SIZE

var table: Control
var match_: TeamMatch
var human := 0
var _bubbles := {}  ## rival seat -> [text, understood, start]
var _eyes := {}  ## rival seat -> [understood, start]
var _fakes := {}  ## seat -> start
var _flash := {}  ## gesture -> when its row lit up
var _own_book := CodeBook.new()  ## kept across rematches when the table has no save's


## Creates the overlay as the last child of `on`, covering it.
static func attach(on: Control) -> InterceptOverlay:
	var o := InterceptOverlay.new()
	o.table = on
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	on.add_child(o)
	return o


## Shows `m` and turns interception on for it (see Interception's
## enable_for_table for `setup` and `codebook`; without a codebook, what's
## learned lasts as long as this table).
func watch(m: TeamMatch, setup: Array[Dictionary], human_seat: int, codebook: CodeBook = null) -> void:
	match_ = m
	human = human_seat
	_bubbles.clear()
	_eyes.clear()
	_fakes.clear()
	_flash.clear()
	m.interception.enable_for_table(setup, human_seat, codebook if codebook else _own_book)
	m.interception.noticed.connect(_on_noticed)
	m.interception.learned.connect(_on_learned)
	m.talk.gesture_made.connect(_on_gesture)


## True if a signal button press is meant as a fake: Shift held on a
## keyboard, LB (raise_less) held on a pad. LB was free to reuse: it only
## steps the raise size, and only on your turn.
static func is_fake_press(event: InputEvent) -> bool:
	if event is InputEventWithModifiers and event.shift_pressed:
		return true
	return InputMap.has_action("raise_less") and Input.is_action_pressed("raise_less")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _my_team() -> int:
	return match_.table.seats[human].team


func _rival_team() -> int:
	for s in match_.table.seats:
		if s.team != _my_team():
			return s.team
	return -1


func _on_noticed(watcher: int, from_seat: int, gesture: int, meaning: int, _fake: bool) -> void:
	if match_.table.seats[from_seat].team == _my_team():
		_eyes[watcher] = [meaning >= 0, _now()]  # a rival caught one of ours
		return
	if match_.table.seats[watcher].team != _my_team():
		return  # a third crew's catch (boss tables): not yours to see
	var text: String = SHORT_GESTURES[gesture].to_lower()
	text += (": " + SHORT_MEANINGS[meaning]) if meaning >= 0 else " ?"
	_bubbles[from_seat] = [text, meaning >= 0, _now()]


func _on_gesture(seat: int, _sig: int) -> void:
	var sent := match_.talk.sent
	if seat == human and sent and sent.back().get("fake", false):
		_fakes[seat] = _now()


func _on_learned(reader_team: int, signaller_team: int, gesture: int, meaning: int) -> void:
	# The table settles the hand after this (it connected later), so the
	# moment the cards turn over is only known once it has: defer.
	_announce.call_deferred(reader_team, signaller_team, gesture, meaning)


func _announce(reader_team: int, _signaller_team: int, gesture: int, meaning: int) -> void:
	if not is_instance_valid(table):
		return
	var at: Variant = table.get("_result_at")
	var when: float = at if at is float and at < INF else _now()
	var line := ""
	if reader_team == _my_team():
		_flash[gesture] = when
		line = "Cracked it! When the rivals %s, it means \"%s\"." % [DOING[gesture], TableTalk.MEANINGS[meaning]]
	else:
		line = "The rivals have figured out your \"%s\"." % TableTalk.GESTURES[gesture].to_lower()
	if table.has_method("_say"):
		table.call("_say", line, (CREW if reader_team == _my_team() else RIVAL).darkened(0.3), when)


func _process(_delta: float) -> void:
	if match_:
		queue_redraw()


func _draw() -> void:
	if match_ == null or not match_.interception.enabled or table.get("_help_open"):
		return
	var now := _now()
	_draw_code_panel(Rect2(4, 4, 196, 56), now)
	if not table.has_method("_seat_geom"):
		return
	var bubble_ends := {}  ## seat -> right edge of its bubble, so eyes sit beside it
	for seat: int in _bubbles:
		var since: float = now - _bubbles[seat][2]
		if since >= 0.0 and since < BUBBLE_TIME:
			bubble_ends[seat] = _draw_bubble(seat, _bubbles[seat][0], _bubbles[seat][1])
	for seat: int in _eyes:
		var since: float = now - _eyes[seat][1]
		if since >= 0.0 and since < EYES_TIME and fmod(since, 0.3) < 0.22:
			_draw_watching(seat, _eyes[seat][0], bubble_ends.get(seat, -1.0))
	for seat: int in _fakes:
		if now - _fakes[seat] < BUBBLE_TIME:
			var geom: Dictionary = table.call("_seat_geom", seat)
			var badge: Rect2 = geom["badge"]
			_tag(Vector2(badge.end.x + 4, badge.position.y - 14), "for show", GOLD)


## A rival's noticed signal: left-aligned over its name plate, clear of the
## dealer's eyes at the plate's right end. Returns its right edge.
func _draw_bubble(seat: int, text: String, understood: bool) -> float:
	var geom: Dictionary = table.call("_seat_geom", seat)
	var badge: Rect2 = geom["badge"]
	var w := UiFont.small().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, S).x + 16
	var r := Rect2(Vector2(clampf(badge.position.x, 2, size.x - w - 2), badge.position.y - 14).floor(), Vector2(w, 11))
	draw_rect(r.grow(1), RIVAL)
	draw_rect(r, PixelFrame.CREAM)
	draw_rect(Rect2(Vector2(r.position.x + 10, r.end.y + 1), Vector2(3, 2)), RIVAL)
	_eye(r.position + Vector2(3, 4), RIVAL)
	_label(r.position + Vector2(12, 8), text, PixelFrame.INK if understood else PixelFrame.INK_SOFT)
	return r.end.x


## A rival who caught one of your crew's signals: its eyes, and "!" if it
## knew what it meant. Beside the seat's own bubble if it has one up
## (`after`: that bubble's right edge).
func _draw_watching(seat: int, understood: bool, after: float) -> void:
	var geom: Dictionary = table.call("_seat_geom", seat)
	var badge: Rect2 = geom["badge"]
	var x := after + 3 if after >= 0.0 else badge.position.x
	var r := Rect2(Vector2(x, badge.position.y - 14), Vector2(22, 11))
	draw_rect(r, PANEL)
	draw_rect(r, RIVAL, false)
	_eye(r.position + Vector2(3, 4), GOLD)
	_eye(r.position + Vector2(8, 4), GOLD)
	_label(r.position + Vector2(15, 8), "!" if understood else "?", GOLD)


## What you've learned of the rival crew's code, and they of yours.
func _draw_code_panel(r: Rect2, now: float) -> void:
	var rival := _rival_team()
	if rival < 0:
		return
	var itc := match_.interception
	PixelFrame.panel(self, r, PixelFrame.CREAM, RIVAL)
	var at := r.position + Vector2(6, 10)
	var theirs := itc.book.learned(itc.crew_id(_my_team()), itc.crew_id(rival))
	_label(at, "Their code: %d cracked" % theirs.size(), PixelFrame.INK)
	for g in 4:
		var cell := at + Vector2((g % 2) * 92, 10 + (g / 2) * 9)
		var lit: bool = _flash.has(g) and now >= _flash[g] and now - _flash[g] < FLASH_TIME
		if lit and fmod(now - _flash[g], 0.3) < 0.2:
			draw_rect(Rect2(cell - Vector2(2, 7), Vector2(90, 9)), GOLD)
		var meaning: String = SHORT_MEANINGS[theirs[g]] if theirs.has(g) else "?"
		_label(cell, "%s: %s" % [SHORT_GESTURES[g], meaning], PixelFrame.INK if theirs.has(g) else PixelFrame.INK_SOFT)
	var yours := itc.book.learned(itc.crew_id(rival), itc.crew_id(_my_team()))
	var known: Array[String] = []
	for g: int in yours:
		known.append(SHORT_GESTURES[g])
	_label(at + Vector2(0, 30), ("They know your " + ", ".join(known)) if known else "They know none of yours", RIVAL.darkened(0.2))
	_label(at + Vector2(0, 39), "LB/Shift + signal: a fake", PixelFrame.INK_SOFT)


func _eye(at: Vector2, color: Color) -> void:
	draw_rect(Rect2(at + Vector2(0, 1), Vector2(4, 2)), color)
	draw_rect(Rect2(at + Vector2(1, 0), Vector2(2, 4)), color)
	draw_rect(Rect2(at + Vector2(1, 1), Vector2(2, 2)), PixelFrame.INK)


func _tag(at: Vector2, text: String, color: Color) -> void:
	var w := UiFont.small().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, S).x + 6
	var r := Rect2(at.floor(), Vector2(w, 11))
	draw_rect(r, PANEL)
	draw_rect(r, color, false)
	_label(r.position + Vector2(3, 8), text, color)


func _label(pos: Vector2, text: String, color: Color) -> void:
	draw_string(UiFont.small(), pos.floor(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, S, color)
