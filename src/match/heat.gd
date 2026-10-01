class_name Heat
extends RefCounted
## The dealer's suspicion of each crew. Every signal adds Heat (how much
## depends on the Dealer); Heat fades a little after every hand. Crossing a
## line has consequences:
##
##   40  warning   the dealer says something; nothing else happens
##   70  fine      every member of the crew posts a dead big blind next hand
##   100 ejection  the seat that made the signal is thrown out after the
##                 hand, its chips leave the game, and the crew's Heat drops
##                 back to 60 (the floor is still watching)
##
## Signals from the same crew in the same hand cost more each time (1x, 2x,
## 3x...): one nose-touch is a habit, three teammates fidgeting in one hand
## is a message. (Counting per seat instead let short-handed styles like the
## Maniac signal freely: tools/heat_report.gd had careless crews caught
## least.) Ejections wait for the hand to end so the rules engine never loses
## a player mid-hand.
##
## A warning or fine fires once on the way up, then re-arms only after the
## crew's Heat cools below half the warning line; otherwise a crew hovering
## at the line was warned 16 times a match.
##
## TeamMatch applies the fines and ejections; this class only keeps score.

signal warned(team: int, seat: int)
signal fined(team: int, seat: int)
signal ejection_called(team: int, seat: int)

const WARNING := 40.0
const FINE := 70.0
const EJECT := 100.0
const AFTER_EJECTION := 60.0

var dealer := Dealer.preset(Dealer.Kind.STREET)
var heat := {}  ## team -> 0..100
var pending_fines: Array[int] = []  ## teams to fine at the next hand's start
var pending_ejections: Array[int] = []  ## seats to throw out when this hand ends
var _table: HoldemTable
var _gestures_this_hand := {}  ## team -> signals made this hand
var _armed := {}  ## team -> true once cool enough to be warned/fined again


func watch(table: HoldemTable, talk: TableTalk) -> void:
	_table = table
	table.hand_started.connect(func(_button: int) -> void: _gestures_this_hand.clear())
	table.hand_finished.connect(func(_result: Dictionary) -> void: _cool())
	talk.gesture_made.connect(_on_gesture)


func level(team: int) -> float:
	return heat.get(team, 0.0)


## What one more signal from `seat` this hand would add.
func cost_of_next(seat: int) -> float:
	var team := _table.seats[seat].team
	return dealer.notice * dealer.team_bias.get(team, 1.0) * (_gestures_this_hand.get(team, 0) + 1)


func _on_gesture(seat: int, _sig: int) -> void:
	if not dealer.watching():
		return
	var team := _table.seats[seat].team
	var before := level(team)
	var after := before + cost_of_next(seat)
	_gestures_this_hand[team] = _gestures_this_hand.get(team, 0) + 1
	heat[team] = after
	var armed: Dictionary = _armed.get_or_add(team, {"warn": true, "fine": true})
	if after >= WARNING and armed["warn"]:
		armed["warn"] = false
		warned.emit(team, seat)
	if after >= FINE and armed["fine"]:
		armed["fine"] = false
		pending_fines.append(team)
		fined.emit(team, seat)
	if after >= EJECT:
		if not pending_ejections.has(seat):
			pending_ejections.append(seat)
		heat[team] = AFTER_EJECTION
		ejection_called.emit(team, seat)


func _cool() -> void:
	for team: int in heat:
		heat[team] = maxf(0.0, heat[team] - dealer.cooling)
		if heat[team] < WARNING / 2 and _armed.has(team):
			_armed[team] = {"warn": true, "fine": true}
