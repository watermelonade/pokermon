class_name PlayStyle
extends Resource
## A poker personality as a handful of numbers the bot reads. These are the
## "types" in the type chart (see docs/DESIGN.md): each style is meant to
## beat one style and lose to another, and tools/simulate.gd plays
## same-style crews against each other to check whether that really happens.
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
## Chance of signalling teammates when there's something to say.
@export var chattiness := 0.6


static func preset(style_kind: Kind) -> PlayStyle:
	var s := PlayStyle.new()
	s.kind = style_kind
	match style_kind:
		Kind.ROCK:
			s.tightness = 1.35
			s.aggression = 0.5
			s.bluff_rate = 0.02
			s.stickiness = 0.0
		Kind.MANIAC:
			s.tightness = 0.6
			s.aggression = 0.85
			s.bluff_rate = 0.35
			s.stickiness = 0.3
		Kind.SHARK:
			s.tightness = 1.05
			s.aggression = 0.7
			s.bluff_rate = 0.1
			s.stickiness = 0.05
		Kind.CALLING_STATION:
			s.tightness = 0.7
			s.aggression = 0.15
			s.bluff_rate = 0.02
			s.stickiness = 0.6
		Kind.BLUFFER:
			s.tightness = 0.9
			s.aggression = 0.6
			s.bluff_rate = 0.45
			s.stickiness = 0.1
	return s


func display_name() -> String:
	return KIND_NAMES[kind]
