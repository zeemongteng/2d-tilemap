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
## Ids of the upgrade branches picked so far (see SpellBranches).
var branches: Array[String] = []


func init_runtime() -> SpellData:
	var copy := duplicate() as SpellData
	copy.level = 1
	copy.branches = []
	copy.charges = copy.effective_max_charges()
	copy.cooldown_remaining = 0
	return copy


func has_branch(branch_id: String) -> bool:
	return branches.has(branch_id)


func branch_stat(key: String) -> int:
	var total := 0
	for branch_id in branches:
		var entry := SpellBranches.get_branch(branch_id)
		if entry.is_empty():
			continue
		total += int((entry["stats"] as Dictionary).get(key, 0))
	return total


func branch_summary() -> String:
	var names: Array[String] = []
	for branch_id in branches:
		var entry := SpellBranches.get_branch(branch_id)
		if not entry.is_empty():
			names.append(str(entry["name"]))
	return ", ".join(names)


func uses_cooldown() -> bool:
	return cooldown_turns > 0


func effective_cooldown() -> int:
	return maxi(1, cooldown_turns - (level - 1) * bonus_cooldown_reduction_per_level + branch_stat("cooldown"))


func effective_status_duration() -> int:
	if status_duration <= 0:
		return 0
	return status_duration + branch_stat("status_duration")


func effective_heal() -> int:
	return heal_per_hit + branch_stat("heal")


func effective_chain_jumps() -> int:
	return chain_jumps + level - 1 + branch_stat("jumps")


func summon_hp_bonus() -> int:
	return (level - 1) * bonus_summon_hp_per_level + branch_stat("summon_hp")


func summon_atk_bonus() -> int:
	return (level - 1) * bonus_summon_atk_per_level + branch_stat("summon_atk")


func is_ready() -> bool:
	return cooldown_remaining <= 0 if uses_cooldown() else charges > 0


func tick_cooldown() -> void:
	if cooldown_remaining > 0:
		cooldown_remaining = maxi(0, cooldown_remaining - 1)


func effective_damage() -> int:
	return damage + (level - 1) * bonus_damage_per_level + branch_stat("damage")


func effective_max_charges() -> int:
	return maxi(1, max_charges + (level - 1) * bonus_charges_per_level + branch_stat("charges"))


func effective_range() -> int:
	if pattern == Pattern.NOVA:
		return 0
	return cast_range + (level - 1) * bonus_range_per_level + branch_stat("range")


func effective_radius() -> int:
	return radius + (level - 1) * bonus_radius_per_level + branch_stat("radius")


func can_upgrade() -> bool:
	return level < max_level


## Levels the spell up, taking `branch_id` (a random valid branch when empty). Returns the branch id taken, or "".
func upgrade(branch_id := "") -> String:
	if not can_upgrade():
		return ""
	var chosen := branch_id
	if chosen.is_empty():
		var offers := SpellBranches.offers_for(self)
		if not offers.is_empty():
			chosen = str(offers[randi() % offers.size()]["id"])
	var old_max := effective_max_charges()
	if not chosen.is_empty() and not has_branch(chosen):
		branches.append(chosen)
	level += 1
	if uses_cooldown():
		cooldown_remaining = 0
	else:
		var gained := effective_max_charges() - old_max
		charges = mini(effective_max_charges(), charges + maxi(1, gained))
	return chosen


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
			return "Chain (%d)" % effective_chain_jumps()
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
		parts.append("%s (%dt)" % [status_effect.display_name, effective_status_duration()])
	if effective_heal() > 0:
		parts.append("Heals %d/hit" % effective_heal())
	if uses_cooldown():
		parts.append("%dt Cooldown" % effective_cooldown())
	else:
		parts.append("%d Charges" % effective_max_charges())
	var stats_line := "  •  ".join(parts)
	var text := stats_line if description.is_empty() else "%s\n%s" % [stats_line, description]
	if not branches.is_empty():
		text += "\nBranches: %s" % branch_summary()
	return text
