class_name ScriptedBot
extends PokerBot
## A seat that plays from a script instead of from equity, for the tutorial
## (TutorialScript). A lesson only teaches if its moment happens every time:
## the teammate who signals "I'm strong" has to signal, the raccoon has to
## bluff the river. PokerBot decides from Monte Carlo equity and dice, so on
## a stacked deck it still did something different from run to run; this
## plays a short policy per street and nothing else.
##
## Policies (a street with none uses "default", else "check_call"):
##   fold          check if it's free, else fold
##   check_call    check or call anything
##   call_upto:N   call up to N chips this decision, else fold
##   raise_to:N    raise the street's bet to N; if it's already that high, call
##   bet:F         bet F x the pot when nobody has bet, else call
##   bluff:F       bet or raise F x the pot whatever it holds
##   yield:P       fold if a teammate has signalled "I'm strong" or "Let me
##                 have it" this hand (stepping aside), else play P
##
## Every policy is safe against anything the player does (a policy never
## needs the player to have acted one way), so a lesson can't get stuck;
## what changes is what the coach says about it. Soft play still applies:
## with no rival left in the pot it checks or folds, like PokerBot.
##
## Signals are scripted too ({street: TableTalk.Sig}), sent once per street
## when the bot first decides on it.

const STREETS := ["preflop", "flop", "turn", "river"]

var plan := {}  ## street name ("preflop", "flop", "turn", "river", "default") -> policy
var signals := {}  ## street name -> TableTalk.Sig
var _sent := {}  ## hand * 10 + street -> true once that street's signal went


func _init(p_plan := {}, p_signals := {}) -> void:
	super(PlayStyle.preset(PlayStyle.Kind.ROCK))
	plan = p_plan
	signals = p_signals


static func street_name(street: int) -> String:
	return STREETS[clampi(street, 0, STREETS.size() - 1)]


func decide(table: HoldemTable, me: int, talk: TableTalk) -> Dictionary:
	var key := table.hand_number * 10 + table.street
	var street := street_name(table.street)
	if signals.has(street) and not _sent.has(key):
		_sent[key] = true
		talk.send(me, signals[street], table.street)
	var rivals_in := false
	for i in table.seats.size():
		if i != me and table.seats[i].live() and table.seats[i].team != table.seats[me].team:
			rivals_in = true
	if not rivals_in:
		return {"action": HoldemTable.Action.FOLD, "amount": 0}  # soft play: the table makes it a check when free
	return play(policy_for(plan, table.street), table, me, talk)


static func policy_for(p_plan: Dictionary, street: int) -> String:
	return str(p_plan.get(street_name(street), p_plan.get("default", "check_call")))


## What `policy` does for seat `me`, the seat to act.
static func play(policy: String, table: HoldemTable, me: int, talk: TableTalk) -> Dictionary:
	var legal := table.legal()
	var to_call: int = legal["to_call"]
	var name := policy.get_slice(":", 0)
	var arg := policy.substr(name.length() + 1)
	var fold := {"action": HoldemTable.Action.FOLD, "amount": 0}
	var call := {"action": HoldemTable.Action.CALL, "amount": 0}
	match name:
		"fold":
			return fold
		"check_call":
			return call
		"call_upto":
			return call if to_call <= int(arg) else fold
		"raise_to":
			if table.current_bet < int(arg) and legal["can_raise"]:
				return {"action": HoldemTable.Action.RAISE, "amount": int(arg)}
			return call
		"bet", "bluff":
			if legal["can_raise"] and (to_call == 0 or name == "bluff"):
				var size := maxi(table.min_raise, int(table.pot() * float(arg)))
				return {"action": HoldemTable.Action.RAISE, "amount": table.current_bet + size}
			return call
		"yield":
			if teammate_said_strong(table, me, talk):
				return fold
			return play(arg, table, me, talk)
	push_error("ScriptedBot: unknown policy %s" % policy)
	return call


## A teammate of `me` signalled "I'm strong" or "Let me have it" this hand.
## Read straight from what was sent: in a lesson the reaction has to be the
## one the coach describes, so there's no bond misread here.
static func teammate_said_strong(table: HoldemTable, me: int, talk: TableTalk) -> bool:
	for s: Dictionary in talk.sent:
		var from: int = s["from"]
		if from == me or table.seats[from].team != table.seats[me].team:
			continue
		if s["sig"] == TableTalk.Sig.STRONG or s["sig"] == TableTalk.Sig.BACK_OFF:
			return true
	return false
