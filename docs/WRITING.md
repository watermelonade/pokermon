# Writing: voice and canon

How the game talks. Every line in the demo lives in data: crews, townsfolk
and signs in `src/world/world_map.gd` (MAPS), the animals' bios and join
lines in `src/crew/bios.gd`, tells in `src/crew/species.gd`, and the
narration (intro, blackout, recruiting, the diner) as `dialog.say(...)`
strings in `src/world/overworld.gd`. `tests/test_writing.gd` checks every
one of them fits the text box.

## The rules

- **Short.** The look is a Game Boy Advance RPG: a text box is read at a
  glance. Aim for one box of about 76 characters (two GBA lines of 38); the
  test's hard cap is 84 (one row of the table's pixel font, in case the box
  moves to it). One thought per box.
- **No speech over about three boxes.** Four is the test's limit, and only
  the hall's boss crew and Old Bertram (who's earned it) use four.
- **Jokes over exposition.** If a line explains a rule, make it do it in
  character ("Step into a crew's sight and they'll deal you in"), then get
  out. Controls are said once, in the intro and by Bertram.
- **The humour is the animals.** Their tells, their habits, how badly they
  want to be good at poker. Nobody is cruel; stakes are low and personal
  (pride, pie, a sunbeam). Losing is funny, never humiliating.
- **Original only.** Inspired by handheld monster RPGs, never quoting them:
  no borrowed names, catchphrases, menus' wording or jingles-as-text.
- **The player is a human with their own seat at the table**, addressed as
  "you". Rosie calls you "hon".
- Capitals belong to geese, signs and the occasional shout. Narration is
  plain and second person ("You beat the Nut Club!"). Stage directions go
  in *asterisks* (`*flops over*`) or (parentheses) for what you notice.

## Mossbank and Ridge Road

**Mossbank** is a sleepy market town of 212 (and a lot of squirrels, who
keep getting counted twice). Everyone plays cards; most of them badly.

- **Rosie's Diner**, the healing centre. Pie, coffee, booths. If a crew
  cleans you out you wake up in a booth with your wallet lighter and your
  crew full of pie. Over a booth hangs a painting of dogs playing cards
  that came with the place. Nobody remembers hanging it.
- **Home**: your house and your practice table, felt worn thin.
- **The Shop**: closed for the Open, because the shopkeeper entered it.
- **The Mossbank Tournament Hall**, at the east end of Ridge Road: the
  Mossbank Open, the town's "gym". Hall rules: no biting, no cards in cheek
  pouches, do not wake Lou.

**Ridge Road** runs east from town to the hall, and crews line it "like
crows on a fence". Each has a personality and a running joke:

| Crew | Who | Personality | Running joke |
| --- | --- | --- | --- |
| The Pond Hecklers | Honk (goose, boss), Nutmeg (squirrel), Gertie (goose) | Loud, territorial, declare the road theirs on the spot | Nutmeg keeps the crew's chips in his cheeks; they'll be honking about the loss for weeks |
| The Alley Cats | Duchess (cat, boss), Whiskers (cat), Rascal (raccoon) | Bored, superior, "weren't even trying" | Rascal always has a plan; nobody listens. You're standing in their sunbeam |
| The Nut Club | Acorn, Hazel, Chitter (squirrels) | Jittery, officious, a toll booth with no booth | "Rule one: we call. Rule two: we always call." Stunned that it doesn't work |
| The Night Shift | Marlo (possum, boss), Hoot (owl), Smudge (raccoon) | Nocturnal, hushed, invisible to most people | They play at night; it is not night. Marlo dies (dramatically) when he loses |
| The Mossbank Regulars | Graves (possum, captain), Tom (cat), Bramble (owl) | The hall's boss crew: same table, same seats, every Thursday since 1971 | Their signals are older than you. Graves keels over, then is fine |

**Townsfolk**

- **Old Bertram** (badger): retired road player. Gives the tutorial as
  war stories. Lost his shirt twice, won it back once.
- **Juniper, age 9**: town gossip. Says what the grown-ups won't (Lou has
  been asleep since before she was born). Wants a crew of nine geese.
- **Rosie**: runs the diner; warm, unflappable, calls you "hon", fixes
  everything with pie.
- **Lou, the dealer**: asleep at the hall's table, always. Talks in his
  sleep. A sleeping dealer is why you can signal freely in the Open.

## How each species talks

| Species | Voice | Example |
| --- | --- | --- |
| Owl (Rock) | Measured, superior, a little pompous; long words, short sentences | "Very well. I shall fold on your behalf now. Expertly." |
| Goose (Maniac) | ALL CAPS. Energy, threats, declarations of ownership | "FINE. I JOIN. WHOEVER BEATS ME IS ON MY TEAM OR IN MY POND." |
| Cat (Shark) | Smug and bored; treats winning as a chore and you as furniture | "I suppose I'll come. Your lap looks adequate." |
| Raccoon (Bluffer) | Schemer; whispers in lowercase, always opens with *psst* | "\*psst\* i'm in. i was always in. that was the plan." |
| Squirrel (Calling Station) | Jittery, repeats itself, hoards (chips in cheeks, winnings buried and lost) | "Okay okay okay! I'm in! Can I hold the chips?" |
| Possum (Rock) | Deadpan; "dies" dramatically when it loses, then is fine | "I'll join. If I lose, I die. Then I get up. It's a whole process." |

Tells (`species.gd`) keep their mechanical meaning exactly (AnimalTells
reads them as rules): reword for flavour, never change *when* they fire.

## The House and the dogs (foreshadow lightly)

The finale is Coolidge's *A Friend in Need* (1903): dogs around a table,
one passing an ace under it. Dogs never join you before then. In the demo
they're only glimpsed, and never named as a threat:

- The **painting in Rosie's Diner** (east wall, by the booths): "dogs
  playing cards. One slips an ace under the table. Did it just wink?"
  Rosie: "don't mind the painting. It came with the place."
- **Lou talks in his sleep**: "Zzz... the House... always... zzz..."
- **Rosie's pie** after you win: "On the house. (Not that House, hon.)"
- **Mittens** (cat) "will not discuss the dogs".
- The demo's last line: "Somewhere, a dog shuffles a deck."

That's the budget for a whole town: one or two per place, always a joke
first and a hint second. Nobody explains the House.

## Adding lines

- Crews: `before` is a list (up to three or four boxes), `after` is one
  string, said after you win and whenever you talk to them later (so it
  should still make sense after one of them has joined you).
- Townsfolk `lines` are said in full every time you talk to them.
- Signs are one box. A sign can sit on a wall cell (the diner's painting,
  the hall's rules): you read it from the floor in front.
- New animals get a bio and a join line in `Bios.BIOS`; the test fails
  until they do.
