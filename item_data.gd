class_name ItemData
extends Resource

enum Type {
	WEAPON,
	ARMOR,
	POTION,
	MANA_POTION,
	SPELL_ORB,
	RELIC,
	DEVIL_PORTAL,
	ANGEL_PORTAL,
	RETURN_PORTAL,
	SPELL_PEDESTAL,
}

enum RelicEffect {
	NONE,
	BURNING_BLOOD,
	VAJRA_CRYSTAL,
	ANCIENT_ANCHOR,
	STORM_CORE,
	ARCANE_PRISM,
	CINDER_HEART,
	PERMAFROST_RING,
	THE_MARK,
	VAMPIRIC_MAW,
	SACRED_HEART,
	HOLY_MANTLE,
}

@export var display_name := "Item"
@export_multiline var description := ""
@export var glyph := "?"
@export var color := Color.WHITE
@export var type := Type.POTION
@export var attack_bonus := 0
@export var defense_bonus := 0
@export var max_hp_bonus := 0
@export var spell_damage_bonus := 0
@export var spell_range_bonus := 0
@export var burn_damage_bonus := 0
@export var status_duration_bonus := 0
@export var afflicted_damage_bonus := 0
@export var heal_amount := 0
@export var charge_restore := 0
@export var sp_amount := 0
@export var hp_cost := 0
@export var granted_spell: SpellData
@export var relic_effect := RelicEffect.NONE


func describe() -> String:
	match type:
		Type.WEAPON:
			return "%s (+%d ATK)" % [display_name, attack_bonus]
		Type.ARMOR:
			return "%s (+%d DEF)" % [display_name, defense_bonus]
		Type.MANA_POTION:
			return "%s (+%d spell charges)" % [display_name, charge_restore]
		Type.SPELL_ORB:
			return "%s (+%d SP)" % [display_name, sp_amount]
		Type.RELIC:
			return "? %s" % display_name
		Type.SPELL_PEDESTAL:
			return "★ Spell: %s" % display_name
		_:
			return "%s (heals %d)" % [display_name, heal_amount]


func type_name() -> String:
	match type:
		Type.WEAPON:
			return "Weapon  •  +%d ATK" % attack_bonus
		Type.ARMOR:
			return "Armor  •  +%d DEF" % defense_bonus
		Type.MANA_POTION:
			return "Consumable  •  +%d Spell Charges" % charge_restore
		Type.SPELL_ORB:
			return "Artifact  •  +%d Spell Points" % sp_amount
		Type.RELIC:
			if hp_cost > 0:
				return "Devil Deal Relic  •  Costs %d Max HP" % hp_cost
			return "Rare Relic  •  Permanent Passive"
		Type.SPELL_PEDESTAL:
			if hp_cost > 0:
				return "Devil Deal Spell  •  Costs %d Max HP" % hp_cost
			return "Angel Blessing Spell  •  Free"
		Type.DEVIL_PORTAL:
			return "Devil Room Portal (Earned via Speed-Clear!)"
		Type.ANGEL_PORTAL:
			return "Angel Room Portal (Earned via Flawless Clear!)"
		Type.RETURN_PORTAL:
			return "Sanctuary Exit Portal"
		_:
			return "Consumable  •  Restores %d HP" % heal_amount


func describe_details() -> String:
	if description.is_empty():
		return type_name()
	return "%s\n%s" % [type_name(), description]
