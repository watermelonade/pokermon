class_name PadControls
extends RefCounted
## The names of the controls, for the on-screen hints, in one place so the
## hints can't drift from project.godot (tests/test_controls.gd checks they
## match the input map).
##
## The four signals have three homes:
## - X, Y, LT, RT: on any Xbox-style pad, and on the Steam Deck out of the
##   box (Steam Input shows every controller to the game as an Xbox-style
##   pad, and its default Gamepad template passes those four through). The
##   hints name these, since they work everywhere.
## - The Deck's back buttons L4 R4 L5 R5 (SDL paddles 1-4): nicer, since a
##   gesture under the table is what a signal is, but Steam only passes them
##   through with a controller configuration that maps them
##   (docs/STEAM_DECK.md section 2), so they can't be the only way.
## - 1-4 on a keyboard.
##
## Why X and Y and the triggers: A and B are confirm and back, LB and RB
## step the raise size (and LB held marks a fake), Start and Select are the
## menu and help, and the D-pad and stick move the cursor. That leaves the
## two upper face buttons and the two triggers, all reachable without
## letting go of the D-pad. The triggers are axes, not buttons, so they go
## through TriggerButtons (src/input/trigger_buttons.gd) to send one press
## per pull.

const SIGNAL_KEYS: Array[String] = ["1", "2", "3", "4"]
const SIGNAL_PAD: Array[String] = ["X", "Y", "LT", "RT"]
const SIGNAL_BACK: Array[String] = ["L4", "R4", "L5", "R5"]


## "X Y LT RT", for hints that name all four.
static func pad_signals() -> String:
	return " ".join(SIGNAL_PAD)
