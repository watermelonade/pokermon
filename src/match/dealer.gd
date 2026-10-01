class_name Dealer
extends Resource
## Who's watching the table, and how closely. Every city's tournament has its
## own dealer (docs/DESIGN.md: asleep in the starter town, strict in the
## capital, bought at the House); street games have none.
##
## The numbers are tuned with tools/heat_report.gd so that an asleep dealer
## almost never fines anyone and a strict one catches a chatty crew most
## matches: see README.md for what they measure.

enum Kind { STREET, ASLEEP, RELAXED, WATCHFUL, STRICT, BOUGHT }

const KIND_NAMES := ["No dealer", "Asleep", "Relaxed", "Watchful", "Strict", "Bought"]

@export var kind: Kind = Kind.STREET
## Heat one signal adds (the first of a hand; more from the same seat in the
## same hand cost more: a seat that keeps touching its nose gets noticed).
@export var notice := 0.0
## Heat that fades after every hand.
@export var cooling := 0.0
## Heat multiplier per team. A bought dealer looks away from the boss crew.
@export var team_bias := {}


static func preset(dealer_kind: Kind, boss_team := 1) -> Dealer:
	var d := Dealer.new()
	d.kind = dealer_kind
	match dealer_kind:
		Kind.STREET:
			pass
		Kind.ASLEEP:
			d.notice = 5.0
			d.cooling = 6.0
		Kind.RELAXED:
			d.notice = 8.0
			d.cooling = 5.0
		Kind.WATCHFUL:
			d.notice = 12.0
			d.cooling = 4.0
		Kind.STRICT:
			d.notice = 20.0
			d.cooling = 3.0
		Kind.BOUGHT:
			d.notice = 12.0
			d.cooling = 4.0
			d.team_bias = {boss_team: 0.25}
	return d


func watching() -> bool:
	return notice > 0.0


func display_name() -> String:
	return KIND_NAMES[kind]
