class_name WorldMap
extends RefCounted
## One overworld map: its tiles, written as text so a map can be read and
## edited in a diff, plus what stands on it (rival crews, townsfolk, signs,
## doors, and since demo 2 cards lying about and gates). The demo starts in
## Sootbridge (with its washhouse), takes the Mill Road east, and comes into
## Mossbank and Ridge Road (one long outdoor map, so walking out of town is
## seamless) on its west side; Mossbank has three interiors.
##
## Tiles are 16x16, one character each (legend in TILES). Pure data and
## queries, no nodes: line of sight, where a crew walks to meet you and
## whether the road can be walked are all tested headless
## (tests/test_world_map.gd), and the map test checks every row is the same
## width and that everything stands where it can stand.
##
## Rival crews stand side by side: the leader on `cell`, facing `facing`,
## the others at its shoulders (a boss crew's extras further out). Only the leader looks: anything on the
## `sight` cells in front of it, up to the first wall or body, gets
## challenged, like trainers in Pokemon. A crew with sight 0 (the
## tournament's) waits to be talked to. Crews are placed so that the first
## and third can't be walked around and the other two can, with care.

const TILE := 16
const START_MAP := "sootbridge"
const START_CELL := Vector2i(12, 5)  ## by the open manhole, where the dog wakes
const HEAL_MAP := "diner"
const HEAL_CELL := Vector2i(5, 3)  ## facing the cook across the counter

## char -> [name, walkable]. The name is also the art file:
## res://assets/tiles/<name>.png (see SpriteBank).
const TILES := {
	".": ["grass", true],
	",": ["flowers", true],
	";": ["tall_grass", true],
	"=": ["path", true],
	"T": ["tree", false],
	"~": ["water", false],
	"F": ["fence", false],
	"R": ["roof", false],
	"#": ["wall", false],
	"w": ["window", false],
	"D": ["door", true],
	"d": ["door_shut", false],
	"S": ["sign", false],
	"_": ["floor", true],
	"W": ["inner_wall", false],
	"C": ["counter", false],
	"t": ["felt", false],
	"b": ["bed", false],
	"p": ["plant", false],
	"X": ["mat", true],
	":": ["cobble", true],
	"B": ["brick", false],
	"o": ["manhole", false],
	"g": ["gate", true],  ## walkable: the overworld refuses it while the deck is short (see gate_at)
	"x": ["crate", false],
	"u": ["washtub", false],
}

## Mossbank's open table (docs/DEMO_SPEC.md W-TABLE): a street game anyone
## can sit at, one npc entry per player standing round the felt, each
## carrying this same dictionary (OpenTable.play reads it). Sage and Bandit
## play here until your first sit, then join you (GameState.OPEN_TABLE_CREW);
## five players so the three left after that still make a game (CashMatch
## wants two rivals at least).
const OPEN_TABLE := {
	"id": "mossbank_open_table", "buy_in": OPEN_TABLE_BUY_IN, "dealer": Dealer.Kind.STREET,
	"players": [[&"owl", 0], [&"raccoon", 0], [&"goose", 3], [&"possum", 2], [&"cat", 3]],
}
const OPEN_TABLE_BUY_IN := 100

## Sootbridge's street game (demo 2.1, docs/DEMO_SPEC.md W-STREET): three
## townsfolk playing for pennies on an upturned crate outside the Lamp.
## No buy-in: they front you `stake` chips and you keep what's above it
## when you get up (OpenTable, CashMatch.cash_out_staked), and only a dog
## with less than the open table's buy-in may sit (`max_money`): it's the
## way back for a dog that lost its wallet before it had a crew, not a
## second income. The players are the three individuals no crew or table
## had yet (Pip the owl, Scraps the raccoon, Gander the goose: a Rock, a
## Bluffer and a Maniac), so none of them can ever be in your crew.
##
## The stake and the blinds are tuned on the pace (tools/cash_sim.gd
## --street, README "Measured so far"): from $0 back to the buy-in in
## about 10-15 minutes, a bot in your seat, at about 20 s a hand. At the
## open table's depth (50 big blinds: a 50 stake at 1/2) it took a median
## 74 hands, about 25 minutes, and a bigger stake at the same depth only
## got there by paying in a few big lumps (200 at 2/4: median 41 hands but
## a tenth of runs done in 7). Shallow is what works: you keep what's above
## the stake and owe nothing below it, so every all-in is a free roll, and
## at 10 big blinds the pennies come in often and small. 60 at 3/6: median
## 39 hands (13 minutes; 4-26 for the middle 80%) on 400 runs of seeds the
## tuning never saw.
const STREET_GAME := {
	"id": "sootbridge_street_game", "stake": 60, "blinds": [3, 6], "max_money": OPEN_TABLE_BUY_IN, "dealer": Dealer.Kind.STREET,
	"players": [[&"owl", 3], [&"raccoon", 3], [&"goose", 2]],
}


const MAPS := {
	# Demo 2's first town (docs/DEMO_SPEC.md): soot-stained terraces on a
	# canal, the street where the dog wakes by the open manhole, and the
	# gate east to the Mill Road. The four Aces are found four ways: one in
	# the gutter in plain sight, one inside the washhouse, one at the dead
	# end of the coal yard's alley (behind the crates), one given by Mags.
	# Outside the Lamp, three townsfolk play for pennies on a crate: the
	# street game (STREET_GAME, demo 2.1), for a dog with empty pockets.
	"sootbridge": {
		"outdoor": true,
		"rows": [
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
			"TTRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRBTTTTT",
			"TTRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRBTTTTT",
			"TTBwBDBBwBBBwBBdBBwBBwBdBwwBdBwBBBBTTTTT",
			"T:::::::::::::::::::::::::::::::::g::::T",
			"T:::::::::::::::::::::::::::::::::g::::T",
			"T:::::::::::o:::::::x:::::::::::::BTTTTT",
			"T:::::::S:::::::::::::::::::::::::BTTTTT",
			"TFFFFFFFFFFF::FFFFFFFFFFFFFFFFFFFFBTTTTT",
			"T~~~~~~~~~~~::~~~~~~~~~~~~~~~~~~~~BTTTTT",
			"T~~~~~~~~~~~::~~~~~~~~~~~~~~~~~~~~BTTTTT",
			"TFFFFFFFFFFF::FFFFFFFFFFFFFFFFFFFFBTTTTT",
			"T::::::::::::::::::;x.............BTTTTT",
			"T...........:.........xxxxxxxxxxxxBTTTTT",
			"T..RRRRRR...:..........xx....xx...BTTTTT",
			"T..RRRRRR...:....,.....xx....xx...BTTTTT",
			"T..BwBdBB...:.....................BTTTTT",
			"T...........::::::::::::::::::::..BTTTTT",
			"T..,,.......:..........xx....xx...BTTTTT",
			"T..,,...TT..:..........xx....xx...BTTTTT",
			"T.......TT........................BTTTTT",
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
		],
		"labels": [
			{"rect": Rect2i(2, 1, 8, 2), "text": "WASHHOUSE"},
			{"rect": Rect2i(11, 1, 9, 2), "text": "THE LAMP"},
		],
		"warps": [
			{"cell": Vector2i(5, 3), "to": "washhouse", "to_cell": Vector2i(5, 6), "facing": Vector2i.UP},
			{"cell": Vector2i(38, 4), "to": "mill_road", "to_cell": Vector2i(2, 5), "facing": Vector2i.RIGHT},
			{"cell": Vector2i(38, 5), "to": "mill_road", "to_cell": Vector2i(2, 6), "facing": Vector2i.RIGHT},
		],
		"gates": [
			{"cells": [Vector2i(34, 4), Vector2i(34, 5)], "requires": "full_deck",
				"text": "The gate out of town. You can't leave. Not without the Aces."},
		],
		"pickups": [
			{"id": "ace_gutter", "cell": Vector2i(18, 7), "card": 51},  # As: in plain sight
			{"id": "ace_coal_yard", "cell": Vector2i(33, 12), "card": 48},  # Ac: the alley's dead end
		],
		"signs": [
			{"cell": Vector2i(8, 7), "text": "SOOTBRIDGE. Mind the drains. The council will fix that manhole cover. Soon."},
		],
		"npcs": [
			{"id": "mags", "name": "Mags", "sprite": "possum", "cell": Vector2i(5, 12), "facing": Vector2i.DOWN, "lines": [
				"Mags. I keep the drains. Don't look at me like that, it's honest work.",
				"Found this in my grate at dawn. A card. Smells of him. Of the Lamp's beer.",
				"Here. It's more yours than his, I reckon. Go careful, dog."],
				"gives_card": {"id": "ace_mags", "card": 50},  # Ah
				"after": ["The drains run all over town, dog. What goes down comes up somewhere."]},
			{"id": "ash", "name": "Ash", "sprite": "cat", "cell": Vector2i(17, 4), "facing": Vector2i.DOWN, "lines": [
				"You're his dog. The one he shouted at. ...He's not shouting now, is he?",
				"I won't say sorry. I'll say: the coal yard. Something shines behind the crates."]},
			{"id": "cinder", "name": "Cinder, the sweep", "sprite": "npc_kid", "cell": Vector2i(26, 7), "facing": Vector2i.UP, "lines": [
				"They're not opening the manhole. Too deep, the constable says. Too late.",
				"Mum says the drains run under half the town. Even under the washhouse."]},
			# The street game round its crate outside the Lamp: one entry per
			# player, all carrying STREET_GAME (OpenTable.play reads it).
			{"id": "street_pip", "name": "Pip", "sprite": "owl", "cell": Vector2i(20, 5), "facing": Vector2i.DOWN,
				"open_table": STREET_GAME, "animal": [&"owl", 3], "lines": [
				"We heard about last night. Sit, if your pockets are empty. We stake you."]},
			{"id": "street_scraps", "name": "Scraps", "sprite": "raccoon", "cell": Vector2i(21, 6), "facing": Vector2i.LEFT,
				"open_table": STREET_GAME, "animal": [&"raccoon", 3], "lines": [
				"*psst* our chips, your paws. win and you keep the extra. lose and, eh."]},
			{"id": "street_gander", "name": "Gander", "sprite": "goose", "cell": Vector2i(19, 6), "facing": Vector2i.RIGHT,
				"open_table": STREET_GAME, "animal": [&"goose", 2], "lines": [
				"HONK. PENNIES ON THE CRATE. THE CRATE IS MINE. THE PENNIES ARE ANYONE'S."]},
		],
		"crews": [],
	},
	"washhouse": {
		"outdoor": false,
		"rows": [
			"WWWWWWWWWWWW",
			"W_uu_uu_uu_W",
			"W__________W",
			"W__________W",
			"WCCCC______W",
			"W__________W",
			"W_______p__W",
			"W____XX____W",
			"WWWWWWWWWWWW",
		],
		"labels": [],
		"warps": [
			{"cell": Vector2i(5, 7), "to": "sootbridge", "to_cell": Vector2i(5, 4), "facing": Vector2i.DOWN},
			{"cell": Vector2i(6, 7), "to": "sootbridge", "to_cell": Vector2i(5, 4), "facing": Vector2i.DOWN},
		],
		"pickups": [
			{"id": "ace_washhouse", "cell": Vector2i(10, 2), "card": 49},  # Ad: up the floor drain
		],
		"signs": [],
		"npcs": [
			{"id": "nell", "name": "Nell", "sprite": "npc_cook", "cell": Vector2i(7, 3), "facing": Vector2i.DOWN, "lines": [
				"Out, dog, I've just mopped. ...Oh. You're his. I heard.",
				"Something came up my floor drain this morning. A card. It's by the tubs."]},
		],
		"crews": [],
	},
	# The road between the towns: short, a couple of folk on it, no crews
	# (the dog has none to play them with yet).
	"mill_road": {
		"outdoor": true,
		"rows": [
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
			"TTTTT......TTTTT.....RRRRRR.....TTTTTTTT",
			"TTT.........,,.......RRRRRR.........TTTT",
			"TT...;;;.............#w#d#w....S......TT",
			"TT...;;;..........................,,..TT",
			"T======================================T",
			"T======================================T",
			"TT.........,,,...............;;;.....TTT",
			"TT....TTT...............,,,.........TTTT",
			"TTTT....TTTT......TTTTT......TTTT...TTTT",
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
		],
		"labels": [
			{"rect": Rect2i(21, 1, 6, 2), "text": "OLD MILL"},
		],
		"warps": [
			{"cell": Vector2i(1, 5), "to": "sootbridge", "to_cell": Vector2i(37, 4), "facing": Vector2i.LEFT},
			{"cell": Vector2i(1, 6), "to": "sootbridge", "to_cell": Vector2i(37, 5), "facing": Vector2i.LEFT},
			{"cell": Vector2i(38, 5), "to": "town", "to_cell": Vector2i(2, 11), "facing": Vector2i.RIGHT},
			{"cell": Vector2i(38, 6), "to": "town", "to_cell": Vector2i(2, 12), "facing": Vector2i.RIGHT},
		],
		"signs": [
			{"cell": Vector2i(31, 3), "text": "THE MILL ROAD. West: Sootbridge. East: Mossbank. Mind the geese."},
		],
		"npcs": [
			{"id": "flint", "name": "Flint, a carter", "sprite": "npc", "cell": Vector2i(10, 7), "facing": Vector2i.UP, "lines": [
				"Sootbridge behind you, Mossbank ahead. Nothing between but the mill and me.",
				"There's a card table in Mossbank, out on the street. Anyone can sit. Even you."]},
			{"id": "hedda", "name": "Hedda", "sprite": "npc_badger", "cell": Vector2i(30, 4), "facing": Vector2i.DOWN, "lines": [
				"The mill's been shut for years. The wheel still turns. Nobody knows why.",
				"You look like you've had a night. Mossbank's kind to strays. Mostly."]},
		],
		"crews": [],
	},
	"town": {
		"outdoor": true,
		"rows": [
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
			"TT................................TTTTTTTTTTTTTT...............,,,.........TTTTTTTTTTTTTTTTTTTTTTTTT",
			"TT..RRRRRRRR...RRRRRRR...RRRRRR...TTTTTTTTTTTTTT...............,,,.........TTTTTTTTTTT............TT",
			"TT..RRRRRRRR...RRRRRRR...RRRRRR...TTTTTTTTTTTTTT...........................TTTTTTTTTTT............TT",
			"TT..RRRRRRRR...RRRRRRR...RRRRRR...TTTTTTTTTTTTTT...====================....TTTTTTTTTTT..RRRRRRRRR.TT",
			"TT..#w#D##w#...#wDw#w#...#wd#w#...TTTTTTTTTTTTTT...====================....TTTTTTTTTTT..RRRRRRRRR.TT",
			"TT.....=.S.......=.........=......TTTTTTTTTTTTTT...==...;;;;;;;......==....TTTTTTTTTTT..RRRRRRRRR.TT",
			"TT.....=,,...,...=....,....=......TT...............==...;;;;;;;......==....TTTTTTTTTTT..RRRRRRRRR.TT",
			"TT.....=.........=.....,...=.......................==;;;TTTTTTTTTTT..==..T.TTTTTTTTTTT..#w#wDw#w#.TT",
			"TT.....=.........=.........=...S...................==;;;TTTTTTTTTT...==....TTTTTTTTTTT......=.....TT",
			"T====================================================;;;TTTTTTTTTT...==....TTTTTTTTTTT......=.....TT",
			"T====================================================...TTTTTTTTTT...==....TTTTTTTTTTT....,.=.,...TT",
			"TT........................S...........;;;;;..;;;........TTTTTTTTTT;;.==....TTTTTTTTTTT......=.....TT",
			"TT....................................;;;;;..;;;........TTTTTTTTTT;;.==..................,..=..,..TT",
			"TT...~~~~...,,,,,,,...FFFFFFFFF...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT;;.==.....................=.....TT",
			"TT..~~~~~~..,,,,,,,...F,,,,,,,F...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT;;.==.................S...=.....TT",
			"TT..~~~~~~....tt......F,,,,,,,F...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT...=============================TT",
			"TT..~~~~~~....tt......F,,,,,,,F...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT...=============================TT",
			"TT...~~~~...S,,,,,....F,,,,,,,F...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT................................TT",
			"TT...........,,,,,....FFFFFFFFF...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT......,,,,....;;;;;.............TT",
			"TT................................TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT...,,,,....;;;;;.............TT",
			"TT................................TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
		],
		"labels": [
			{"rect": Rect2i(4, 3, 8, 3), "text": "DINER"},
			{"rect": Rect2i(15, 3, 7, 3), "text": "HOME"},
			{"rect": Rect2i(25, 3, 6, 3), "text": "SHOP"},
			{"rect": Rect2i(88, 5, 9, 4), "text": "TOURNAMENT HALL"},
		],
		"warps": [
			{"cell": Vector2i(7, 6), "to": "diner", "to_cell": Vector2i(6, 7), "facing": Vector2i.UP},
			{"cell": Vector2i(17, 6), "to": "home", "to_cell": Vector2i(4, 6), "facing": Vector2i.UP},
			{"cell": Vector2i(92, 9), "to": "hall", "to_cell": Vector2i(9, 10), "facing": Vector2i.UP},
			{"cell": Vector2i(1, 11), "to": "mill_road", "to_cell": Vector2i(37, 5), "facing": Vector2i.LEFT},
			{"cell": Vector2i(1, 12), "to": "mill_road", "to_cell": Vector2i(37, 6), "facing": Vector2i.LEFT},
		],
		"signs": [
			{"cell": Vector2i(9, 7), "text": "ROSIE'S DINER. Pie, coffee, booths. Lose on the road? You'll wake up here."},
			{"cell": Vector2i(31, 10), "text": "EAST: Ridge Road, then the Tournament Hall. Mostly Ridge Road. Lots of it."},
			{"cell": Vector2i(26, 13), "text": "MOSSBANK. Population 212. Squirrels, please stop counting yourselves twice."},
			{"cell": Vector2i(27, 6), "text": "SHOP. Closed for the Mossbank Open. The shopkeeper entered. Wish her luck."},
			{"cell": Vector2i(88, 16), "text": "MOSSBANK TOURNAMENT HALL. Tonight: the Mossbank Open. Dealer: Lou. Lou: asleep."},
			{"cell": Vector2i(12, 19), "text": "OPEN TABLE. Anyone may sit. $100 buy-in. Leave whenever you like."},
		],
		"npcs": [
			{"id": "bertram", "name": "Old Bertram", "sprite": "npc_badger", "cell": Vector2i(30, 9), "facing": Vector2i.DOWN, "lines": [
				"Ridge Road, eh? Crews line it like crows on a fence. Nobody gets by for free.",
				"Step into a crew's sight and they'll deal you in. Win, and one might join you.",
				"Press Start (or Tab) and pick Crew to choose which two animals sit with you.",
				"I played that road forty years. Lost my shirt twice. Won it back once."]},
			{"id": "kid", "name": "Juniper, age 9", "sprite": "npc_kid", "cell": Vector2i(12, 13), "facing": Vector2i.UP, "lines": [
				"Lou the dealer has been asleep since before I was born. Mom says so.",
				"So in the hall you can signal your crew all you like! Nose! Ear! Hat!",
				"When I grow up I'm gonna have a crew of nine geese. Nine!"]},
			{"id": "tally", "name": "Tally, the census", "sprite": "squirrel", "cell": Vector2i(5, 9), "facing": Vector2i.DOWN, "lines": [
				"Two hundred and twelve! Two hundred and thirteen! Wait. Did I count me?",
				"A dog! Do dogs count? I'll count you. Two hundred and fourteen!"]},
			{"id": "dot", "name": "Dot", "sprite": "goose", "cell": Vector2i(20, 14), "facing": Vector2i.LEFT, "lines": [
				"HONK. THE TABLE BY THE POND IS OPEN TO ALL. EVEN DOGS. ESPECIALLY DOGS.",
				"THEY NEED A FOURTH. THEY ALWAYS NEED A FOURTH. GO ON. SIT."]},
			# The open table's players: one entry each, all carrying OPEN_TABLE;
			# "animal" says which player each one is, so whoever has joined you
			# stops standing here (the overworld hides them).
			{"id": "table_sage", "name": "Sage", "sprite": "owl", "cell": Vector2i(13, 17), "facing": Vector2i.RIGHT,
				"open_table": OPEN_TABLE, "animal": [&"owl", 0], "lines": [
				"Ah. A dog. Do sit, if you have the buy-in. We play for money, not pats."]},
			{"id": "table_bandit", "name": "Bandit", "sprite": "raccoon", "cell": Vector2i(16, 18), "facing": Vector2i.LEFT,
				"open_table": OPEN_TABLE, "animal": [&"raccoon", 0], "lines": [
				"*psst* fresh chips. i mean, hi. sit down, sit down."]},
			{"id": "table_waddles", "name": "Waddles", "sprite": "goose", "cell": Vector2i(15, 16), "facing": Vector2i.DOWN,
				"open_table": OPEN_TABLE, "animal": [&"goose", 3], "lines": [
				"DEAL THE DOG IN. DEAL EVERYONE IN. THIS IS MY TABLE NOW."]},
			{"id": "table_pudding", "name": "Pudding", "sprite": "possum", "cell": Vector2i(13, 18), "facing": Vector2i.RIGHT,
				"open_table": OPEN_TABLE, "animal": [&"possum", 2], "lines": [
				"Sit, if you like. I play slow. If I lose, I lie down for a bit. It's fine."]},
			{"id": "table_mittens", "name": "Mittens", "sprite": "cat", "cell": Vector2i(14, 19), "facing": Vector2i.UP,
				"open_table": OPEN_TABLE, "animal": [&"cat", 3], "lines": [
				"A dog at the table. How novel. Do try not to drool on the felt."]},
		],
		"crews": [
			{"id": "pond_hecklers", "name": "the Pond Hecklers", "cell": Vector2i(44, 8), "facing": Vector2i.DOWN, "sight": 6,
				"members": [[&"goose", 0], [&"squirrel", 0], [&"goose", 1]],
				"before": ["HONK! HALT! THIS IS OUR ROAD NOW. WE DECIDED THAT JUST NOW.",
					"NOBODY PASSES THE POND HECKLERS WITHOUT A HAND. SIT. DEAL. FEAR.",
					"(Nutmeg, the squirrel, holds their chips. In his cheeks. Mostly.)"],
				"after": "FINE. YOU WIN. WE'LL BE AT THE POND, HONKING ABOUT IT FOR WEEKS.",
				"reward": 120, "chips": 500, "dealer": Dealer.Kind.STREET},
			{"id": "alley_cats", "name": "the Alley Cats", "cell": Vector2i(48, 7), "facing": Vector2i.RIGHT, "sight": 4,
				"members": [[&"cat", 0], [&"cat", 1], [&"raccoon", 1]],
				"before": ["Oh. A human. With pets. How quaint.",
					"We weren't going to play today. It's warm. But fine. Don't be boring.",
					"(Behind her, the raccoon whispers \"psst, I have a plan.\" Nobody listens.)"],
				"after": "We let you win, obviously. Now move. You're standing in our sunbeam.",
				"reward": 150, "chips": 500, "dealer": Dealer.Kind.STREET},
			{"id": "nut_club", "name": "the Nut Club", "cell": Vector2i(60, 2), "facing": Vector2i.DOWN, "sight": 6,
				"members": [[&"squirrel", 1], [&"squirrel", 2], [&"squirrel", 3]],
				"before": ["HALT! Halt. Hi. Halt! This stretch of road belongs to the Nut Club!",
					"Toll's one game. Or one nut. No nut? Game it is! Sit sit sit!",
					"Club rule one: we call. Rule two: we always call. Rule three: snacks."],
				"after": "We called everything. EVERYTHING. Why didn't that work?!",
				"reward": 180, "chips": 500, "dealer": Dealer.Kind.STREET},
			{"id": "night_shift", "name": "the Night Shift", "cell": Vector2i(78, 15), "facing": Vector2i.DOWN, "sight": 5,
				"members": [[&"possum", 0], [&"owl", 1], [&"raccoon", 2]],
				"before": ["...", "Oh. You can see us. Most folks walk right past.",
					"We're the Night Shift. We play at night. It is not night. Deal quietly."],
				"after": "*flops over* I have died. Tell my mother I bluffed bravely. ...Shh.",
				"reward": 220, "chips": 500, "dealer": Dealer.Kind.STREET},
		],
	},
	"diner": {
		"outdoor": false,
		"rows": [
			"WWWWWWWWWWWWWW",
			"W____________W",
			"WCCCCCCCCC___W",
			"W____________W",
			"W____________W",
			"W_tt____tt___W",
			"W_tt____tt__pW",
			"Wp___________W",
			"W_____XX_____W",
			"WWWWWWWWWWWWWW",
		],
		"labels": [],
		"warps": [
			{"cell": Vector2i(6, 8), "to": "town", "to_cell": Vector2i(7, 7), "facing": Vector2i.DOWN},
			{"cell": Vector2i(7, 8), "to": "town", "to_cell": Vector2i(7, 7), "facing": Vector2i.DOWN},
		],
		"signs": [
			{"cell": Vector2i(13, 4), "text": "A painting: dogs playing cards. One slips an ace under the table. Did it just wink?"},
		],
		"npcs": [
			{"id": "rosie", "name": "Rosie", "sprite": "npc_cook", "cell": Vector2i(5, 1), "facing": Vector2i.DOWN, "lines": [
				"Sit a while, hon. Nobody leaves Rosie's hungry. Or broke. Well. Hungry.",
				"If a crew cleans you out, you'll wake up in that booth. Happens to everybody.",
				"And don't mind the painting. It came with the place."]},
		],
		"crews": [],
	},
	"home": {
		"outdoor": false,
		"rows": [
			"WWWWWWWWWW",
			"W_bb___p_W",
			"W_bb_____W",
			"W________W",
			"W___tt___W",
			"W___tt___W",
			"W________W",
			"W___XX___W",
			"WWWWWWWWWW",
		],
		"labels": [],
		"warps": [
			{"cell": Vector2i(4, 7), "to": "town", "to_cell": Vector2i(17, 7), "facing": Vector2i.DOWN},
			{"cell": Vector2i(5, 7), "to": "town", "to_cell": Vector2i(17, 7), "facing": Vector2i.DOWN},
		],
		"signs": [
			{"cell": Vector2i(4, 4), "text": "Your practice table. The felt has seen better days. So has the deck."},
			{"cell": Vector2i(5, 4), "text": "Your practice table. The felt has seen better days. So has the deck."},
		],
		"npcs": [],
		"crews": [],
	},
	"hall": {
		"outdoor": false,
		"rows": [
			"WWWWWWWWWWWWWWWWWWWW",
			"W__________________W",
			"W_p______________p_W",
			"W______tttttt______W",
			"W______tttttt______W",
			"W______tttttt______W",
			"W__________________W",
			"W__________________W",
			"W__________________W",
			"W__________________W",
			"W__________________W",
			"W________XX________W",
			"WWWWWWWWWWWWWWWWWWWW",
		],
		"labels": [],
		"warps": [
			{"cell": Vector2i(9, 11), "to": "town", "to_cell": Vector2i(92, 10), "facing": Vector2i.DOWN},
			{"cell": Vector2i(10, 11), "to": "town", "to_cell": Vector2i(92, 10), "facing": Vector2i.DOWN},
		],
		"signs": [
			{"cell": Vector2i(5, 0), "text": "HALL RULES: 1. No biting. 2. No cards in cheek pouches. 3. Do not wake Lou."},
		],
		"npcs": [
			{"id": "lou", "name": "Lou, the dealer", "sprite": "npc_dealer", "cell": Vector2i(9, 2), "facing": Vector2i.DOWN, "asleep": true, "lines": [
				"Zzz... ante up... zzz...",
				"Zzz... the House... always... zzz..."]},
		],
		"crews": [
			{"id": "mossbank_regulars", "name": "the Mossbank Regulars", "cell": Vector2i(9, 6), "facing": Vector2i.DOWN, "sight": 0,
				# A boss crew (BossTable): four against your three, Graves leading
				# on a big stack, the seat draw rigged around you.
				"members": [[&"possum", 3], [&"cat", 2], [&"owl", 2], [&"possum", 1]], "boss": true,
				"before": ["So. You're the one cleaning out Ridge Road. I'm Graves. I captain the Regulars.",
					"Four of us, same seats every Thursday since 1971. Tonight: either side of you.",
					"Lou's asleep, so signal all you like. We will. Our signals are older than you.",
					"Win the Open and the Mossbank bracelet is yours. You won't."],
				"after": "*keels over* ...I'm fine. Wear it well. The next town won't be so polite.",
				"reward": 500, "chips": 1000, "dealer": Dealer.Kind.ASLEEP, "bracelet": "mossbank", "tournament": true},
		],
	},
}

static var _cache := {}

var id := ""
var outdoor := true
var rows: PackedStringArray = []
var width := 0
var height := 0
var warps: Array = []
var signs: Array = []
var npcs: Array = []
var crews: Array = []
var labels: Array = []
var gates: Array = []
var _pickups: Array = []


static func ids() -> Array:
	return MAPS.keys()


static func get_map(map_id: String) -> WorldMap:
	if not _cache.has(map_id):
		assert(MAPS.has(map_id), "unknown map: %s" % map_id)
		var data: Dictionary = MAPS[map_id]
		var m := WorldMap.new()
		m.id = map_id
		m.outdoor = data["outdoor"]
		m.rows = PackedStringArray(data["rows"])
		m.height = m.rows.size()
		m.width = m.rows[0].length()
		m.warps = data["warps"]
		m.signs = data["signs"]
		m.npcs = data["npcs"]
		m.crews = data["crews"]
		m.labels = data["labels"]
		m.gates = data.get("gates", [])
		m._pickups = data.get("pickups", [])
		_cache[map_id] = m
	return _cache[map_id]


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


## The tile character; off the map is a tree outdoors and a wall inside.
func char_at(cell: Vector2i) -> String:
	if not in_bounds(cell):
		return "T" if outdoor else "W"
	return rows[cell.y][cell.x]


func tile_name(cell: Vector2i) -> String:
	return TILES.get(char_at(cell), ["grass", true])[0]


func tile_walkable(cell: Vector2i) -> bool:
	return TILES.get(char_at(cell), ["", false])[1]


func pixel_size() -> Vector2:
	return Vector2(width * TILE, height * TILE)


func warp_at(cell: Vector2i) -> Dictionary:
	for w: Dictionary in warps:
		if w["cell"] == cell:
			return w
	return {}


func sign_at(cell: Vector2i) -> String:
	for s: Dictionary in signs:
		if s["cell"] == cell:
			return s["text"]
	return ""


func crew_by_id(crew_id: String) -> Dictionary:
	for c: Dictionary in crews:
		if c["id"] == crew_id:
			return c
	return {}


# --- Demo 2: pickups, gates, the open table (docs/DEMO_SPEC.md) -----------------

## The cards lying on this map: [{"id", "cell", "card"}] from the map's
## "pickups" (all of them; which are taken is the run's business,
## GameState.taken_pickups). An Ace a townsperson gives is the npc entry's
## "gives_card" instead.
func pickups() -> Array:
	return _pickups


## The pickup lying on `cell` ({"id", "cell", "card"}), or {}.
func pickup_at(cell: Vector2i) -> Dictionary:
	for p: Dictionary in _pickups:
		if p["cell"] == cell:
			return p
	return {}


## The card behind a pickup id, on any map, a gift's included; -1 if no
## pickup has that id. Ids are unique across the maps (tests/test_demo_state).
static func pickup_card(pickup_id: String) -> int:
	for map_id: String in MAPS:
		var data: Dictionary = MAPS[map_id]
		for p: Dictionary in data.get("pickups", []):
			if p["id"] == pickup_id:
				return p["card"]
		for n: Dictionary in data["npcs"]:
			if n.has("gives_card") and n["gives_card"]["id"] == pickup_id:
				return n["gives_card"]["card"]
	return -1


## The gate covering `cell` ({"cells", "requires", "text"}), or {}. Gate
## cells are walkable tiles; whether you may step on one is the run's
## business (the overworld asks GameState.has_full_deck for "full_deck"),
## so the map and its paths stay the same whichever way the gate stands.
func gate_at(cell: Vector2i) -> Dictionary:
	for g: Dictionary in gates:
		if (g["cells"] as Array).has(cell):
			return g
	return {}


## The townsfolk on this map who sit at an open table: npc entries with an
## "open_table" ({"id", "buy_in", "players", "dealer"}).
func open_tables() -> Array:
	return npcs.filter(func(n: Dictionary) -> bool: return n.has("open_table"))


## Whether this townsperson has gone off with you: an open-table player
## ("animal": [species, individual]) who has joined your roster. They stop
## standing at home, like a recruit from a crew.
static func npc_joined(npc: Dictionary, state: GameState) -> bool:
	if not npc.has("animal") or state == null:
		return false
	var a: Array = npc["animal"]
	return state.has_animal(a[0], Species.individual(a[0], a[1]).name)


## Where a crew stands at home: the leader, then its two shoulders.
## Where each member stands at home: the leader on `cell`, then at its
## shoulders, then further out on alternate sides (a boss crew of four puts
## its fourth at the left shoulder's shoulder).
static func crew_cells(crew: Dictionary) -> Array[Vector2i]:
	var c: Vector2i = crew["cell"]
	var f: Vector2i = crew["facing"]
	var side := Vector2i(absi(f.y), absi(f.x))
	var out: Array[Vector2i] = [c]
	for k in range(1, (crew["members"] as Array).size()):
		out.append(c - side * ((k + 1) / 2) if k % 2 == 1 else c + side * (k / 2))
	return out


## The crew's animals, leader first. Their bond (how well they read each
## other's signals at the table) is the crew's `bond`, if it has one, else
## a stranger's 0.3.
static func crew_animals(crew: Dictionary) -> Array[Animal]:
	var out: Array[Animal] = []
	for m: Array in crew["members"]:
		out.append(Species.individual(m[0], m[1], crew.get("bond", 0.3)))
	return out


## Every cell a townsperson or crew member stands on at home (cell -> true).
func occupied_cells() -> Dictionary:
	var out := {}
	for n: Dictionary in npcs:
		out[n["cell"]] = true
	for c: Dictionary in crews:
		for cell in crew_cells(c):
			out[cell] = true
	return out


## Every cell someone stands on when this map loads, in the run `state`:
## the townsfolk, and every crew member who hasn't joined you (a recruit's
## spot is empty from then on). occupied_cells() is the same without a run.
func standing_cells(state: GameState) -> Dictionary:
	var out := {}
	for n: Dictionary in npcs:
		if not npc_joined(n, state):
			out[n["cell"]] = true
	for c: Dictionary in crews:
		var cells := crew_cells(c)
		var animals := crew_animals(c)
		for i in cells.size():
			if not state.has_animal(animals[i].species, animals[i].name):
				out[cells[i]] = true
	return out


## Where to stand you when a save puts you somewhere you can't be: `cell`
## itself if it's walkable and nobody in `taken` stands there, otherwise the
## nearest free cell (not a door) that can be walked to from the map's
## doors, so a fence next to the garden can't shut you inside it.
##
## It used to be "back to the start" for anything odd, meant for saves made
## before a map edit. But spots the map counts as taken are free in play:
## where a recruit stood, or a crew's home after it walked over to you. Quit
## there and Continue took you home to Mossbank, the whole road lost
## (found by tools/playtest.gd, which stands on such spots and continues).
func open_cell_near(cell: Vector2i, taken: Dictionary) -> Vector2i:
	if tile_walkable(cell) and not taken.has(cell):
		return cell
	var seen := {}
	var queue: Array[Vector2i] = []
	for w: Dictionary in warps:
		seen[w["cell"]] = true
		queue.append(w["cell"])
	var best := START_CELL if id == START_MAP else cell
	var best_distance := 1 << 30
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var distance := absi(c.x - cell.x) + absi(c.y - cell.y)
		if distance < best_distance and warp_at(c).is_empty():
			best = c
			best_distance = distance
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = c + d
			if seen.has(next) or taken.has(next) or not tile_walkable(next):
				continue
			seen[next] = true
			queue.append(next)
	return best


## The cells a crew leader can see: straight ahead, up to `distance`, until
## a tile that isn't walkable or anyone in `occupied` blocks the view.
## Tall grass doesn't hide you; this is poker, not hide and seek.
func view_cells(from: Vector2i, facing: Vector2i, distance: int, occupied := {}) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cell := from
	for k in distance:
		cell += facing
		if not tile_walkable(cell) or occupied.has(cell):
			break
		out.append(cell)
	return out


## The first unbeaten crew that can see `player_cell` from its home spot,
## or {}. Other crews and townsfolk block the view; the player's own
## followers don't (they walk behind). `party_size` is how many animals
## sit with you: a dog on its own (0) is nobody a crew would deal in, so
## nobody spots it (docs/DEMO_SPEC.md S-PARTY). The default (a full party)
## keeps every other caller as it was.
func spotter(player_cell: Vector2i, beaten: Dictionary, party_size := GameState.PARTY_SIZE) -> Dictionary:
	if party_size <= 0:
		return {}
	var occupied := occupied_cells()
	for c: Dictionary in crews:
		if c["sight"] <= 0 or beaten.has(c["id"]):
			continue
		if player_cell in view_cells(c["cell"], c["facing"], c["sight"], occupied):
			return c
	return {}


## The cells a leader at `from` walks through, along `facing`, to stand
## next to `target` (empty if it's already there).
static func approach_path(from: Vector2i, facing: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cell := from + facing
	while cell != target and out.size() < 64:
		out.append(cell)
		cell += facing
	return out


## Whether `to` can be walked to from `from` without stepping on `blocked`
## cells (cell -> true). For tests: the road must stay passable around
## crews that have been beaten.
func reachable(from: Vector2i, to: Vector2i, blocked := {}) -> bool:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while queue:
		var cell: Vector2i = queue.pop_front()
		if cell == to:
			return true
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + d
			if seen.has(next) or blocked.has(next) or not tile_walkable(next):
				continue
			seen[next] = true
			queue.append(next)
	return false
