class_name StatusData
extends Resource
## Modular status effect resource. Drop new .tres files into res://statuses/ to add new effects.

@export var id := "status"
@export var display_name := "Status"
@export_multiline var description := ""
@export var badge_glyph := "~"
@export var color := Color(1.0, 0.5, 0.15)

@export_group("Effect Rules")
@export var default_duration := 2
@export var damage_per_turn := 0
@export var skips_turn := false
@export var blocks_regen := false
@export var incoming_damage_multiplier := 1.0
@export var shatters_on_hit := false
@export var cancels_status_ids: PackedStringArray = []

var turns_left := 0


func init_runtime(duration_override := -1, bonus_dot_damage := 0) -> StatusData:
	var copy := duplicate() as StatusData
	copy.turns_left = duration_override if duration_override > 0 else default_duration
	if copy.damage_per_turn > 0 or bonus_dot_damage > 0:
		copy.damage_per_turn = maxi(0, copy.damage_per_turn + bonus_dot_damage)
	return copy


func badge_text() -> String:
	return "%s%d" % [badge_glyph, turns_left]


func summary_text() -> String:
	if damage_per_turn > 0:
		return "%s (%dt, %d dmg/t)" % [display_name, turns_left, damage_per_turn]
	return "%s (%dt)" % [display_name, turns_left]

