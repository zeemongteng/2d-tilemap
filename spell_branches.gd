class_name SpellBranches
extends RefCounted
## Upgrade-branch catalog. Leveling a spell asks the player to pick one branch.
## Tier 1 is offered at Lv.1 -> 2, tier 2 at Lv.2+. A branch with an `after` id only appears once that branch is owned.
## "stats" are summed by SpellData.branch_stat(); every other effect is a flag checked via SpellData.has_branch(id).

static var _catalog: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func catalog() -> Array[Dictionary]:
	if _catalog.is_empty():
		_build()
	return _catalog


static func get_branch(branch_id: String) -> Dictionary:
	if _by_id.is_empty():
		_build()
	return _by_id.get(branch_id, {})


static func _add(id: String, branch_name: String, desc: String, tier: int, element: int, pattern: int, after: String, needs: String, stats := {}) -> void:
	var entry := {
		"id": id,
		"name": branch_name,
		"desc": desc,
		"tier": tier,
		"element": element,
		"pattern": pattern,
		"after": after,
		"needs": needs,
		"stats": stats,
	}
	_catalog.append(entry)
	_by_id[id] = entry


static func _build() -> void:
	_catalog.clear()
	_by_id.clear()
	var E = SpellData.Element
	var P = SpellData.Pattern

	# --- Tier 1: element paths -------------------------------------------
	_add("fire_spread", "Wildfire", "Every foe struck sets adjacent foes ablaze (Burn 2t).", 1, E.FIRE, -1, "", "offense")
	_add("light_static", "Static Charge", "Foes struck are Shocked for 2 turns.", 1, E.LIGHTNING, -1, "", "offense")
	_add("ice_deep", "Deep Freeze", "+2 damage and +1 status duration.", 1, E.ICE, -1, "", "offense", {"damage": 2, "status_duration": 1})
	_add("arc_focus", "Arcane Focus", "+2 damage and +2 range.", 1, E.ARCANE, -1, "", "offense", {"damage": 2, "range": 2})
	_add("nat_virulent", "Virulent Strain", "+1 damage and +2 status duration.", 1, E.NATURE, -1, "", "offense", {"damage": 1, "status_duration": 2})
	_add("dark_siphon", "Soul Siphon", "+1 damage. Heal 2 HP per foe struck.", 1, E.DARK, -1, "", "offense", {"damage": 1, "heal": 2})
	_add("holy_radiance", "Radiance", "+3 damage.", 1, E.HOLY, -1, "", "offense", {"damage": 3})

	# --- Tier 1: pattern paths -------------------------------------------
	_add("single_marksman", "Marksman", "+2 damage and +3 range.", 1, -1, P.SINGLE, "", "", {"damage": 2, "range": 3})
	_add("blast_wide", "Wide Burst", "+1 blast radius.", 1, -1, P.BLAST, "", "", {"radius": 1})
	_add("beam_long", "Long Reach", "+3 range and +1 max charge.", 1, -1, P.BEAM, "", "", {"range": 3, "charges": 1})
	_add("chain_forks", "Forking Arcs", "+2 chain jumps and +1 jump range.", 1, -1, P.CHAIN, "", "", {"jumps": 2, "radius": 1})
	_add("blink_pulse", "Shockwave Arrival", "+3 damage and +1 arrival pulse radius.", 1, -1, P.BLINK, "", "", {"damage": 3, "radius": 1})
	_add("nova_wide", "Expanding Ring", "+1 nova radius and +1 max charge.", 1, -1, P.NOVA, "", "", {"radius": 1, "charges": 1})
	_add("summon_hardy", "Hardened Servants", "Summons gain +8 HP and +2 ATK.", 1, -1, P.SUMMON, "", "", {"summon_hp": 8, "summon_atk": 2})
	_add("dash_blade", "Slipstream Blade", "The dash cuts every foe along its path for 5 damage.", 1, -1, P.DASH, "", "", {"damage": 5})

	# --- Tier 1: general paths -------------------------------------------
	_add("gen_potency", "Potency", "+3 damage.", 1, -1, -1, "", "damage", {"damage": 3})
	_add("gen_overcharge", "Overcharge", "+3 max charges (or -1 turn of cooldown).", 1, -1, -1, "", "", {"charges": 3, "cooldown": -1})

	# --- Tier 2: element capstones ---------------------------------------
	_add("fire_cremate", "Cremation", "Foes slain by this spell explode for 4 damage to adjacent foes.", 2, E.FIRE, -1, "fire_spread", "offense")
	_add("light_thunder", "Thunderclap", "Foes struck are also Stunned for 1 turn.", 2, E.LIGHTNING, -1, "light_static", "offense")
	_add("ice_whiteout", "Whiteout", "Foes adjacent to every target are Frozen for 1 turn.", 2, E.ICE, -1, "ice_deep", "offense")
	_add("arc_surge", "Arcane Surge", "Casting refunds 1 charge (or 1 turn of cooldown) on a random other spell.", 2, E.ARCANE, -1, "arc_focus", "offense")
	_add("nat_bloom", "Overgrowth", "Heal 3 HP per foe struck and +1 status duration.", 2, E.NATURE, -1, "nat_virulent", "offense", {"heal": 3, "status_duration": 1})
	_add("dark_curse", "Hexbind", "Foes struck are Hexed for 2 turns (+50% damage taken).", 2, E.DARK, -1, "dark_siphon", "offense")
	_add("holy_aegis", "Aegis", "Casting grants a Holy Mantle shield if you have none.", 2, E.HOLY, -1, "holy_radiance", "offense")

	# --- Tier 2: pattern capstones ---------------------------------------
	_add("single_twin", "Twin Bolt", "Also strikes the nearest other foe within 3 hexes of the target.", 2, -1, P.SINGLE, "single_marksman", "")
	_add("blast_epicenter", "Epicenter", "The targeted hex takes double damage.", 2, -1, P.BLAST, "blast_wide", "")
	_add("beam_lance", "Lance", "+5 damage.", 2, -1, P.BEAM, "beam_long", "", {"damage": 5})
	_add("chain_conduit", "Conduit", "+2 chain jumps and +3 damage.", 2, -1, P.CHAIN, "chain_forks", "", {"jumps": 2, "damage": 3})
	_add("blink_phase", "Phase Cloak", "Gain Evasion for 1 turn after teleporting.", 2, -1, P.BLINK, "blink_pulse", "")
	_add("nova_cascade", "Cascade", "Refunds the cast if the nova strikes 3 or more foes.", 2, -1, P.NOVA, "nova_wide", "")
	_add("summon_pack", "Pack Tactics", "Summons a second ally on an adjacent hex.", 2, -1, P.SUMMON, "summon_hardy", "")
	_add("dash_adrenaline", "Adrenaline", "-1 turn of cooldown and Evasion lasts 2 turns.", 2, -1, P.DASH, "dash_blade", "", {"cooldown": -1})

	# --- Tier 2: general paths -------------------------------------------
	_add("gen_spellweaver", "Spellweaver", "30% chance to cast this spell for free.", 2, -1, -1, "", "")
	_add("gen_executioner", "Executioner", "Double damage against foes below 35% HP.", 2, -1, -1, "", "damage")
	_add("gen_overdrive", "Overdrive", "+5 damage, but -2 max charges (+1 turn of cooldown).", 2, -1, -1, "", "damage", {"damage": 5, "charges": -2, "cooldown": 1})


static func _applies(spell: SpellData, entry: Dictionary) -> bool:
	match str(entry["needs"]):
		"damage":
			return spell.damage > 0
		"offense":
			return spell.pattern != SpellData.Pattern.SUMMON and spell.pattern != SpellData.Pattern.DASH
	return true


## Branches the player may pick for this spell's next level-up.
static func offers_for(spell: SpellData) -> Array[Dictionary]:
	var tier := 1 if spell.level <= 1 else 2
	var result: Array[Dictionary] = []
	for entry in catalog():
		if int(entry["tier"]) != tier or spell.has_branch(str(entry["id"])):
			continue
		var el := int(entry["element"])
		if el != -1 and el != int(spell.element):
			continue
		var pat := int(entry["pattern"])
		if pat != -1 and pat != int(spell.pattern):
			continue
		var after := str(entry["after"])
		if after != "" and not spell.has_branch(after):
			continue
		if not _applies(spell, entry):
			continue
		result.append(entry)
	return result
