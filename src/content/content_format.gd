class_name ContentFormat
extends RefCounted
## The one formatter every content file is written with (docs/EDITOR_SPEC.md,
## "Canonical form"): parse a file and write it again and you get the same
## bytes, so an editor save changes only what was changed and git shows
## just that. C-ROUND (tests/test_content.gd) holds every file to it.
##
## The bytes depend only on the data, never on how it was read or built:
## keys go in one fixed order (KEY_ORDER, then any others alphabetically),
## so a dictionary built in another order, or parsed from compact JSON,
## formats the same. Godot's JSON hands every number back as a float, so a
## whole number is written as an int (120, not 120.0); that's also why the
## loader (Content) turns numbers back into ints itself.
##
## Layout, chosen to read well in a diff:
## - 2-space indent, \n line ends, one trailing newline.
## - A map's `rows` one string per line, so a tile edit is a one-line diff
##   and the map still looks like a map.
## - Small records on one line: a dictionary of at most MAX_INLINE_KEYS
##   keys whose values are all flat (a scalar, a list of them, or a list of
##   such lists: a cell, a member, a gate's cells). That puts every
##   dialogue line ({"id", "text", "status"}), warp, pickup, sign and label
##   on its own line. Bigger things (npcs, crews, areas) get a line per key.
## - Flat lists on one line ([5, 3], [["goose", 0], ["cat", 1]]); any other
##   list one entry per line.
##
## JSON.stringify(data, "  ", true) was the first try: it sorts keys
## alphabetically (so "id" lands mid-record and "text" after "status") and
## puts every cell's x and y on lines of their own: measured on the content
## as moved, 2,004 lines against these 1,007 (the town map 446 against
## 191), and every dialogue line five lines instead of one.

const INDENT := "  "
const MAX_INLINE_KEYS := 5
## Keys in the order they're written; any key not here comes after these,
## alphabetically (a speaker's own sets of lines, e.g. Rosie's "offer").
const KEY_ORDER: Array[String] = [
	"id", "map", "name", "region", "kind", "rect", "text", "status", "notes",
	"outdoor", "rows", "labels", "warps", "gates", "pickups", "signs", "open_tables", "npcs", "crews",
	"areas", "speakers",
	"sprite", "cell", "cells", "to", "to_cell", "facing", "sight", "asleep", "requires", "card",
	"members", "boss", "tournament", "bracelet", "bond", "reward", "chips",
	"stake", "buy_in", "blinds", "max_money", "dealer", "players",
	"open_table", "animal", "gives_card", "dialogue",
	"lines", "before", "after",
]


## `data` as a content file's text.
static func stringify(data: Variant) -> String:
	return _value(data, "", "", true) + "\n"


## A content file's data, or null if it isn't JSON (parse_error says why).
static func parse(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## Why `text` doesn't parse ("line 12: Expected ','"), or "" if it does.
static func parse_error(text: String) -> String:
	var json := JSON.new()
	if json.parse(text) == OK:
		return ""
	return "line %d: %s" % [json.get_error_line(), json.get_error_message()]


## The keys of `d` in the order they're written.
static func ordered_keys(d: Dictionary) -> Array[String]:
	var known: Array[String] = []
	var rest: Array[String] = []
	for k: Variant in d:
		if KEY_ORDER.has(str(k)):
			known.append(str(k))
		else:
			rest.append(str(k))
	known.sort_custom(func(a: String, b: String) -> bool: return KEY_ORDER.find(a) < KEY_ORDER.find(b))
	rest.sort()
	return known + rest


static func _value(v: Variant, indent: String, key: String, top := false) -> String:
	if v is Dictionary:
		return _dict(v, indent, top)
	if v is Array:
		return _array(v, indent, key)
	return _scalar(v)


static func _dict(d: Dictionary, indent: String, top: bool) -> String:
	if d.is_empty():
		return "{}"
	var keys := ordered_keys(d)
	if not top and _inline(d):
		var parts: Array[String] = []
		for k in keys:
			parts.append("%s: %s" % [JSON.stringify(k), flat(d[k])])
		return "{%s}" % ", ".join(parts)
	var inner := indent + INDENT
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s%s: %s" % [inner, JSON.stringify(k), _value(d[k], inner, k)])
	return "{\n%s\n%s}" % [",\n".join(parts), indent]


static func _array(a: Array, indent: String, key: String) -> String:
	if a.is_empty():
		return "[]"
	if key != "rows" and _is_flat(a):
		return flat(a)
	var inner := indent + INDENT
	var parts: Array[String] = []
	for e: Variant in a:
		parts.append(inner + _value(e, inner, ""))
	return "[\n%s\n%s]" % [",\n".join(parts), indent]


## Whether a dictionary goes on one line (see the top).
static func _inline(d: Dictionary) -> bool:
	if d.size() > MAX_INLINE_KEYS or d.has("rows"):
		return false
	for v: Variant in d.values():
		if not _is_flat(v):
			return false
	return true


## A scalar, a list of scalars, or a list of lists of scalars.
static func _is_flat(v: Variant, depth := 0) -> bool:
	if v is Dictionary:
		return false
	if v is Array:
		if depth >= 2:
			return false
		for e: Variant in v:
			if not _is_flat(e, depth + 1):
				return false
	return true


## A value on one line, as the file shows it: [5, 3], "dwon", 120.
static func flat(v: Variant) -> String:
	if v is Array:
		var parts: Array[String] = []
		for e: Variant in v:
			parts.append(flat(e))
		return "[%s]" % ", ".join(parts)
	return _scalar(v)


static func _scalar(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			var f: float = v
			if is_finite(f) and f == floorf(f) and absf(f) < 1e15:
				return str(int(f))
			return JSON.stringify(f)
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(str(v))
	push_error("ContentFormat: %s isn't JSON data (write cells as [x, y], enums by name)" % var_to_str(v))
	return JSON.stringify(var_to_str(v))
