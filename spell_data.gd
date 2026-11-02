class_name SpellData
extends Resource
## Rift Wizard-style spell resource with charges, elemental types, AoE patterns, and SP upgrades.

enum Element { FIRE, LIGHTNING, ICE, ARCANE }
enum Pattern { SINGLE, BLAST, BEAM, CHAIN, BLINK, NOVA }

@export var display_name := "Spell"
@export_multiline var description := ""
@export var element := Element.FIRE
@export var pattern := Pattern.SINGLE
@export var color := Color(1.0, 0.45, 0.2)

@export_group("Stats")
@export var max_charges := 5
@export var cast_range := 5
@export var radius := 0
@export var chain_jumps := 0
@export var damage := 4
@export var status_duration := 0
@export var requires_los := true

@export_group("Progression")
@export var learn_cost := 1
@export var upgrade_cost := 2
@export var max_level := 3
@export var bonus_damage_per_level := 2
@export var bonus_charges_per_level := 2
@export var bonus_range_per_level := 1
@export var bonus_radius_per_level := 0

var charges := 5
var level := 1


func init_runtime() -> SpellData:
	var copy := duplicate() as SpellData
	copy.level = 1
	copy.charges = copy.effective_max_charges()
	return copy


func effective_damage() -> int:
	return damage + (level - 1) * bonus_damage_per_level


func effective_max_charges() -> int:
	return max_charges + (level - 1) * bonus_charges_per_level


func effective_range() -> int:
	if pattern == Pattern.NOVA:
		return 0
	return cast_range + (level - 1) * bonus_range_per_level


func effective_radius() -> int:
	return radius + (level - 1) * bonus_radius_per_level


func can_upgrade() -> bool:
	return level < max_level


func upgrade() -> void:
	if not can_upgrade():
		return
	var old_max := effective_max_charges()
	level += 1
	var gained := effective_max_charges() - old_max
	charges = mini(effective_max_charges(), charges + maxi(1, gained))


func restore_charges(amount: int) -> void:
	charges = mini(effective_max_charges(), charges + amount)


func element_name() -> String:
	match element:
		Element.FIRE:
			return "Fire"
		Element.LIGHTNING:
			return "Lightning"
		Element.ICE:
			return "Ice"
		Element.ARCANE:
			return "Arcane"
	return "Magic"


func pattern_name() -> String:
	match pattern:
		Pattern.SINGLE:
			return "Single"
		Pattern.BLAST:
			return "Blast (r=%d)" % effective_radius()
		Pattern.BEAM:
			return "Beam"
		Pattern.CHAIN:
			return "Chain (%d)" % (chain_jumps + level - 1)
		Pattern.BLINK:
			return "Teleport"
		Pattern.NOVA:
			return "Nova (r=%d)" % effective_radius()
	return "Spell"


func describe_button(hotkey: String) -> String:
	return "[%s] %s Lv.%d  (%d/%d)" % [
		hotkey, display_name, level, charges, effective_max_charges()
	]


func describe_details() -> String:
	var parts: Array[String] = [
		"[%s | %s]" % [element_name(), pattern_name()],
		"%d DMG" % effective_damage(),
	]
	if effective_range() > 0:
		parts.append("Rng %d" % effective_range())
	parts.append("%d Charges" % effective_max_charges())
	var stats_line := "  •  ".join(parts)
	if description.is_empty():
		return stats_line
	return "%s\n%s" % [stats_line, description]

