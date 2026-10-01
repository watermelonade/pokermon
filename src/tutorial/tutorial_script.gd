class_name TutorialScript
extends RefCounted
## The tutorial match, as data: five set-up hands at Rosie's back table, one
## lesson each, and what Rosie says when. TableTutorial runs it at the table;
## tests/test_tutorial.gd plays every lesson headless and checks that each
## one produces its situation (the teammate signals, the raccoon bluffs the
## river with its tell showing, the dealer warns your crew...).
##
## Why scripted hands: a lesson that depends on the shuffle teaches nothing
## half the time. Each lesson fixes the button (so who acts before whom is
## known), every seat's hole cards and the board (dealt from Deck.stacked
## through TeamMatch.start_hand(stacked)), and how each animal plays
## (ScriptedBot policies). Your seat has a plan too: the play the coach
## suggests, which puts the menu cursor there, and which --autoplay follows.
## Every policy copes with any other play (you can raise when Rosie says
## fold), so a lesson can't get stuck; the coach's lines branch on what you
## did instead (`if`).
##
## Seats are the table's usual 3v3, alternating: 0 you, 1 Waddles the
## Goose, 2 your first animal, 3 Scraps the Raccoon, 4 your second animal,
## 5 Mittens the Cat. The rivals are Rosie's diner regulars, fixed, because
## the tell lesson needs a raccoon in seat 3; your teammates are whoever
## you've seated (their tells never fire here, and their plans don't depend
## on the species).
##
## Coach entries: {"on": event, ...filters, "if": condition, "lines": [...]}.
##   events: "hand_start"; "your_turn" (+ "street"); "acted" (+ "seat",
##   "action"); "hand_over". Each entry fires at most once a lesson, the
##   first time its event happens with its condition true.
##   conditions: you_raised, you_folded, not_folded, you_won, not_won,
##   you_signalled, facing_bet, not_facing_bet, tell_seen, no_tell.
##   lines: text, or {"text", "wait": "signal:0" | "signal:any"} for a line
##   that waits for you to signal (A has Rosie do it for you: on a Deck whose
##   back buttons aren't mapped yet, nobody gets stuck).
##   placeholders: {m2} {m4} your animals, {r1} {r3} {r5} Rosie's; {heat}
##   your crew's Heat, {next} what your next signal would add, {after} the
##   two together. Filled in when the line shows, so numbers are current.
##
## Lines follow docs/WRITING.md (on the writing branch): one box of about
## 76 characters (84 at most, with the longest names filled in) and no more
## than four boxes at a time; tests/test_tutorial.gd checks both, and that
## each fits the table's text box.

const COACH := "Rosie"
const COACH_SPRITE := &"npc_cook"
const CHIPS := 1000

## The rivals: [species, index] into Species.individual. The fourth of each
## kind, so none of them is a crew you meet (or recruit) on Ridge Road.
const RIVALS := [[&"goose", 3], [&"raccoon", 3], [&"cat", 3]]

const LESSONS := [
	{
		"id": "basics",
		"title": "The table",
		"button": 0,
		"dealer": Dealer.Kind.STREET,
		"hole": {0: "Ks Kh", 1: "9c 3d", 2: "8d 4s", 3: "Qd Js", 4: "6h 5c", 5: "Tc 3s"},
		"board": "Kd 7s 2h 9h 4c",
		"plans": {
			0: {"preflop": "raise_to:40", "default": "bet:0.6"},
			1: {"default": "fold"},
			2: {"default": "fold"},
			3: {"preflop": "call_upto:80", "default": "fold"},
			4: {"default": "fold"},
			5: {"default": "fold"},
		},
		"coach": [
			{"on": "hand_start", "lines": [
				"Welcome to my back table, hon! Practice only: nobody loses a thing. Not even pie.",
				"Teal's your crew: you, {m2} and {m4}. Rust is mine. Take their chips!",
				"It's hold'em: two cards each, five shared, best five cards win. Easy as pie.",
			]},
			{"on": "your_turn", "street": "preflop", "lines": [
				"Your cards are at the bottom. The gold words say what you hold: a pair of Kings!",
				"CALL matches the bet, RAISE bets more, FOLD gives up. HELP lists every button.",
				"Kings are big, so RAISE. A opens the amount, LB/RB changes it, A again bets it.",
			]},
			{"on": "acted", "seat": 2, "action": "fold", "if": "you_raised", "lines": [
				"See {m2} fold? Teammates never fight each other for chips. That's soft play.",
			]},
			{"on": "your_turn", "street": "flop", "lines": [
				"The flop: three shared cards, and one's a King. Three Kings! RAISE again, hon.",
			]},
			{"on": "hand_over", "if": "you_won", "lines": [
				"That's poker. Now for the part that makes it a team game.",
			]},
			{"on": "hand_over", "if": "not_won", "lines": [
				"Cards are cards. Chips reset every lesson, so no harm done. Now, teamwork.",
			]},
		],
	},
	{
		"id": "step_aside",
		"title": "A teammate's signal",
		"button": 1,
		"dealer": Dealer.Kind.STREET,
		"hole": {0: "Ad Jc", 1: "Ts 9s", 2: "7d 3c", 3: "6c 2s", 4: "Qh Qc", 5: "8c 4h"},
		"board": "Qs 8d 3h 2c Kd",
		"plans": {
			0: {"default": "fold"},
			1: {"preflop": "call_upto:60", "default": "fold"},
			2: {"default": "fold"},
			3: {"default": "fold"},
			4: {"preflop": "raise_to:30", "default": "bet:0.6"},
			5: {"default": "fold"},
		},
		"signals": {4: {"preflop": TableTalk.Sig.STRONG}},
		"coach": [
			{"on": "hand_start", "lines": [
				"Teammates can't see each other's cards. So crews cheat. Politely. With signals.",
				"Four secret gestures: back buttons on a Deck, 1 to 4 on keys. List's bottom left.",
				"No dealer at my table, so signal all you like. Now, watch {m4}.",
			]},
			{"on": "your_turn", "street": "preflop", "lines": [
				"{m4} touched a nose. That means \"I'm strong\". Then raised to 30.",
				"Your Ace-Jack's fine, but when a teammate's strong, you step aside: FOLD.",
				"Fight {m4} for it and the best you can win is chips your crew already has.",
			]},
			{"on": "hand_over", "if": "you_folded", "lines": [
				"{m4} takes it, and the chips stay in the crew. Stepping aside cost nothing.",
			]},
			{"on": "hand_over", "if": "not_folded", "lines": [
				"You fought {m4}. Chips won off a teammate were your crew's already, hon!",
			]},
		],
	},
	{
		"id": "your_signal",
		"title": "Your signal",
		"button": 2,
		"dealer": Dealer.Kind.STREET,
		"hole": {0: "Ah Ac", 1: "Kc Th", 2: "Kd Qd", 3: "7h 2c", 4: "8s 8d", 5: "9d 5c"},
		"board": "As 9c 4d Jh 3s",
		"plans": {
			0: {"preflop": "raise_to:40", "default": "bet:0.6"},
			1: {"preflop": "call_upto:60", "default": "fold"},
			2: {"preflop": "yield:call_upto:60", "default": "check_call"},
			3: {"default": "fold"},
			4: {"preflop": "yield:call_upto:60", "default": "check_call"},
			5: {"default": "fold"},
		},
		"coach": [
			{"on": "hand_start", "lines": [
				"Now you do the talking. Watch how your crew takes it.",
			]},
			{"on": "your_turn", "street": "preflop", "lines": [
				{"text": "Two Aces! Tell your crew: touch your nose. That's 1 (or L4 on a Deck).", "wait": "signal:0"},
				"There: \"I'm strong\". Now RAISE, and watch {m2} and {m4}.",
			]},
			{"on": "acted", "seat": 4, "action": "fold", "if": "you_signalled", "lines": [
				"{m2} and {m4} read you and folded hands they'd have played. Good crew.",
			]},
			{"on": "your_turn", "street": "flop", "lines": [
				"Three Aces, and only {r1} left. Bet it!",
			]},
			{"on": "hand_over", "lines": [
				"A signal's only as good as its reader. Better bond, better reads.",
			]},
		],
	},
	{
		"id": "tells",
		"title": "Tells",
		"button": 3,
		"dealer": Dealer.Kind.STREET,
		"hole": {0: "9h 9s", 1: "Jd 2c", 2: "Kc 4h", 3: "6c 5c", 4: "Td 3s", 5: "Jh 8d"},
		"board": "Qc 7d 4s 2h Ks",
		"plans": {
			0: {"default": "check_call"},
			1: {"default": "fold"},
			2: {"default": "fold"},
			3: {"preflop": "call_upto:40", "river": "bluff:1.5", "default": "check_call"},
			4: {"default": "fold"},
			5: {"default": "fold"},
		},
		"tell": {"seat": 3, "street": "river"},
		"coach": [
			{"on": "hand_start", "lines": [
				"Next, tells. Every kind of animal gives something away. Like me around pie.",
			]},
			{"on": "your_turn", "street": "preflop", "lines": [
				"A pair of 9s. Nothing fancy: CALL along, and keep an eye on my lot.",
			]},
			{"on": "your_turn", "street": "river", "if": "not_facing_bet", "lines": [
				"Last card. CHECK, and see what {r3} does.",
			]},
			{"on": "your_turn", "street": "river", "if": "facing_bet", "lines": [
				"Did you catch that? {r3} rubbed its paws. Raccoons do that when they bluff.",
				"Your 9s aren't much, but they beat a bluff. CALL!",
			]},
			{"on": "hand_over", "if": "you_won", "lines": [
				"{r3} had six-high! That tell won you the pot. Yours have tells too, mind.",
			]},
			{"on": "hand_over", "if": "not_won", "lines": [
				"{r3} had six-high: a bluff! Trust the paws next time. Yours have tells too.",
			]},
		],
	},
	{
		"id": "heat",
		"title": "Heat",
		"button": 4,
		"dealer": Dealer.Kind.STRICT,
		"hole": {0: "8c 8d", 1: "Jc 4c", 2: "Qh 5s", 3: "Kh 6h", 4: "9s 2d", 5: "Ts 3h"},
		"board": "8h Ks 3d 5c 2s",
		"plans": {
			0: {"preflop": "check_call", "default": "bet:0.6"},
			1: {"default": "fold"},
			2: {"default": "fold"},
			3: {"preflop": "call_upto:30", "default": "call_upto:200"},
			4: {"default": "fold"},
			5: {"preflop": "check_call", "default": "fold"},
		},
		"coach": [
			{"on": "hand_start", "lines": [
				"Last one: Heat. A strict dealer's watching now. Those eyes, top right? Hers.",
				"Each signal she spots adds Heat, and every extra one in a hand costs more.",
			]},
			{"on": "your_turn", "street": "preflop", "lines": [
				{"text": "Try it: give your crew a signal. Any of 1 to 4, or a back button.", "wait": "signal:any"},
				{"text": "Heat's {heat}, and she glanced your way. The next one costs +{next}. Again!", "wait": "signal:any"},
				"Hear that? Past 40 Heat the dealer warns your crew. Only a warning... so far.",
				"At 70 your whole crew is fined a big blind. At 100 the signaller's thrown out.",
			]},
			{"on": "acted", "seat": 0, "street": "preflop", "lines": [
				"Thrown out yourself? Your crew forfeits. One more now costs +{next}. Too hot!",
				"Heat cools a little every hand. Save your signals for when they count.",
			]},
			{"on": "hand_over", "lines": [
				"That's the lot: crews, soft play, signals, tells and Heat. Help's on Select.",
				"Ridge Road's east of town. Go show those crews how a real crew plays, hon!",
			]},
		],
	},
]

## Said when a signal would push your crew's Heat to a fine or worse: the
## tutorial never fines or ejects you, it only explains it.
const TOO_HOT := "Whoa! +{next} would put your crew at {after} Heat. Fined at 70, out at 100!"
const SKIP_PROMPT := "Skip the rest of the lesson? A: skip it. B: keep going."
const RESULT := "Lesson complete!"
const SKIPPED := "Lesson skipped."


static func count() -> int:
	return LESSONS.size()


static func lesson(index: int) -> Dictionary:
	return LESSONS[clampi(index, 0, LESSONS.size() - 1)]


## Who sits where (TableView.setup): you, then Rosie's regulars and your
## seated animals alternating. Missing teammates (a party of one) are
## filled with the starting pair.
static func setup_for(party: Array[Animal]) -> Array[Dictionary]:
	var mates: Array[Animal] = []
	for a in party:
		if mates.size() < 2:
			mates.append(a)
	var fallback: Array[Animal] = [Species.individual(&"owl", 0, 0.5), Species.individual(&"raccoon", 0, 0.5)]
	while mates.size() < 2:
		mates.append(fallback[mates.size()])
	var out: Array[Dictionary] = []
	for i in 3:
		var mine: Animal = null if i == 0 else mates[i - 1]
		out.append({"name": "You" if mine == null else mine.name, "team": 0, "animal": mine})
		var rival := Species.individual(RIVALS[i][0], RIVALS[i][1])
		out.append({"name": rival.name, "team": 1, "animal": rival})
	return out


## The stacked deck for a lesson: hole cards in the order the table deals
## them (one each, starting left of the button, twice round), then the
## board, then every other card so the deck never runs dry.
static func deck_for(index: int, seats := 6) -> Array[int]:
	var l := lesson(index)
	var holes := {}
	for seat: int in l["hole"]:
		holes[seat] = Card.parse_many(l["hole"][seat])
	var order: Array[int] = []
	for round_ in 2:
		for k in range(1, seats + 1):
			var seat: int = (int(l["button"]) + k) % seats
			order.append(holes[seat][round_])
	order.append_array(Card.parse_many(l["board"]))
	for c in 52:
		if not order.has(c):
			order.append(c)
	return order
