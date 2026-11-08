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
	TREASURE_PORTAL,
	RETURN_PORTAL,
	SPELL_PEDESTAL,
	BOMB,
	PILL,
	GOLD,
	SHOP_PORTAL,
	SHRINE_OF_CHANCE,
	BLOOD_ALTAR,
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
	GLASS_CANNON,
	PHOENIX_FEATHER,
	GASOLINE,
	VENOM_FANG,
	BANDOLIER,
	SOUL_VESSEL,
	UKULELE,
	LUCKY_PENNY,
	HAWKS_LENS,
	FAMILIARS_TOME,
	ECHO_MIRROR,
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
@export var gold_amount := 0
@export var hp_cost := 0
@export var gold_cost := 0
@export var is_on_sale := false
@export var uses_left := 2
@export var granted_spell: SpellData
@export var relic_effect := RelicEffect.NONE
## Status inflicted on foes by the wielder's melee hits (weapons and relics).
@export var on_hit_status: StatusData
@export var on_hit_status_duration := 3
## Bombs: damage dealt to every foe within blast_radius hexes of the user.
@export var blast_damage := 0
@export var blast_radius := 1


func gear_extras() -> String:
	var parts: Array[String] = []
	if spell_damage_bonus != 0:
		parts.append("%+d Spell DMG" % spell_damage_bonus)
	if on_hit_status != null:
		parts.append("inflicts %s" % on_hit_status.display_name)
	if parts.is_empty():
		return ""
	return "  •  " + ", ".join(parts)


func describe() -> String:
	match type:
		Type.WEAPON:
			return "%s (+%d ATK)" % [display_name, attack_bonus]
		Type.ARMOR:
			return "%s (+%d DEF)" % [display_name, defense_bonus]
		Type.MANA_POTION:
			return "%s (+%d spell charges)" % [display_name, charge_restore]
		Type.SPELL_ORB:
			return "%s (+%d Souls)" % [display_name, sp_amount]
		Type.RELIC:
			return "? %s" % display_name
		Type.SPELL_PEDESTAL:
			return "★ Spell: %s" % display_name
		Type.BOMB:
			return "%s (%d DMG blast)" % [display_name, blast_damage]
		Type.PILL:
			return "%s (???)" % display_name
		Type.GOLD:
			return "%s (+%d¢)" % [display_name, gold_amount]
		Type.SHRINE_OF_CHANCE:
			return "%s (%d¢)" % [display_name, gold_cost]
		Type.BLOOD_ALTAR:
			return "%s (-%d HP)" % [display_name, hp_cost]
		_:
			return "%s (heals %d)" % [display_name, heal_amount]


func _cost_suffix() -> String:
	if gold_cost > 0:
		var sale_note := " (50% OFF SALE!)" if is_on_sale else ""
		return "  •  Shop Price: %d¢%s" % [gold_cost, sale_note]
	if hp_cost > 0:
		return "  •  Costs %d HP" % hp_cost
	return ""


func type_name() -> String:
	match type:
		Type.WEAPON:
			return "Weapon  •  +%d ATK%s%s" % [attack_bonus, gear_extras(), _cost_suffix()]
		Type.ARMOR:
			return "Armor  •  +%d DEF%s%s" % [defense_bonus, gear_extras(), _cost_suffix()]
		Type.BOMB:
			return "Consumable  •  %d DMG to all foes within %d hex%s" % [blast_damage, blast_radius, _cost_suffix()]
		Type.PILL:
			return "Consumable  •  Unknown effect — gamble!%s" % _cost_suffix()
		Type.MANA_POTION:
			return "Consumable  •  +%d Spell Charges%s" % [charge_restore, _cost_suffix()]
		Type.POTION when max_hp_bonus > 0:
			return "Consumable  •  Restores %d HP, +%d Max HP%s" % [heal_amount, max_hp_bonus, _cost_suffix()]
		Type.SPELL_ORB:
			return "Artifact  •  +%d Souls%s" % [sp_amount, _cost_suffix()]
		Type.GOLD:
			return "Coin Pickup  •  +%d¢" % gold_amount
		Type.RELIC:
			if gold_cost > 0:
				var rel_sale := " (50% OFF SALE!)" if is_on_sale else ""
				return "Shop Relic  •  Price: %d¢%s" % [gold_cost, rel_sale]
			if hp_cost > 0:
				return "Devil Deal Relic  •  Costs %d Max HP" % hp_cost
			return "Rare Relic  •  Permanent Passive"
		Type.SPELL_PEDESTAL:
			if gold_cost > 0:
				var sp_sale := " (50% OFF SALE!)" if is_on_sale else ""
				return "Shop Spell Tome  •  Price: %d¢%s" % [gold_cost, sp_sale]
			if hp_cost > 0:
				return "Devil Deal Spell  •  Costs %d Max HP" % hp_cost
			return "Angel Blessing Spell  •  Free"
		Type.DEVIL_PORTAL:
			return "Devil Room Portal (Earned via Speed-Clear!)"
		Type.ANGEL_PORTAL:
			return "Angel Room Portal (Earned via Flawless Clear!)"
		Type.TREASURE_PORTAL:
			return "Golden Treasure Room Portal"
		Type.SHOP_PORTAL:
			return "Merchant Shop Portal (Spend Coins!)"
		Type.RETURN_PORTAL:
			return "Sanctuary Exit Portal"
		Type.SHRINE_OF_CHANCE:
			return "Risk of Rain Altar  •  Offer %d¢ (%d blessing(s) left)" % [gold_cost, uses_left]
		Type.BLOOD_ALTAR:
			return "Blood Altar  •  Sacrifice %d HP → Coins & Reward (%d left)" % [hp_cost, uses_left]
		_:
			return "Consumable  •  Restores %d HP%s" % [heal_amount, _cost_suffix()]


func describe_details() -> String:
	if description.is_empty():
		return type_name()
	return "%s\n%s" % [type_name(), description]
