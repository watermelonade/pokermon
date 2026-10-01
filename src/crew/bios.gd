class_name Bios
extends RefCounted
## Who each named animal is: a one-line bio (for the Binder and the Crew
## screen) and the line it says when it joins you, in its species' voice
## (docs/WRITING.md has the voices: owls measured and superior, geese in
## capitals, cats bored, raccoons whispering schemes, squirrels jittery,
## possums deadpan until they "die").
##
## A separate table rather than more keys in Species.CATALOG: the catalog is
## the rules' data (style, tell, names) and other code reads it; this is
## pure flavour, owned by the writing, and can grow (a line for a rematch, a
## line when benched) without touching the rules. Keyed by species, then by
## the individual's name exactly as Species lists it; tests/test_writing.gd
## checks every individual has both lines and that they fit the text box.
##
## Lines are short on purpose: the overworld's text box is read at a glance,
## Game Boy style, so one box each (about 76 characters at most).

const BIOS := {
	&"owl": {
		"Sage": {
			"bio": "Your first crewmate. Reads poker books for fun. Has notes on yours.",
			"recruit": "I accept. Someone has to keep an eye on your bet sizing."},
		"Hoot": {
			"bio": "The Night Shift's owl. Folds ninety hands, then takes the hundredth.",
			"recruit": "Very well. I shall fold on your behalf now. Expertly."},
		"Bramble": {
			"bio": "A Mossbank Regular for forty years. Still takes notes. On you.",
			"recruit": "I have watched you for three hands. That was sufficient. I'll come."},
		"Pip": {
			"bio": "A very small owl with a very large vocabulary. Tries not to hoot. Hoots.",
			"recruit": "Indubitably. That means yes. I am small, not a beginner."},
	},
	&"raccoon": {
		"Bandit": {
			"bio": "Your other first crewmate. Has a plan. The plan changes every hand.",
			"recruit": "*psst* i'm in. i was always in. that was the plan."},
		"Rascal": {
			"bio": "The Alley Cats' raccoon. Whispers plans nobody asked for.",
			"recruit": "*psst* finally, someone who listens. ok. plan one:"},
		"Smudge": {
			"bio": "Has a lot of pockets. Nobody knows what's in them. Smudge forgets.",
			"recruit": "*psst* deal me in. i brought snacks. they're from your bag."},
		"Scraps": {
			"bio": "Lives behind Rosie's. Bluffs with garbage. Sometimes wins with it.",
			"recruit": "*psst* a junk hand is just a treasure nobody believed in yet."},
	},
	&"goose": {
		"Honk": {
			"bio": "Boss of the Pond Hecklers. Raises every hand. Raises at ducks.",
			"recruit": "FINE. I JOIN. WHOEVER BEATS ME IS ON MY TEAM OR IN MY POND."},
		"Gertie": {
			"bio": "Honk's sister. Twice as loud, half as patient. Bites the deck.",
			"recruit": "I'M IN. POINT ME AT SOMEBODY. I WILL HONK AT THEM."},
		"Gander": {
			"bio": "Has never once checked. Does not know what checking is.",
			"recruit": "WHAT'S A CHECK. NEVER MIND. ALL IN. HELLO. I'M YOURS NOW."},
		"Waddles": {
			"bio": "The quietest goose in Mossbank, which is still very loud.",
			"recruit": "HELLO. I AM WADDLES. THIS IS MY INDOOR VOICE. LET'S PLAY."},
	},
	&"cat": {
		"Duchess": {
			"bio": "Runs the Alley Cats from a sunbeam. Has never been seen hurrying.",
			"recruit": "I suppose I'll come. Your lap looks adequate."},
		"Whiskers": {
			"bio": "Wins enormous pots, then pretends not to have noticed.",
			"recruit": "Fine. Wake me when somebody makes a mistake."},
		"Tom": {
			"bio": "A Mossbank Regular. Same chair since he was a kitten. It's his chair.",
			"recruit": "Thirty years at one table. Fine. I'll try another. Don't fuss."},
		"Mittens": {
			"bio": "Looks sweet. Is not. Will not discuss the dogs.",
			"recruit": "Yes, yes. Don't make it a whole thing. ...Is there a cushion?"},
	},
	&"squirrel": {
		"Nutmeg": {
			"bio": "The Pond Hecklers' accountant. Keeps their chips in his cheeks.",
			"recruit": "Okay okay okay! I'm in! Can I hold the chips? I'll hold the chips."},
		"Acorn": {
			"bio": "Founder of the Nut Club. Calls everything. Has never folded. Proud.",
			"recruit": "Yes! Join! Join! I'll call for you! I'll call EVERYTHING for you!"},
		"Hazel": {
			"bio": "Buried her winnings in forty-one places. Has found six.",
			"recruit": "Coming! Wait. Where did I put my chips. Wait. Coming!"},
		"Chitter": {
			"bio": "Talks through every hand. Mostly to the chips. They don't answer.",
			"recruit": "Me? Me! Okay! Chips, we're moving! Everybody in the cheeks!"},
	},
	&"possum": {
		"Marlo": {
			"bio": "Leads the Night Shift. Plays dead after every lost pot. Every one.",
			"recruit": "I'll join. If I lose, I die. Then I get up. It's a whole process."},
		"Dusty": {
			"bio": "The Regulars' fourth chair. Fainted at three Opens. Won one while fainted.",
			"recruit": "Okay. Wake me if I win."},
		"Pudding": {
			"bio": "The sweetest possum in Mossbank. Will still bury you. Politely.",
			"recruit": "I'll come. I'll bring a blanket, for when I die. It's cold down there."},
		"Graves": {
			"bio": "Captain of the Mossbank Regulars. Has \"died\" at that table 900 times.",
			"recruit": "...Fine. I've died at every table in Mossbank. Time for new ones."},
	},
}


## The animal's one-line bio, or "" if it has none (a species added to
## Species before its bios are written).
static func bio(species_id: StringName, animal_name: String) -> String:
	return str(BIOS.get(species_id, {}).get(animal_name, {}).get("bio", ""))


## What the animal says when it joins your crew, or "".
static func recruit_line(species_id: StringName, animal_name: String) -> String:
	return str(BIOS.get(species_id, {}).get(animal_name, {}).get("recruit", ""))
