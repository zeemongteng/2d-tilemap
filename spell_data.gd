class_name SpellData
extends Resource
## Rift Wizard-style spell resource with charges, elemental types, AoE patterns, summoning, and SP upgrades.

enum Element { FIRE, LIGHTNING, ICE, ARCANE, NATURE, DARK, HOLY }
enum Pattern { SINGLE, BLAST, BEAM, CHAIN, BLINK, NOVA, SUMMON, DASH }

@export var display_name := "Spell"
@export_multiline var description := ""
@export var element := Element.FIRE
@export var pattern := Pattern.SINGLE
@export var color := Color(1.0, 0.45, 0.2)
@export var is_innate := false

@export_group("Stats")
@export var max_charges := 5
## When > 0, this skill uses a turn-based cooldown instead of charges.
@export var cooldown_turns := 0
@export var cast_range := 5
@export var radius := 0
@export var chain_jumps := 0
@export var damage := 4
@export var status_effect: StatusData
@export var status_duration := 0
@export var summon_scene: PackedScene
@export var requires_los := true
## HP the caster recovers for every foe struck.
@export var heal_per_hit := 0

@export_group("Progression")
@export var learn_cost := 1
@export var upgrade_cost := 2
@export var max_level := 3
@export var bonus_damage_per_level := 2
@export var bonus_charges_per_level := 2
@export var bonus_range_per_level := 1
@export var bonus_radius_per_level := 0
@export var bonus_summon_hp_per_level := 4
@export var bonus_summon_atk_per_level := 1
@export var bonus_cooldown_reduction_per_level := 0

var charges := 5
var cooldown_remaining := 0
var level := 1


func init_runtime() -> SpellData:
	var copy := duplicate() as SpellData
	copy.level = 1
	copy.charges = copy.effective_max_charges()
	copy.cooldown_remaining = 0
	return copy


func uses_cooldown() -> bool:
	return cooldown_turns > 0


func effective_cooldown() -> int:
	return maxi(1, cooldown_turns - (level - 1) * bonus_cooldown_reduction_per_level)


func is_ready() -> bool:
	return cooldown_remaining <= 0 if uses_cooldown() else charges > 0


func tick_cooldown() -> void:
	if cooldown_remaining > 0:
		cooldown_remaining = maxi(0, cooldown_remaining - 1)


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
	if uses_cooldown():
		cooldown_remaining = 0
	else:
		var gained := effective_max_charges() - old_max
		charges = mini(effective_max_charges(), charges + maxi(1, gained))


func restore_charges(amount: int) -> void:
	if uses_cooldown():
		return
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
		Element.NATURE:
			return "Nature"
		Element.DARK:
			return "Dark"
		Element.HOLY:
			return "Holy"
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
		Pattern.SUMMON:
			return "Summon"
		Pattern.DASH:
			return "Dash & Dodge"
	return "Spell"


func describe_button(hotkey: String) -> String:
	if uses_cooldown():
		var cd_state := "READY • %dt CD" % effective_cooldown() if cooldown_remaining <= 0 else "CD: %dt" % cooldown_remaining
		var key_tag := "D/%s" % hotkey if is_innate and hotkey != "D" else hotkey
		return "[%s] %s Lv.%d  (%s)" % [key_tag, display_name, level, cd_state]
	return "[%s] %s Lv.%d  (%d/%d)" % [
		hotkey, display_name, level, charges, effective_max_charges()
	]


func describe_details() -> String:
	var parts: Array[String] = [
		"[%s | %s]" % [element_name(), pattern_name()],
	]
	if pattern == Pattern.SUMMON:
		parts.append("Summons Ally")
	elif pattern == Pattern.DASH:
		parts.append("Dodges Attacks (1t)")
	elif effective_damage() > 0:
		parts.append("%d DMG" % effective_damage())
	if effective_range() > 0:
		parts.append("Rng %d" % effective_range())
	if status_effect != null and status_duration > 0:
		parts.append("%s (%dt)" % [status_effect.display_name, status_duration])
	if heal_per_hit > 0:
		parts.append("Heals %d/hit" % heal_per_hit)
	if uses_cooldown():
		parts.append("%dt Cooldown" % effective_cooldown())
	else:
		parts.append("%d Charges" % effective_max_charges())
	var stats_line := "  •  ".join(parts)
	if description.is_empty():
		return stats_line
	return "%s\n%s" % [stats_line, description]
