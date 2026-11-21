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
	CURSED_PENNY,
	CRACKED_DICE,
	SOUR_CANDY,
	BEGGARS_CUP,
	THORN_RING,
	BLOOD_VIAL,
	POCKET_SAND,
	PEN_NIB,
	SNECKO_EYE,
	CROWBAR,
	WILL_O_THE_WISP,
	POLYPHEMUS,
	TINKER_WANDS,
	THUNDERSTONE,
	HOLOGRAM_BRACELET,
}

@export var display_name := "Item"
@export_multiline var description := ""
@export var glyph := "?"
@export var color := Color.WHITE
@export var type := Type.POTION
## Quality tier from 0 (Basic) to 4 (Mythic / Strongest).
@export_range(0, 4) var tier := 1
@export var attack_bonus := 0
@export var defense_bonus := 0
@export var max_hp_bonus := 0
@export var spell_damage_bonus := 0
@export var spell_range_bonus := 0
@export var max_charges_bonus := 0
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
## Active cooldown ability granted while this weapon is equipped.
@export var weapon_skill: SpellData
@export var relic_effect := RelicEffect.NONE
## Status inflicted on foes by the wielder's melee hits (weapons and relics).
@export var on_hit_status: StatusData
@export var on_hit_status_duration := 3
## Bombs: damage dealt to every foe within blast_radius hexes of the user.
@export var blast_damage := 0
@export var blast_radius := 1

var runtime_weapon_skill: SpellData


func get_weapon_skill() -> SpellData:
	if weapon_skill == null:
		return null
	if runtime_weapon_skill == null:
		runtime_weapon_skill = weapon_skill.init_runtime()
	return runtime_weapon_skill


func gear_extras() -> String:
	var parts: Array[String] = []
	if spell_damage_bonus != 0:
		parts.append("%+d Spell DMG" % spell_damage_bonus)
	if on_hit_status != null:
		parts.append("inflicts %s" % on_hit_status.display_name)
	if weapon_skill != null:
		parts.append("Skill: %s (%dt CD)" % [weapon_skill.display_name, weapon_skill.cooldown_turns])
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


func has_tier() -> bool:
	return type not in [
		Type.DEVIL_PORTAL,
		Type.ANGEL_PORTAL,
		Type.TREASURE_PORTAL,
		Type.SHOP_PORTAL,
		Type.RETURN_PORTAL,
		Type.SHRINE_OF_CHANCE,
		Type.BLOOD_ALTAR,
	]


func tier_name() -> String:
	match clampi(tier, 0, 4):
		0:
			return "Tier 0 • Basic"
		1:
			return "Tier 1 • Common"
		2:
			return "Tier 2 • Rare"
		3:
			return "Tier 3 • Epic"
		_:
			return "Tier 4 • Mythic"


func tier_color() -> Color:
	match clampi(tier, 0, 4):
		0:
			return Color(0.68, 0.68, 0.72)
		1:
			return Color(0.88, 0.92, 0.96)
		2:
			return Color(0.38, 0.78, 1.0)
		3:
			return Color(0.82, 0.45, 1.0)
		_:
			return Color(1.0, 0.82, 0.25)


func _tier_prefix() -> String:
	return "[%s]  " % tier_name() if has_tier() else ""


func type_name() -> String:
	var tp := _tier_prefix()
	match type:
		Type.WEAPON:
			return "%sWeapon  •  +%d ATK%s%s" % [tp, attack_bonus, gear_extras(), _cost_suffix()]
		Type.ARMOR:
			return "%sArmor  •  +%d DEF%s%s" % [tp, defense_bonus, gear_extras(), _cost_suffix()]
		Type.BOMB:
			return "%sConsumable  •  %d DMG to all foes within %d hex%s" % [tp, blast_damage, blast_radius, _cost_suffix()]
		Type.PILL:
			return "%sConsumable  •  Unknown effect — gamble!%s" % [tp, _cost_suffix()]
		Type.MANA_POTION:
			return "%sConsumable  •  +%d Spell Charges%s" % [tp, charge_restore, _cost_suffix()]
		Type.POTION when max_hp_bonus > 0:
			return "%sConsumable  •  Restores %d HP, +%d Max HP%s" % [tp, heal_amount, max_hp_bonus, _cost_suffix()]
		Type.SPELL_ORB:
			return "%sArtifact  •  +%d Souls%s" % [tp, sp_amount, _cost_suffix()]
		Type.GOLD:
			return "%sCoin Pickup  •  +%d¢" % [tp, gold_amount]
		Type.RELIC:
			if gold_cost > 0:
				var rel_sale := " (50% OFF SALE!)" if is_on_sale else ""
				return "%sShop Relic  •  Price: %d¢%s" % [tp, gold_cost, rel_sale]
			if hp_cost > 0:
				return "%sDevil Deal Relic  •  Costs %d Max HP" % [tp, hp_cost]
			return "%sRelic  •  Permanent Passive" % tp
		Type.SPELL_PEDESTAL:
			if gold_cost > 0:
				var sp_sale := " (50% OFF SALE!)" if is_on_sale else ""
				return "%sShop Spell Tome  •  Price: %d¢%s" % [tp, gold_cost, sp_sale]
			if hp_cost > 0:
				return "%sDevil Deal Spell  •  Costs %d Max HP" % [tp, hp_cost]
			return "%sAngel Blessing Spell  •  Free" % tp
		Type.DEVIL_PORTAL:
			return "Devil Room Portal (Boss Deal)"
		Type.ANGEL_PORTAL:
			return "Angel Room Portal (Boss Deal)"
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
			return "%sConsumable  •  Restores %d HP%s" % [tp, heal_amount, _cost_suffix()]


func describe_details() -> String:
	if description.is_empty():
		return type_name()
	return "%s\n%s" % [type_name(), description]
