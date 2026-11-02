class_name ItemData
extends Resource

enum Type { WEAPON, ARMOR, POTION, MANA_POTION, SPELL_ORB }

@export var display_name := "Item"
@export_multiline var description := ""
@export var glyph := "?"
@export var color := Color.WHITE
@export var type := Type.POTION
@export var attack_bonus := 0
@export var defense_bonus := 0
@export var heal_amount := 0
@export var charge_restore := 0
@export var sp_amount := 0


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
		_:
			return "Consumable  •  Restores %d HP" % heal_amount


func describe_details() -> String:
	if description.is_empty():
		return type_name()
	return "%s\n%s" % [type_name(), description]
