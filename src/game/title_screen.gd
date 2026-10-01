extends Control
## The title: Continue (when there's a save) or New game. Starting over when
## a save exists asks first, since the game only has one slot.
##
## The backdrop is the demo's six species around a felt table, drawn with
## the overworld's placeholder painter, until there's title art (the
## painting the game is named after is the obvious reference).
##
## Dev flags: --new or --continue skip straight to the overworld (see
## src/game/game.gd for the rest).

var _options: Array[String] = []
var _cursor := 0
var _confirming := false
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Game.dev_args.has("new"):
		Game.new_game()
		Game.goto_world.call_deferred()
		return
	if Game.dev_args.has("continue") and Game.continue_game():
		Game.goto_world.call_deferred()
		return
	_build_options()


func _build_options() -> void:
	_options.clear()
	if Game.has_save():
		_options.append("Continue")
	_options.append("New game")
	_cursor = 0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var d := UiKit.menu_dir(event)
	if d.y != 0:
		_cursor = wrapi(_cursor + d.y, 0, 2 if _confirming else _options.size())
	elif UiKit.accept(event):
		_choose()
	elif event.is_action_pressed("ui_cancel") and _confirming:
		_confirming = false
		_cursor = _options.find("New game")
	else:
		return
	get_viewport().set_input_as_handled()


func _choose() -> void:
	if _confirming:
		if _cursor == 0:
			_start_new()
		else:
			_confirming = false
			_cursor = _options.find("New game")
		return
	match _options[_cursor]:
		"Continue":
			if Game.continue_game():
				Game.goto_world()
		"New game":
			if Game.has_save():
				_confirming = true
				_cursor = 1  # "No" first: starting over should take a deliberate press
			else:
				_start_new()


func _start_new() -> void:
	Game.new_game()
	Game.goto_world()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.BG)
	var cx := size.x / 2
	# A lamp-lit table, the six species sat round it.
	var c := Vector2(cx, 236)
	_ellipse(c, Vector2(150, 50), Color("4a3424"))
	_ellipse(c, Vector2(142, 44), Color("2b5b3a"))
	_ellipse(Vector2(cx, 120), Vector2(260, 120), Color(1, 0.85, 0.5, 0.04))
	var species := Species.ids()
	for i in species.size():
		var a := PI + TAU * (i + 0.5) / species.size()
		var p := c + Vector2(cos(a) * 170, sin(a) * 62) - Vector2(16, 26)
		var bob := sin(_t * 2.0 + i) * 1.0 if i % 2 == 0 else 0.0
		Critter.paint(self, String(species[i]), Vector2i.DOWN, p + Vector2(0, bob), 2.0)
	for k in 3:
		_card(c + Vector2(-34 + k * 24, -12))
	UiKit.text(self, Vector2(cx, 62), "A Friend in Need", 32, UiKit.GOLD, 1)
	UiKit.text(self, Vector2(cx, 84), "a team hold'em adventure", 10, UiKit.QUIET, 1)
	# Menu.
	var items := _options if not _confirming else ["Yes, start over", "No"]
	var top := 312.0
	if _confirming:
		UiKit.text(self, Vector2(cx, top - 6), "Start over? Your saved game will be replaced.", 10, UiKit.HOT, 1)
		top += 10
	for i in items.size():
		var y := top + i * 18
		var selected := i == _cursor
		UiKit.text(self, Vector2(cx, y), items[i], 16 if selected else 10, UiKit.TEXT if selected else UiKit.QUIET, 1)
		if selected:
			var w := UiKit.text_width(items[i], 16)
			var tip := Vector2(cx - w / 2 - 14, y - 10)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(0, 10), tip + Vector2(6, 5)]), UiKit.GOLD)
	UiKit.text(self, Vector2(cx, size.y - 8), "A / Enter: choose", 8, UiKit.QUIET, 1)


func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, color)


func _card(at: Vector2) -> void:
	draw_rect(Rect2(at, Vector2(20, 28)), Color("f4ecd8"))
	draw_rect(Rect2(at + Vector2(2, 2), Vector2(16, 24)), Color("a8483a"), false)
