class_name RaiseSizes
extends RefCounted
## The raise sizes the bumpers jump between: the minimum, half the pot, the
## pot, twice the pot, and all-in. The first table stepped one big blind per
## press, so a pot-sized raise on the river took a dozen presses; on a
## controller that's the difference between raising and not bothering.
## D-pad up/down still fine-tunes by one big blind (`nudge`).
##
## Pot-sized means what it does in a card room: call first, then raise by
## the whole pot, so raise-to = current bet + (pot + to call) x fraction.
## Sizes that land outside the legal range are clamped into it, and sizes
## that land on the same amount merge, keeping "Min" and "All-in" names.

const FRACTIONS := [["Half pot", 0.5], ["Pot", 1.0], ["2x pot", 2.0]]


## [{"name": String, "to": int}], ascending, no duplicate amounts.
## `legal` is HoldemTable.legal(); `current_bet` the bet to match.
static func presets(legal: Dictionary, current_bet: int, pot: int) -> Array[Dictionary]:
	var lo: int = legal["min_raise_to"]
	var hi: int = legal["max_raise_to"]
	var to_call: int = legal["to_call"]
	var out: Array[Dictionary] = [{"name": "Min", "to": lo}]
	for f: Array in FRACTIONS:
		var to := current_bet + roundi((pot + to_call) * float(f[1]))
		if to > lo and to < hi:
			out.append({"name": f[0], "to": to})
	if hi > lo:
		out.append({"name": "All-in", "to": hi})
	else:
		out[0]["name"] = "All-in"
	# Two fractions can round to the same amount in a tiny pot.
	var merged: Array[Dictionary] = []
	for p in out:
		if merged and p["to"] == merged[-1]["to"]:
			continue
		merged.append(p)
	return merged


## The next preset above (dir > 0) or below (dir < 0) `current`, or
## `current` itself at the end of the range.
static func step(sizes: Array[Dictionary], current: int, dir: int) -> int:
	if dir > 0:
		for p in sizes:
			if p["to"] > current:
				return p["to"]
	else:
		for k in range(sizes.size() - 1, -1, -1):
			if sizes[k]["to"] < current:
				return sizes[k]["to"]
	return current


## One big blind up or down, inside the legal range.
static func nudge(legal: Dictionary, current: int, big_blind: int, dir: int) -> int:
	return clampi(current + dir * big_blind, legal["min_raise_to"], legal["max_raise_to"])


## The preset's name if `amount` is exactly one, else "".
static func name_of(sizes: Array[Dictionary], amount: int) -> String:
	for p in sizes:
		if p["to"] == amount:
			return p["name"]
	return ""
