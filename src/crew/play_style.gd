class_name PlayStyle
extends Resource
## A poker personality as a handful of numbers the bot reads. These are the
## "types" in the type chart (see docs/DESIGN.md): each style beats the
## next in the cycle Bluffer > Rock > Maniac > Shark > Calling Station >
## Bluffer, as measured by tools/simulate.gd playing same-style crews.
##
## Getting the cycle took more than numbers. With only tightness, aggression,
## bluffing and stickiness, the Shark won every pairing and two links sat at
## 21-40%: tuning those four just moved the losses around. What made it work,
## each found by measuring where a losing crew's chips went:
## - `respect`: bets read as strength, so a Rock folds to a Bluffer.
## - `doubt`: a Maniac was winning the pots nobody contested and losing
##   everything in all-ins, because nobody folded a strong hand. A careful
##   Shark now can be shoved off one; a Rock can't.
## - `persistence`: a Maniac keeps re-raising, a Bluffer gives up.
## - `reads`: folding to bets (the Bluffer link) also handed the Maniac every
##   pot it raised, until the Rock learned to spot who never backs down.
## - `bluff_risk`: late in a match any raise was a shove, so the Bluffer's
##   bluffs became all-ins the Rock called; it lost 212 of 330. Capping a
##   bluff at half its stack fixed that.
##
## A Resource, so animals can carry a tuned style as a .tres file later.

enum Kind { ROCK, MANIAC, SHARK, CALLING_STATION, BLUFFER }

const KIND_NAMES := ["Rock", "Maniac", "Shark", "Calling Station", "Bluffer"]

@export var kind: Kind = Kind.SHARK
## Equity needed to play, relative to a fair share of the pot (1.0 = fair).
@export var tightness := 1.0
## Chance of raising rather than calling with a strong hand.
@export var aggression := 0.5
## Chance of betting or raising with a weak hand.
@export var bluff_rate := 0.1
## Chance of calling anyway when the price is wrong.
@export var stickiness := 0.1
## How much a bet in front of it reads as strength, 0..1. A high-respect
## player folds medium hands to pressure (so bluffs work on it); at 0 it
## judges its cards as if nobody had bet (so bluffs don't).
@export var respect := 0.5
## The largest share of its stack it will put in on a bluff, 0..1. A
## Bluffer steals small pots and won't bluff its stack off; a Maniac will.
@export var bluff_risk := 1.0
## How far big bets shake its faith in a strong hand too, 0..1 (scales
## `respect` for strong hands). A Rock (0) never folds a strong hand; a
## careful Shark (1) can be shoved off one.
@export var doubt := 0.5
## How well it notices a seat that never backs down (re-raises whenever bet
## into) and stops respecting that seat's bets, 0..1. See TableReads.
@export var reads := 0.0
## Chance of bluffing again once someone has raised: low gives up when
## resisted (a Bluffer), high doesn't let go (a Maniac).
@export var persistence := 0.3
## Chance of signalling teammates when there's something to say.
@export var chattiness := 0.6
## How much the dealer's suspicion quiets it, 0..1. It won't signal past a
## comfort line on its crew's Heat: 40 (the warning) at 1, 100 (ejection) at
## 0; and a careless animal (low caution) sometimes forgets the line.
@export var caution := 0.5


static func preset(style_kind: Kind) -> PlayStyle:
	var s := PlayStyle.new()
	s.kind = style_kind
	# Tuned with tools/simulate.gd until each style beats the next one in the
	# cycle; README.md has the numbers. Change one, re-run the simulator.
	match style_kind:
		Kind.ROCK:
			# Plays only good hands, folds the rest to any bet, never folds a
			# good hand, and notices who never backs down.
			s.tightness = 1.45
			s.aggression = 0.5
			s.bluff_rate = 0.02
			s.stickiness = 0.0
			s.respect = 1.0
			s.doubt = 0.0
			s.reads = 1.0
			s.persistence = 0.0
			s.caution = 0.9
			s.bluff_risk = 1.0
		Kind.MANIAC:
			# Plays everything, raises everything, doesn't let go.
			s.tightness = 0.6
			s.aggression = 0.85
			s.bluff_rate = 0.35
			s.stickiness = 0.15
			s.respect = 0.1
			s.doubt = 0.5
			s.reads = 0.0
			s.persistence = 0.9
			s.caution = 0.0
			s.bluff_risk = 1.0
		Kind.SHARK:
			# Solid and careful: believes big bets, even holding a good hand.
			s.tightness = 1.05
			s.aggression = 0.7
			s.bluff_rate = 0.1
			s.stickiness = 0.05
			s.respect = 1.0
			s.doubt = 1.0
			s.reads = 0.0
			s.persistence = 0.3
			s.caution = 0.85
			s.bluff_risk = 1.0
		Kind.CALLING_STATION:
			# Calls. Believes nothing, never bluffs, bets its good hands.
			s.tightness = 0.7
			s.aggression = 0.45
			s.bluff_rate = 0.02
			s.stickiness = 0.3
			s.respect = 0.0
			s.doubt = 0.5
			s.reads = 0.0
			s.persistence = 0.0
			s.caution = 0.4
			s.bluff_risk = 1.0
		Kind.BLUFFER:
			# Bets weak hands when nobody has shown strength, gives up when
			# resisted, and believes a raise (a Rock's raise is always real).
			s.tightness = 0.9
			s.aggression = 0.35
			s.bluff_rate = 0.7
			s.stickiness = 0.1
			s.respect = 1.0
			s.doubt = 1.0
			s.reads = 0.0
			s.persistence = 0.1
			s.caution = 0.8
			s.bluff_risk = 0.5
	return s


func display_name() -> String:
	return KIND_NAMES[kind]
