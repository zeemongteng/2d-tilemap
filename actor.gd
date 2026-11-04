class_name Actor
extends Node2D
## Anything that occupies one (or 7, for bosses) hexes and takes a turn: the player, monsters, spawners, bosses.

@export var display_name := "Actor"
@export_multiline var description := ""
@export var glyph := "@"
@export var color := Color.WHITE
@export var font_size := 28
@export var stats: Stats
## Chance (0-1) of dropping a random item on death.
@export var loot_chance := 0.0

@export_group("Monster Abilities")
@export var is_allies := false
@export var attack_range := 1
@export var regen_per_turn := 0
@export var is_spawner := false
@export var spawn_interval := 4
@export var spawn_scene: PackedScene
@export var is_boss := false
@export var footprint_radius := 0
@export var slam_damage := 7
## Earliest room this monster can randomly appear in.
@export var min_room := 1
## Inflicted on the target by this actor's melee and ranged hits.
@export var on_hit_status: StatusData
@export var on_hit_status_duration := 3
## On death, deals this much damage to every other creature within death_blast_radius hexes.
@export var death_blast_damage := 0
@export var death_blast_radius := 1
## On death, splits into this many copies of death_spawn_scene.
@export var death_spawn_scene: PackedScene
@export var death_spawn_count := 2

var cell := Vector2i.ZERO
var grid: HexGrid
var inventory: Array[ItemData] = []
var relics: Array[ItemData] = []
var spells: Array[SpellData] = []
var statuses: Array[StatusData] = []
var spell_points := 2
var weapon: ItemData
var armor: ItemData

var spawn_cooldown := 3
var ability_cooldown := 2
var ability2_cooldown := 3
var telegraph_mode := 0
var telegraph_cells: Array[Vector2i] = []
var is_enraged := false
var was_charmed_enemy := false
var holy_mantle_shield := false
var evade_turns := 0
var phoenix_charges := 0
var is_elite := false
var elite_color := Color.WHITE


func _ready() -> void:
	# Scene sub-resources are shared between instances, so each actor gets its own copy.
	if stats == null:
		stats = Stats.new()
	else:
		stats = stats.duplicate() as Stats
	stats.hp = stats.max_hp
	spawn_cooldown = maxi(1, spawn_interval - 1)


func place(target_grid: HexGrid, target_cell: Vector2i) -> void:
	grid = target_grid
	cell = target_cell
	position = grid.cell_to_pixel(cell)
	queue_redraw()


func move_to(target_cell: Vector2i, duration: float) -> Tween:
	cell = target_cell
	var tween := create_tween()
	tween.tween_property(self, "position", grid.cell_to_pixel(cell), duration)
	return tween


## Returns all hex cells occupied by this actor (1 hex for normal actors, 7 hexes when footprint_radius == 1).
func occupied_cells_at(center_cell: Vector2i) -> Array[Vector2i]:
	if footprint_radius <= 0:
		return [center_cell]
	var result: Array[Vector2i] = []
	for dq in range(-footprint_radius, footprint_radius + 1):
		for dr in range(maxi(-footprint_radius, -dq - footprint_radius), mini(footprint_radius, -dq + footprint_radius) + 1):
			result.append(center_cell + Vector2i(dq, dr))
	return result


func occupied_cells() -> Array[Vector2i]:
	return occupied_cells_at(cell)


func occupies_cell(target_cell: Vector2i) -> bool:
	return HexGrid.distance(cell, target_cell) <= footprint_radius


## Minimum hex distance from any hex occupied by this actor to `target_cell`.
func distance_to_cell(target_cell: Vector2i) -> int:
	return maxi(0, HexGrid.distance(cell, target_cell) - footprint_radius)


func total_attack() -> int:
	return stats.attack + (weapon.attack_bonus if weapon != null else 0)


func total_defense() -> int:
	return stats.defense + (armor.defense_bonus if armor != null else 0)


func total_spell_damage_bonus() -> int:
	var bonus := 0
	for r in relics:
		bonus += r.spell_damage_bonus
	if weapon != null:
		bonus += weapon.spell_damage_bonus
	if armor != null:
		bonus += armor.spell_damage_bonus
	return bonus


func total_spell_range_bonus() -> int:
	var bonus := 0
	for r in relics:
		bonus += r.spell_range_bonus
	return bonus


func total_burn_damage_bonus() -> int:
	var bonus := 0
	for r in relics:
		bonus += r.burn_damage_bonus
	return bonus


func total_status_duration_bonus() -> int:
	var bonus := 0
	for r in relics:
		bonus += r.status_duration_bonus
	return bonus


func total_afflicted_damage_bonus() -> int:
	var bonus := 0
	for r in relics:
		bonus += r.afflicted_damage_bonus
	return bonus


## Number of other (non-innate) spells known that share this spell's element.
func element_mastery_count(element: int) -> int:
	var count := 0
	for s in spells:
		if not s.is_innate and int(s.element) == element:
			count += 1
	return count


## Spell-school synergy: +2 damage per other known spell of the same element (max +4).
func element_mastery_bonus(spell: SpellData) -> int:
	var others := element_mastery_count(int(spell.element))
	if not spell.is_innate and spells.has(spell):
		others -= 1
	return 2 * clampi(others, 0, 2)


func add_relic(relic: ItemData) -> void:
	relics.append(relic)
	if relic.attack_bonus > 0:
		stats.attack += relic.attack_bonus
	if relic.defense_bonus > 0:
		stats.defense += relic.defense_bonus
	if relic.max_hp_bonus > 0:
		stats.max_hp += relic.max_hp_bonus
		heal(relic.max_hp_bonus)
	if relic.relic_effect == ItemData.RelicEffect.SACRED_HEART:
		stats.hp = stats.max_hp
	if relic.relic_effect == ItemData.RelicEffect.HOLY_MANTLE:
		holy_mantle_shield = true
	if relic.relic_effect == ItemData.RelicEffect.PHOENIX_FEATHER:
		phoenix_charges += 1
	queue_redraw()


func refresh_room_shields() -> void:
	holy_mantle_shield = has_relic(ItemData.RelicEffect.HOLY_MANTLE)
	evade_turns = 0
	queue_redraw()


func count_relic(effect: ItemData.RelicEffect) -> int:
	var total := 0
	for r in relics:
		if r.relic_effect == effect:
			total += 1
	return total


func has_relic(effect: ItemData.RelicEffect) -> bool:
	return count_relic(effect) > 0


# --- modular status system ------------------------------------------------

func apply_status(template: StatusData, duration_override := -1, bonus_dot_damage := 0) -> void:
	if template == null:
		return
	if template.charms_actor and is_boss:
		return
	for cancel_id in template.cancels_status_ids:
		remove_status(cancel_id)
	var dur := duration_override if duration_override > 0 else template.default_duration
	var existing := get_status(template.id)
	if existing != null:
		existing.turns_left = maxi(existing.turns_left, dur)
		if template.damage_per_turn > 0 or bonus_dot_damage > 0:
			existing.damage_per_turn = maxi(existing.damage_per_turn, template.damage_per_turn + bonus_dot_damage)
	else:
		statuses.append(template.init_runtime(dur, bonus_dot_damage))
	if template.charms_actor and not is_allies:
		is_allies = true
		was_charmed_enemy = true
	queue_redraw()


func get_status(status_id: String) -> StatusData:
	for s in statuses:
		if s.id == status_id:
			return s
	return null


func has_status(status_id: String) -> bool:
	return get_status(status_id) != null


func has_any_status() -> bool:
	return not statuses.is_empty()


func is_charmed() -> bool:
	for s in statuses:
		if s.charms_actor:
			return true
	return false


func is_feared() -> bool:
	for s in statuses:
		if s.fears_actor:
			return true
	return false


func sync_charm_allegiance() -> bool:
	if was_charmed_enemy and not is_charmed():
		is_allies = false
		was_charmed_enemy = false
		queue_redraw()
		return true
	return false


func remove_status(status_id: String) -> void:
	for i in range(statuses.size() - 1, -1, -1):
		if statuses[i].id == status_id:
			statuses.remove_at(i)
	sync_charm_allegiance()
	queue_redraw()


func skips_turn_from_status() -> bool:
	for s in statuses:
		if s.skips_turn:
			return true
	return false


func tick_skip_turn_statuses() -> void:
	for i in range(statuses.size() - 1, -1, -1):
		if statuses[i].skips_turn:
			statuses[i].turns_left -= 1
			if statuses[i].turns_left <= 0:
				statuses.remove_at(i)
	queue_redraw()


func blocks_regen_from_status() -> bool:
	for s in statuses:
		if s.blocks_regen:
			return true
	return false


func incoming_damage_multiplier() -> float:
	var mult := 1.0
	for s in statuses:
		mult *= s.incoming_damage_multiplier
	return mult


func consume_shatter_statuses() -> bool:
	var shattered := false
	for i in range(statuses.size() - 1, -1, -1):
		if statuses[i].shatters_on_hit:
			statuses.remove_at(i)
			shattered = true
	if shattered:
		queue_redraw()
	return shattered


func describe_statuses() -> String:
	var parts: Array[String] = []
	for s in statuses:
		parts.append(s.summary_text())
	return ", ".join(parts)


# --- combat & equipment ---------------------------------------------------

func is_dead() -> bool:
	return stats.hp <= 0


func take_damage(amount: int, flash_color := Color(1, 0.3, 0.3)) -> int:
	if evade_turns > 0 and amount > 0:
		modulate = Color(0.5, 1.0, 0.9)
		create_tween().tween_property(self, "modulate", Color.WHITE, 0.25)
		queue_redraw()
		return 0
	if holy_mantle_shield and amount > 0:
		holy_mantle_shield = false
		modulate = Color(0.55, 0.95, 1.0)
		create_tween().tween_property(self, "modulate", Color.WHITE, 0.3)
		queue_redraw()
		return 0
	stats.hp = maxi(0, stats.hp - amount)
	if stats.hp <= 0 and phoenix_charges > 0:
		phoenix_charges -= 1
		stats.hp = maxi(1, stats.max_hp / 2)
		statuses.clear()
		flash_color = Color(1.0, 0.85, 0.3)
	modulate = flash_color
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.25)
	queue_redraw()
	return amount


func heal(amount: int) -> void:
	stats.hp = mini(stats.max_hp, stats.hp + amount)
	queue_redraw()


func learn_spell(template: SpellData) -> SpellData:
	var existing := get_learned_spell(template.display_name)
	if existing != null:
		return existing
	var instance := template.init_runtime()
	spells.append(instance)
	return instance


func get_learned_spell(spell_name: String) -> SpellData:
	for s in spells:
		if s.display_name == spell_name:
			return s
	return null


func restore_all_spells(amount: int) -> void:
	for s in spells:
		s.restore_charges(amount)


func recharge_all_spells() -> void:
	for s in spells:
		if s.uses_cooldown():
			s.cooldown_remaining = 0
		else:
			s.charges = s.effective_max_charges()


func tick_spell_cooldowns() -> void:
	for s in spells:
		s.tick_cooldown()


## Equips a weapon or armor; the replaced piece goes back into the inventory.
func equip(item: ItemData) -> void:
	var old: ItemData
	if item.type == ItemData.Type.WEAPON:
		old = weapon
		weapon = item
	else:
		old = armor
		armor = item
	if old != null:
		inventory.append(old)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var draw_col := color
	if not statuses.is_empty():
		draw_col = color.lerp(statuses[0].color, 0.6)

	# Draw 7-hex armored boss footprint plates if footprint_radius > 0.
	if footprint_radius > 0 and grid != null:
		var plate_fill := Color(draw_col.r, draw_col.g, draw_col.b, 0.26)
		var plate_border := Color(draw_col.r, draw_col.g, draw_col.b, 0.88)
		var center_px := grid.cell_to_pixel(cell)
		for occ in occupied_cells():
			var rel_center := grid.cell_to_pixel(occ) - center_px
			var poly := PackedVector2Array()
			for i in 6:
				var angle := deg_to_rad(60.0 * i - 30.0)
				poly.append(rel_center + Vector2(cos(angle), sin(angle)) * (grid.hex_size * 0.92))
			draw_colored_polygon(poly, plate_fill)
			poly.append(poly[0])
			draw_polyline(poly, plate_border, 2.2)
			if occ != cell:
				draw_circle(rel_center, 5.0, plate_border)

	if is_spawner:
		draw_arc(Vector2.ZERO, font_size * 0.58, 0.0, TAU, 24, Color(draw_col.r, draw_col.g, draw_col.b, 0.45), 2.0)
	elif was_charmed_enemy:
		draw_arc(Vector2.ZERO, font_size * 0.54, 0.0, TAU, 20, Color(1.0, 0.45, 0.85, 0.85), 2.2)
	elif is_allies and glyph != "@":
		draw_arc(Vector2.ZERO, font_size * 0.52, 0.0, TAU, 20, Color(0.3, 0.95, 0.65, 0.55), 2.0)
	if is_enraged:
		draw_arc(Vector2.ZERO, font_size * 0.76, 0.0, TAU, 28, Color(1.0, 0.35, 0.15, 0.9), 2.5)
	if is_elite:
		draw_arc(Vector2.ZERO, font_size * 0.7, 0.0, TAU, 28, Color(elite_color.r, elite_color.g, elite_color.b, 0.9), 2.4)
		draw_arc(Vector2.ZERO, font_size * 0.78, 0.0, TAU, 28, Color(elite_color.r, elite_color.g, elite_color.b, 0.4), 1.4)
	if holy_mantle_shield:
		draw_arc(Vector2.ZERO, font_size * 0.62, 0.0, TAU, 24, Color(0.55, 0.92, 1.0, 0.85), 2.2)
	if evade_turns > 0:
		draw_arc(Vector2.ZERO, font_size * 0.72, 0.0, TAU, 24, Color(0.45, 0.98, 0.9, 0.9), 2.2)

	var offset := Vector2(-font_size, font_size * 0.35)
	draw_string(font, offset, glyph, HORIZONTAL_ALIGNMENT_CENTER, font_size * 2.0, font_size, draw_col)

	var badge_y := -font_size * 0.38 if footprint_radius == 0 else -font_size * 0.65
	if not statuses.is_empty():
		var badges: Array[String] = []
		for s in statuses:
			badges.append(s.badge_text())
		draw_string(font, Vector2(-font_size, badge_y), " ".join(badges), HORIZONTAL_ALIGNMENT_CENTER, font_size * 2.0, 13, statuses[0].color)
	elif is_spawner:
		var timer_txt := "⏳%d" % spawn_cooldown if spawn_cooldown > 1 else "!"
		draw_string(font, Vector2(-font_size, badge_y), timer_txt, HORIZONTAL_ALIGNMENT_CENTER, font_size * 2.0, 12, Color(0.95, 0.65, 1.0))

	if stats != null and stats.hp < stats.max_hp and stats.hp > 0:
		var bar_w := 64.0 if is_boss else 24.0
		var bar_h := 5.0 if is_boss else 3.5
		var ratio := clampf(float(stats.hp) / float(stats.max_hp), 0.0, 1.0)
		var bar_pos := Vector2(-bar_w * 0.5, font_size * 0.48)
		var fill_col := Color(0.25, 0.92, 0.55, 0.95) if is_allies else Color(0.95, 0.2, 0.25, 0.95)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.15, 0.05, 0.05, 0.85))
		draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), fill_col)
