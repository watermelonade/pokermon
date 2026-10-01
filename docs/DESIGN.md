# Design summary

The full design doc, kept up to date, is here:
https://claude.ai/code/artifact/c284c9ac-3915-4b60-9293-ad0b666dede4

This is the short version, for code that needs to know the rules it's
implementing.

- **Pitch:** train the animals you meet to play team Texas hold'em, win a
  tournament in each of eight cities, and finish inside Cassius Coolidge's
  *A Friend in Need* (1903), the "Dogs Playing Poker" painting where a
  bulldog passes an ace under the table.
- **Combat:** your crew of 3 against theirs at a 6-seat table, seats
  alternating. You play only your own seat and can't see teammates' cards.
  A crew is out when all its seats are busted. Bosses bring bigger crews
  (3v4, 3v5); later regions require a crew of 4.
- **Team play:** soft play (no fighting teammates for chips), whipsaws,
  chip dumps, and secret signals on the Steam Deck's back buttons. Bond
  decides how reliably teammates read signals.
- **Heat:** every signal raises the dealer's suspicion of the crew (more for
  each extra signal the crew makes in the same hand). 40: warning. 70: the
  crew is fined a dead big blind each. 100: the signaller is thrown out.
  Heat cools each hand. Street games have no dealer; a bought dealer barely
  sees the boss crew; getting a boss crew's leader thrown out wins. Careful
  animals stay under their comfort line; careless ones get caught.
- **Interception:** the crews watch each other's signals. Each gesture can
  be noticed by the other crew (watchful species like owls and cats see
  more; a crew's second and third signal in a hand are two and three times
  as easy to catch, so chatty and bigger crews leak more). Every crew has
  its own code, so a noticed gesture means nothing until a showdown shows
  what it meant; learned codes are kept for good (saved). A fake signal
  (held modifier) is ignored by your teammates and believed by rivals who
  have cracked that gesture. Bots use what they read: they respect a bettor
  who said "strong" a bit more and bluff into one who said "weak". It's a
  match setting: on at the player's tables, off for the type chart's
  bot-vs-bot balance.
- **Play styles form a cycle:** Bluffer > Rock > Maniac > Shark > Calling
  Station > Bluffer. `tools/simulate.gd` measures how close the bots are.
- **The Binder:** 25 species, 4+ recruitable individuals each, so a crew of
  one species is possible. Dogs only join after the finale, enough of them
  to recreate the painting.
- **Look and feel (for now):** old-school Pokemon, Game Boy Advance era:
  16x16 tiles, outlined 3/4 top-down characters, trainer-style "!"
  encounters, bottom-of-screen text boxes, a healing-center diner, a
  battle-menu-style table. Inspired by, never copied.
- **Steam Deck:** 640x400 base resolution, integer-scaled to 1280x800,
  controller only, save between hands.
