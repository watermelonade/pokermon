extends SceneTestCase
## Scratch (not committed): screenshots of the street game under xvfb.

const OUT := "/tmp/claude-0/agents5/street/"

func _shot(name: String) -> void:
	await frames(2)
	var img := tree.root.get_viewport().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("shot ", OUT + name + ".png")


func test_zz_shots() -> void:
	timeout_s = 2000.0
	var found := street_game_npcs()
	var npc: Dictionary = found[0][1]
	for n: Array in found:
		if n[1]["id"] == "street_gander":
			npc = n[1]
	# The refusal: $200.
	var s := demo_state_at(WorldMap.START_MAP, WorldMap.START_CELL)
	s.money = 200
	await continue_from(s)
	await advance(20.0, "cancel")
	await talk_to(npc["id"])
	for _i in 30:
		if dialog_open() and "empty pockets" in dialog_line().to_lower():
			break
		if dialog_open():
			await press("ui_accept")
		await frames(5)
	await seconds(2.0)
	await _shot("street_refused")
	await advance(20.0, "cancel")
	# Broke: the offer.
	s = demo_state_at(WorldMap.START_MAP, WorldMap.START_CELL)
	s.money = 0
	await continue_from(s)
	await advance(20.0, "cancel")
	await _shot("sootbridge_street_game")
	game.dev_args["autoplay"] = ""
	game.dev_args["seed"] = "11"
	await talk_to(npc["id"])
	await advance(20.0, "stop")
	await seconds(0.5)
	await _shot("street_offer")
	await choose_index(0)
	await came_true(at_table, 10.0)
	await seconds(1.5)
	await _shot("street_table_start")
	await came_true(func() -> bool: return table_hand() >= 2 and table_flow() == FLOW_HUMAN or (table() != null and int(table().get("match_").get("table").get("board").size()) >= 3), 120.0)
	await seconds(1.0)
	await _shot("street_mid_hand")
	await wait_for_hand_done(3, 300.0)
	await press("menu")
	await seconds(0.6)
	await _shot("street_leave_prompt")
	await press("ui_accept")
	await came_true(func() -> bool: return dialog_open(), 20.0)
	await seconds(2.0)
	await _shot("street_after_leaving")
	await advance(20.0, "cancel")
