extends TestCase
## SpriteBank: missing art means placeholders (null), and a character strip
## is cut to its first 16px frame, so whatever the art pass delivers (single
## frames or strips, 16x16 or 16x24) draws one standing figure.


func test_missing_art_falls_back_to_placeholders() -> void:
	check_eq(SpriteBank.character("no_such_animal"), null)
	check_eq(SpriteBank.tile("no_such_tile"), null)


func test_character_region_takes_the_first_frame_of_a_strip() -> void:
	var single := ImageTexture.create_from_image(Image.create(16, 24, false, Image.FORMAT_RGBA8))
	check_eq(SpriteBank.character_region(single), Rect2(0, 0, 16, 24))
	var square := ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGBA8))
	check_eq(SpriteBank.character_region(square), Rect2(0, 0, 16, 16))
	var strip := ImageTexture.create_from_image(Image.create(64, 24, false, Image.FORMAT_RGBA8))
	check_eq(SpriteBank.character_region(strip), Rect2(0, 0, 16, 24))


func test_every_tile_and_character_has_a_placeholder() -> void:
	for ch: String in WorldMap.TILES:
		check(WorldMap.TILES[ch][0] is String, "tile %s has a name" % ch)
	for id: StringName in Species.ids():
		check(Critter.LOOKS.has(String(id)), "%s has placeholder colours" % id)
	for map_id: String in WorldMap.ids():
		for n: Dictionary in WorldMap.get_map(map_id).npcs:
			check(Critter.LOOKS.has(n["sprite"]), "%s has placeholder colours" % n["sprite"])
