extends Node2D
## Turn loop: every player action (a step, an attack, casting a spell, using an item, waiting)
## is followed by one action from each monster. Clicking a far hex auto-walks
## one step per turn.

const STEP_TIME := 0.08
const MAX_INVENTORY := 9
const SPELL_HOTKEYS: Array[Key] = [KEY_Q, KEY_W, KEY_E, KEY_F, KEY_G, KEY_C]

@export var player_scene: PackedScene
@export var monster_scene: PackedScene
@export var monster_pool: Array[PackedScene]
@export var spawner_scene: PackedScene
@export var boss_scene: PackedScene
@export var world_item_scene: PackedScene
@export var item_pool: Array[Resource]
@export var relic_pool: Array[Resource]
@export var starting_items: Array[Resource]
@export var starting_spells: Array[Resource]
@export var spell_catalog: Array[Resource]
@export var monster_count := 6
@export var spawner_count := 2
@export var item_count := 7
@export var relic_spawn_chance := 0.45
@export var monster_sight := 6

@onready var grid: HexGrid = $HexGrid
@onready var hud: Hud = $Hud

var player: Actor
var monsters: Array[Actor] = []
var items: Array[WorldItem] = []
var turn := 0
var room_level := 1
var _room_cleared := false
var _kills := 0
var _busy := false
var _dead := false
var _cancel_walk := false
var _active_spell_index := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	grid.generate()

	var typed_catalog: Array[SpellData] = []
	for res in spell_catalog:
		if res is SpellData:
			typed_catalog.append(res as SpellData)
	hud.set_spell_catalog(typed_catalog)
	hud.spell_selected.connect(_on_hud_spell_selected)
	hud.item_selected.connect(_on_hud_item_selected)
	hud.spell_learn_requested.connect(_on_spell_learn_requested)
	hud.spell_upgrade_requested.connect(_on_spell_upgrade_requested)
	hud.next_room_confirmed.connect(_on_next_room_confirmed)

	player = _spawn_actor(player_scene, Vector2i.ZERO)
	for res in starting_items:
		if res is ItemData:
			player.inventory.append(res as ItemData)
	for res in starting_spells:
		if res is SpellData:
			player.learn_spell(res as SpellData)

	_populate_current_room(Vector2i.ZERO)
	hud.post("Clear all foes, then walk to any green edge passage to enter the next room!")
	_refresh_hud()


func _process(_delta: float) -> void:
	$Camera2D.position = player.position


# --- room generation & spawning -------------------------------------------

static func _is_boss_room(room_num: int) -> bool:
	return room_num >= 2 and (room_num - 2) % 3 == 0


func _active_boss() -> Actor:
	for m in monsters:
		if m.is_boss and not m.is_dead():
			return m
	return null


func _populate_current_room(entry_cell: Vector2i) -> void:
	_room_cleared = false
	_active_spell_index = -1
	grid.set_room_cleared(false)
	grid.clear_spell_preview()
	grid.set_danger_cells([])

	if _is_boss_room(room_level) and boss_scene != null:
		var boss_cell := grid.current_room_center
		grid.crush_walls_in_radius(boss_cell, 2)
		var boss := _spawn_actor(boss_scene, boss_cell)
		var extra_hp := maxi(0, (room_level - 2) * 8)
		boss.stats.max_hp += extra_hp
		boss.stats.hp = boss.stats.max_hp
		monsters.append(boss)
		for i in 2 + (room_level / 3):
			var minion_cell := grid.random_floor_cell(_rng, 4, entry_cell, 5)
			if not _is_occupied(minion_cell):
				monsters.append(_spawn_actor(_random_monster_scene(), minion_cell))
	else:
		var total_spawners := spawner_count + (room_level - 1) / 2
		for i in total_spawners:
			var cell := grid.random_floor_cell(_rng, 4, entry_cell, 5)
			if not _is_occupied(cell):
				var spawner := _spawn_actor(spawner_scene if spawner_scene != null else monster_scene, cell)
				if spawner.spawn_scene == null:
					spawner.spawn_scene = _random_monster_scene()
				monsters.append(spawner)

		var total_monsters := monster_count + (room_level - 1) * 2
		for i in total_monsters:
			var cell := grid.random_floor_cell(_rng, 3, entry_cell, 4)
			if not _is_occupied(cell):
				monsters.append(_spawn_actor(_random_monster_scene(), cell))

	for i in item_count:
		var cell := grid.random_floor_cell(_rng, 2, entry_cell, 2)
		if not _is_occupied(cell) and _item_at(cell) == null:
			_spawn_item(_random_item(), cell)

	if _rng.randf() < relic_spawn_chance:
		var relic_cell := grid.random_floor_cell(_rng, 4, entry_cell, 4)
		if not _is_occupied(relic_cell) and _item_at(relic_cell) == null:
			_spawn_item(_random_relic(), relic_cell)


func _on_next_room_confirmed(edge_cell: Vector2i) -> void:
	if _busy or _dead or not _room_cleared:
		return
	_busy = true
	room_level += 1
	var next_center := grid.get_adjacent_room_center(grid.current_room_center, edge_cell)
	var boss_room := _is_boss_room(room_level)
	grid.generate_room(next_center, edge_cell, boss_room)

	# Step 1 hex inward toward the new room center if walkable so the player stands inside the new room.
	var step_in := edge_cell
	var best_dist := HexGrid.distance(edge_cell, next_center)
	for n in grid.walkable_neighbors(edge_cell):
		var d := HexGrid.distance(n, next_center)
		if d < best_dist and not _is_occupied(n):
			best_dist = d
			step_in = n
	if step_in != player.cell:
		await player.move_to(step_in, STEP_TIME).finished
		_pickup()

	_populate_current_room(player.cell)
	if boss_room:
		hud.post("⚠ BOSS LAIR (Room %d)! The 7-hex Rift Colossus awakens!" % room_level)
	else:
		hud.post("Entered Room %d! %d foes await." % [room_level, monsters.size()])

	# Storm Core Relic effect on entering a new room:
	var storm_count := player.count_relic(ItemData.RelicEffect.STORM_CORE)
	if storm_count > 0 and not monsters.is_empty():
		player.restore_all_spells(storm_count)
		var target := monsters[_rng.randi_range(0, monsters.size() - 1)]
		var zap_dmg := 7 * storm_count
		var arc: Array[Vector2] = [grid.cell_to_pixel(player.cell), grid.cell_to_pixel(target.cell)]
		grid.play_spell_vfx([target.cell], Color(0.35, 0.85, 1.0), arc)
		target.take_damage(zap_dmg, Color(0.35, 0.85, 1.0))
		hud.post("Storm Core zaps %s for %d and restores +%d spell charge(s)!" % [
			target.display_name.to_lower(), zap_dmg, storm_count
		])
		if target.is_dead():
			_handle_monster_death(target)

	_busy = false
	_refresh_hud()
	_refresh_hover()


func _check_edge_trigger() -> bool:
	if not grid.is_unvisited_edge_cell(player.cell):
		return false
	if not _room_cleared:
		hud.post("The passage out of this room is sealed until all monsters are defeated!")
		return false
	var next_room := room_level + 1
	hud.prompt_next_room(next_room, player.cell, _is_boss_room(next_room))
	return true


func _spawn_actor(scene: PackedScene, cell: Vector2i) -> Actor:
	var actor := scene.instantiate() as Actor
	grid.add_child(actor)
	actor.place(grid, cell)
	return actor


func _random_monster_scene() -> PackedScene:
	if monster_pool.is_empty():
		return monster_scene
	return monster_pool[_rng.randi_range(0, monster_pool.size() - 1)]


func _spawn_item(data: ItemData, cell: Vector2i) -> void:
	if data == null:
		return
	var item := world_item_scene.instantiate() as WorldItem
	grid.add_child(item)
	grid.move_child(item, 0) # draw under actors
	item.setup(data, grid, cell)
	items.append(item)


func _random_item() -> ItemData:
	if item_pool.is_empty():
		return null
	return item_pool[_rng.randi_range(0, item_pool.size() - 1)] as ItemData


func _random_relic() -> ItemData:
	if relic_pool.is_empty():
		return null
	var unowned: Array[ItemData] = []
	for res in relic_pool:
		if res is ItemData:
			var r := res as ItemData
			if not player.has_relic(r.relic_effect):
				unowned.append(r)
	if not unowned.is_empty():
		return unowned[_rng.randi_range(0, unowned.size() - 1)]
	return relic_pool[_rng.randi_range(0, relic_pool.size() - 1)] as ItemData


func _refresh_hud() -> void:
	hud.refresh(player, turn, _active_spell_index, room_level, monsters.size(), _room_cleared, _active_boss())


# --- lookups --------------------------------------------------------------

func _is_occupied(cell: Vector2i) -> bool:
	return (player != null and player.cell == cell) or _monster_at(cell) != null


func _monster_at(cell: Vector2i) -> Actor:
	for m in monsters:
		if m.occupies_cell(cell):
			return m
	return null


func _item_at(cell: Vector2i) -> WorldItem:
	for item in items:
		if item.cell == cell:
			return item
	return null


func _monster_cells(exclude_actor: Actor = null) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for m in monsters:
		if m == exclude_actor:
			continue
		for occ in m.occupied_cells():
			cells.append(occ)
	return cells


func _monster_adjacent() -> bool:
	for m in monsters:
		if m.distance_to_cell(player.cell) == 1:
			return true
	return false


# --- input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().reload_current_scene()
		return
	if _dead:
		return

	if hud.is_confirm_open():
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in [KEY_Y, KEY_ENTER, KEY_KP_ENTER]:
				hud.confirm_next_room()
			elif event.keycode in [KEY_N, KEY_ESCAPE]:
				hud.close_confirm_modal()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			hud.toggle_spellbook()
			return
		if event.keycode == KEY_ESCAPE:
			if hud.is_spellbook_open():
				hud.close_spellbook()
				return
			if _active_spell_index != -1:
				_cancel_spell_aim()
				return

	if hud.is_any_modal_open():
		return

	if event is InputEventMouseMotion:
		_refresh_hover()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if _active_spell_index != -1:
				_cancel_spell_aim()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _busy:
				_cancel_walk = true
				return
			var cell := grid.pixel_to_cell(grid.get_local_mouse_position())
			if _active_spell_index != -1:
				_try_cast_active_spell(cell)
				return
			var target := _monster_at(cell)
			if target != null and target.distance_to_cell(player.cell) == 1:
				_attack_turn(target)
				return
			var path := _path_to(cell)
			if not path.is_empty():
				_walk(path)
	elif event is InputEventKey and event.pressed and not event.echo:
		if _busy:
			_cancel_walk = true
			return
		var spell_slot := SPELL_HOTKEYS.find(event.keycode)
		if spell_slot != -1:
			_on_hud_spell_selected(spell_slot)
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_use_item(event.keycode - KEY_1)
		elif event.keycode in [KEY_SPACE, KEY_PERIOD, KEY_KP_5]:
			_wait()


## Path to a cell; clicking a monster paths up to (not into) its occupied hexes.
func _path_to(cell: Vector2i) -> Array[Vector2i]:
	var target := _monster_at(cell)
	var blocked := _monster_cells(target)
	var path := grid.find_path(player.cell, cell, blocked, not _room_cleared)
	if target != null and not path.is_empty():
		while not path.is_empty() and target.occupies_cell(path[path.size() - 1]):
			path.pop_back()
	return path


func _refresh_hover() -> void:
	var cell := grid.pixel_to_cell(grid.get_local_mouse_position())
	var hovered_monster := _monster_at(cell)
	var world_item := _item_at(cell)
	hud.show_world_hover_popup(hovered_monster, world_item.data if world_item != null else null)
	if _busy:
		grid.set_hover(cell, [])
		grid.clear_spell_preview()
		return

	if _active_spell_index >= 0 and _active_spell_index < player.spells.size():
		var spell := player.spells[_active_spell_index]
		var range_cells := _valid_spell_targets(spell)
		var aoe_cells: Array[Vector2i] = []
		if spell.pattern == SpellData.Pattern.NOVA:
			aoe_cells = _compute_spell_aoe(spell, player.cell)
		elif range_cells.has(cell):
			aoe_cells = _compute_spell_aoe(spell, cell)
		grid.set_hover(cell, [])
		grid.set_spell_preview(range_cells, aoe_cells, spell.color)
	else:
		grid.clear_spell_preview()
		grid.set_hover(cell, _path_to(cell))


# --- HUD callbacks & Grimoire ---------------------------------------------

func _on_hud_spell_selected(index: int) -> void:
	if _busy or _dead:
		return
	if index < 0 or index >= player.spells.size():
		return
	var spell := player.spells[index]
	if spell.charges <= 0:
		hud.post("%s has no charges left! Drink a Mana Potion to recharge." % spell.display_name)
		return
	if _active_spell_index == index:
		if spell.pattern == SpellData.Pattern.NOVA:
			_try_cast_active_spell(player.cell)
		else:
			_cancel_spell_aim()
		return
	_active_spell_index = index
	_refresh_hud()
	_refresh_hover()


func _cancel_spell_aim() -> void:
	_active_spell_index = -1
	grid.clear_spell_preview()
	_refresh_hud()
	_refresh_hover()


func _on_hud_item_selected(index: int) -> void:
	if _busy or _dead:
		return
	_use_item(index)


func _on_spell_learn_requested(template: SpellData) -> void:
	if _busy or _dead or player.spell_points < template.learn_cost:
		return
	player.spell_points -= template.learn_cost
	var learned := player.learn_spell(template)
	hud.post("You learn %s (%d charges)!" % [learned.display_name, learned.charges])
	_refresh_hud()


func _on_spell_upgrade_requested(spell: SpellData) -> void:
	if _busy or _dead or not spell.can_upgrade() or player.spell_points < spell.upgrade_cost:
		return
	player.spell_points -= spell.upgrade_cost
	spell.upgrade()
	hud.post("Upgraded %s to Lv.%d!" % [spell.display_name, spell.level])
	_refresh_hud()


# --- spell targeting & casting --------------------------------------------

func _valid_spell_targets(spell: SpellData) -> Array[Vector2i]:
	if spell.pattern == SpellData.Pattern.NOVA:
		return grid.cells_in_radius(player.cell, spell.effective_radius(), true)
	var r := spell.effective_range() + player.total_spell_range_bonus()
	var candidates := grid.cells_in_radius(player.cell, r, true)
	var valid: Array[Vector2i] = []
	for c in candidates:
		if c == player.cell:
			continue
		if not _room_cleared and not grid.is_in_current_room(c):
			continue
		if spell.requires_los and not grid.has_line_of_sight(player.cell, c):
			continue
		if spell.pattern == SpellData.Pattern.BLINK and _is_occupied(c):
			continue
		valid.append(c)
	return valid


func _compute_spell_aoe(spell: SpellData, target_cell: Vector2i) -> Array[Vector2i]:
	match spell.pattern:
		SpellData.Pattern.SINGLE:
			return [target_cell]
		SpellData.Pattern.BLAST:
			return grid.cells_in_radius(target_cell, spell.effective_radius(), true)
		SpellData.Pattern.BEAM:
			return grid.hex_line(player.cell, target_cell, true)
		SpellData.Pattern.CHAIN:
			return _compute_chain_cells(target_cell, spell.effective_radius(), spell.chain_jumps + spell.level - 1)
		SpellData.Pattern.BLINK:
			var pulse := grid.cells_in_radius(target_cell, spell.effective_radius(), true)
			return pulse
		SpellData.Pattern.NOVA:
			var ring := grid.cells_in_radius(player.cell, spell.effective_radius(), true)
			ring.erase(player.cell)
			return ring
	return [target_cell]


func _compute_chain_cells(start_cell: Vector2i, jump_range: int, max_jumps: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = [start_cell]
	var current := start_cell
	var hit_actors: Array[Actor] = []
	var first_m := _monster_at(start_cell)
	if first_m != null:
		hit_actors.append(first_m)
	for _i in max_jumps:
		var best_cell := current
		var best_dist := 999
		var best_m: Actor = null
		for m in monsters:
			if hit_actors.has(m):
				continue
			var d := m.distance_to_cell(current)
			if d <= jump_range and d < best_dist:
				best_dist = d
				best_cell = m.cell
				best_m = m
		if best_m == null:
			break
		hit_actors.append(best_m)
		result.append(best_cell)
		current = best_cell
	return result


func _try_cast_active_spell(target_cell: Vector2i) -> void:
	if _active_spell_index < 0 or _active_spell_index >= player.spells.size():
		return
	var spell := player.spells[_active_spell_index]
	var valid_targets := _valid_spell_targets(spell)
	if spell.pattern != SpellData.Pattern.NOVA and not valid_targets.has(target_cell):
		hud.post("Out of range or blocked line of sight.")
		return
	_cast_spell(spell, target_cell)


func _cast_spell(spell: SpellData, target_cell: Vector2i) -> void:
	_busy = true
	_active_spell_index = -1
	grid.clear_spell_preview()

	var free_cast := player.has_relic(ItemData.RelicEffect.ARCANE_PRISM) and _rng.randf() < 0.35
	if not free_cast:
		spell.charges = maxi(0, spell.charges - 1)
	var free_note := " (Arcane Prism: free cast!)" if free_cast else ""

	var aoe_cells := _compute_spell_aoe(spell, target_cell)
	var arc_points: Array[Vector2] = []

	if spell.pattern == SpellData.Pattern.BEAM or spell.pattern == SpellData.Pattern.CHAIN:
		arc_points.append(grid.cell_to_pixel(player.cell))
		for c in aoe_cells:
			arc_points.append(grid.cell_to_pixel(c))

	if spell.pattern == SpellData.Pattern.BLINK:
		await player.move_to(target_cell, STEP_TIME).finished
		_pickup()
		aoe_cells.erase(player.cell)

	var vfx_tween := grid.play_spell_vfx(aoe_cells, spell.color, arc_points)

	var hit_names: Array[String] = []
	var hit_monsters: Array[Actor] = []
	var overlap_counts: Dictionary = {}
	for c in aoe_cells:
		var m := _monster_at(c)
		if m != null:
			if not hit_monsters.has(m):
				hit_monsters.append(m)
				overlap_counts[m] = 1
			else:
				overlap_counts[m] = int(overlap_counts[m]) + 1

	var bonus_dmg := player.total_spell_damage_bonus()
	var bonus_afflicted := player.total_afflicted_damage_bonus()
	var bonus_dur := player.total_status_duration_bonus()
	var bonus_burn := player.total_burn_damage_bonus()
	for m in hit_monsters:
		var overlaps: int = int(overlap_counts.get(m, 1))
		var overlap_mult := 1.0 + 0.25 * float(overlaps - 1)
		var dmg := spell.effective_damage() + bonus_dmg
		if m.has_any_status():
			dmg += bonus_afflicted
		dmg = int(ceil(float(dmg) * overlap_mult * m.incoming_damage_multiplier()))
		if spell.element == SpellData.Element.FIRE:
			m.consume_shatter_statuses()
		m.take_damage(dmg, spell.color)
		if spell.status_effect != null and spell.status_duration > 0:
			var extra_dot := bonus_burn if spell.status_effect.id == "burn" else 0
			m.apply_status(spell.status_effect, spell.status_duration + bonus_dur, extra_dot)
		if overlaps > 1:
			hit_names.append("%s (%d, %d hexes!)" % [m.display_name.to_lower(), dmg, overlaps])
		else:
			hit_names.append("%s (%d)" % [m.display_name.to_lower(), dmg])

	if hit_names.is_empty():
		hud.post("You cast %s.%s" % [spell.display_name, free_note])
	else:
		hud.post("You cast %s, hitting %s.%s" % [spell.display_name, ", ".join(hit_names), free_note])

	for m in hit_monsters:
		if m.is_dead():
			_handle_monster_death(m)

	await vfx_tween.finished
	await _advance_turn()
	if spell.pattern == SpellData.Pattern.BLINK:
		_check_edge_trigger()


# --- player turns ---------------------------------------------------------

func _wait() -> void:
	_busy = true
	_cancel_spell_aim()
	await _advance_turn()


func _attack_turn(target: Actor) -> void:
	_busy = true
	_attack(player, target)
	await _advance_turn()


func _use_item(index: int) -> void:
	if index < 0 or index >= player.inventory.size():
		return
	_busy = true
	_active_spell_clear_quiet()
	var item := player.inventory[index]
	player.inventory.remove_at(index)
	match item.type:
		ItemData.Type.POTION:
			player.heal(item.heal_amount)
			hud.post("You drink the %s (+%d HP)." % [item.display_name.to_lower(), item.heal_amount])
		ItemData.Type.MANA_POTION:
			player.restore_all_spells(item.charge_restore)
			hud.post("You drink the %s (+%d charges to all spells)." % [item.display_name.to_lower(), item.charge_restore])
		ItemData.Type.SPELL_ORB:
			player.spell_points += item.sp_amount
			hud.post("You absorb the %s (+%d SP)." % [item.display_name.to_lower(), item.sp_amount])
		ItemData.Type.RELIC:
			player.add_relic(item)
			hud.post("★ RELIC ACQUIRED: %s! %s" % [item.display_name, item.description])
		_:
			player.equip(item)
			hud.post("You equip the %s." % item.display_name.to_lower())
	await _advance_turn()


func _active_spell_clear_quiet() -> void:
	_active_spell_index = -1
	grid.clear_spell_preview()


func _walk(path: Array[Vector2i]) -> void:
	_busy = true
	_cancel_walk = false
	grid.set_hover(grid.hover_cell, [])
	for i in path.size():
		if _dead or _cancel_walk or _is_occupied(path[i]):
			break
		# Like Qud, stop auto-walking once something hostile is next to you.
		if i > 0 and _monster_adjacent():
			break
		await player.move_to(path[i], STEP_TIME).finished
		var picked_up := _pickup()
		await _monsters_act()
		turn += 1
		_refresh_hud()
		if _check_edge_trigger() or picked_up:
			break
	_finish_action()


func _advance_turn() -> void:
	await _monsters_act()
	turn += 1
	_finish_action()


func _finish_action() -> void:
	_busy = false
	_cancel_walk = false
	_check_room_cleared()
	_refresh_hud()
	_refresh_hover()


func _pickup() -> bool:
	var item := _item_at(player.cell)
	if item == null:
		return false
	if item.data.type == ItemData.Type.RELIC:
		player.add_relic(item.data)
		items.erase(item)
		grid.play_spell_vfx([player.cell], item.data.color)
		hud.post("★ RELIC ACQUIRED: %s — %s" % [item.data.display_name, item.data.description])
		item.queue_free()
		return true
	if item.data.type == ItemData.Type.SPELL_ORB:
		player.spell_points += item.data.sp_amount
		items.erase(item)
		hud.post("You absorb a %s (+%d SP)!" % [item.data.display_name, item.data.sp_amount])
		item.queue_free()
		return true
	if player.inventory.size() >= MAX_INVENTORY:
		hud.post("Your pack is too full for the %s." % item.data.display_name.to_lower())
		return false
	player.inventory.append(item.data)
	items.erase(item)
	hud.post("You pick up the %s." % item.data.display_name.to_lower())
	item.queue_free()
	return true


# --- combat & room clear --------------------------------------------------

func _attack(attacker: Actor, defender: Actor) -> void:
	var damage := maxi(1, attacker.total_attack() - defender.total_defense() + _rng.randi_range(-1, 1))
	if attacker == player and defender.has_any_status():
		damage += player.total_afflicted_damage_bonus()
	damage = int(ceil(float(damage) * defender.incoming_damage_multiplier()))
	var shattered := defender.consume_shatter_statuses()
	defender.take_damage(damage)
	var shatter_note := " (SHATTER!)" if shattered else ""
	hud.post("%s %s %s for %d%s." % [
		attacker.display_name,
		"hit" if attacker == player else "hits",
		defender.display_name.to_lower(),
		damage,
		shatter_note,
	])
	if not defender.is_dead():
		return
	if defender == player:
		_dead = true
		hud.post("You die. Press R to start over.")
	else:
		_handle_monster_death(defender)


func _handle_monster_death(defender: Actor) -> void:
	if not monsters.has(defender):
		return
	monsters.erase(defender)
	if defender.is_boss:
		defender.telegraph_cells.clear()
		grid.set_danger_cells([])
	_kills += 1
	var sp_gain := 3 if defender.is_boss else (1 if (defender.is_spawner or _kills % 2 == 0) else 0)
	player.spell_points += sp_gain
	var blood_stacks := player.count_relic(ItemData.RelicEffect.BURNING_BLOOD)
	if blood_stacks > 0:
		player.heal(2 * blood_stacks)
	var bonus_notes: Array[String] = []
	if sp_gain > 0:
		bonus_notes.append("+%d SP" % sp_gain)
	if blood_stacks > 0:
		bonus_notes.append("+%d HP" % (2 * blood_stacks))
	var note_str := " (%s)" % ", ".join(bonus_notes) if not bonus_notes.is_empty() else ""

	if defender.is_boss:
		hud.post("★ BOSS VANQUISHED: %s falls!%s Dropped a Relic and Mana Potion!" % [defender.display_name, note_str])
		if _item_at(defender.cell) == null:
			_spawn_item(_random_relic(), defender.cell)
		for n in grid.walkable_neighbors(defender.cell):
			if _item_at(n) == null:
				for it_res in starting_items:
					if it_res is ItemData and (it_res as ItemData).type == ItemData.Type.MANA_POTION:
						_spawn_item(it_res as ItemData, n)
						break
				break
	else:
		hud.post("%s is destroyed!%s" % [defender.display_name, note_str] if defender.is_spawner else "%s dies.%s" % [defender.display_name, note_str])
		if _item_at(defender.cell) == null:
			if defender.is_spawner and _rng.randf() < 0.25:
				_spawn_item(_random_relic(), defender.cell)
			elif _rng.randf() < defender.loot_chance:
				_spawn_item(_random_item(), defender.cell)

	defender.queue_free()
	_check_room_cleared()


func _check_room_cleared() -> void:
	if _room_cleared or _dead or not monsters.is_empty():
		return
	_room_cleared = true
	grid.set_room_cleared(true)
	grid.set_danger_cells([])
	player.spell_points += 2
	player.restore_all_spells(1)
	var blood_stacks := player.count_relic(ItemData.RelicEffect.BURNING_BLOOD)
	if blood_stacks > 0:
		player.heal(5 * blood_stacks)
	grid.play_spell_vfx(grid.cells_in_radius(player.cell, 2, true), Color(0.35, 0.95, 0.55))
	hud.post("★ ROOM %d CLEARED! (+2 SP, +1 spell charge). Walk to any glowing green edge passage to enter the next room!" % room_level)
	_check_edge_trigger()


# --- monster, spawner & boss turns ----------------------------------------

func _monsters_act() -> void:
	if _process_actor_statuses(player):
		return
	var tween: Tween
	var acting_monsters: Array[Actor] = monsters.duplicate()
	for m in acting_monsters:
		if not is_instance_valid(m) or m.is_dead():
			continue
		if _process_actor_statuses(m):
			continue
		if m.skips_turn_from_status():
			m.tick_skip_turn_statuses()
			continue
		if m.regen_per_turn > 0 and not m.blocks_regen_from_status() and m.stats.hp < m.stats.max_hp:
			m.heal(m.regen_per_turn)
		if m.is_boss:
			var boss_tween := _boss_act(m)
			if boss_tween != null:
				tween = boss_tween
			if _dead:
				break
			continue
		if m.is_spawner:
			_spawner_act(m)
			continue
		var dist := m.distance_to_cell(player.cell)
		if dist == 1:
			_attack(m, player)
			if _dead:
				break
			continue
		if m.attack_range > 1 and dist <= m.attack_range and grid.has_line_of_sight(m.cell, player.cell):
			_ranged_monster_attack(m, player)
			if _dead:
				break
			continue
		var next := _monster_step(m)
		if next != m.cell:
			tween = m.move_to(next, STEP_TIME)
	if tween != null:
		await tween.finished
	else:
		await get_tree().create_timer(STEP_TIME).timeout


func _boss_act(boss: Actor) -> Tween:
	# 1. Resolve telegraphed Ground Slam if one was prepared last turn.
	if not boss.telegraph_cells.is_empty():
		var slam_cells := boss.telegraph_cells.duplicate()
		boss.telegraph_cells.clear()
		grid.set_danger_cells([])
		grid.play_spell_vfx(slam_cells, Color(1.0, 0.25, 0.2))
		if slam_cells.has(player.cell):
			var dmg := maxi(1, boss.slam_damage - player.total_defense())
			player.take_damage(dmg, Color(1.0, 0.25, 0.2))
			hud.post("💥 %s's Ground Slam crushes you for %d!" % [boss.display_name, dmg])
			if player.is_dead():
				_dead = true
				hud.post("You are crushed by %s. Press R to start over." % boss.display_name.to_lower())
		else:
			hud.post("💥 %s's Ground Slam shatters the cave floor!" % boss.display_name)
		return null

	boss.spawn_cooldown -= 1
	boss.ability_cooldown -= 1

	# 2. Periodically summon an imp minion at the boss's 7-hex perimeter.
	if boss.spawn_cooldown <= 0:
		boss.spawn_cooldown = boss.spawn_interval
		var ring := grid.cells_in_radius(boss.cell, boss.footprint_radius + 1, true)
		var spawn_options: Array[Vector2i] = []
		for c in ring:
			if HexGrid.distance(c, boss.cell) == boss.footprint_radius + 1 and grid.is_in_current_room(c) and not _is_occupied(c):
				spawn_options.append(c)
		if not spawn_options.is_empty():
			var sc := spawn_options[_rng.randi_range(0, spawn_options.size() - 1)]
			var minion_scene := boss.spawn_scene if boss.spawn_scene != null else _random_monster_scene()
			var minion := _spawn_actor(minion_scene, sc)
			monsters.append(minion)
			grid.play_spell_vfx([sc], boss.color)
			hud.post("%s summons %s!" % [boss.display_name, minion.display_name.to_lower()])
			return null

	# 3. Telegraph a 7-hex Ground Slam around the player's position.
	var dist_to_player := boss.distance_to_cell(player.cell)
	if boss.ability_cooldown <= 0 and dist_to_player <= 5:
		boss.ability_cooldown = 3
		boss.telegraph_cells = grid.cells_in_radius(player.cell, 1, true)
		grid.set_danger_cells(boss.telegraph_cells)
		hud.post("⚠ %s raises its colossus fists! Move out of the red danger zone!" % boss.display_name)
		return null

	# 4. Melee crush if adjacent to any of the boss's 7 hexes.
	if dist_to_player <= 1:
		_attack(boss, player)
		return null

	# 5. March 1 step toward the player, crushing interior cave walls under its 7-hex body.
	var best_step := boss.cell
	var best_dist := HexGrid.distance(boss.cell, player.cell)
	for d in HexGrid.DIRECTIONS:
		var cand := boss.cell + d
		if HexGrid.distance(cand, grid.current_room_center) >= grid.radius - boss.footprint_radius:
			continue
		var new_footprint := boss.occupied_cells_at(cand)
		if new_footprint.has(player.cell):
			continue
		var blocked_by_minion := false
		for other in monsters:
			if other != boss and new_footprint.has(other.cell):
				blocked_by_minion = true
				break
		if blocked_by_minion:
			continue
		var cand_dist := HexGrid.distance(cand, player.cell)
		if cand_dist < best_dist:
			best_dist = cand_dist
			best_step = cand

	if best_step != boss.cell:
		grid.crush_walls_in_radius(best_step, boss.footprint_radius)
		return boss.move_to(best_step, STEP_TIME)
	return null


func _spawner_act(spawner: Actor) -> void:
	spawner.spawn_cooldown -= 1
	if spawner.spawn_cooldown > 0:
		spawner.queue_redraw()
		return
	spawner.spawn_cooldown = spawner.spawn_interval
	spawner.queue_redraw()
	var options: Array[Vector2i] = []
	for n in grid.walkable_neighbors(spawner.cell):
		if grid.is_in_current_room(n) and not _is_occupied(n):
			options.append(n)
	if options.is_empty():
		return
	var spawn_cell := options[_rng.randi_range(0, options.size() - 1)]
	var scene := spawner.spawn_scene if spawner.spawn_scene != null else _random_monster_scene()
	var summoned := _spawn_actor(scene, spawn_cell)
	monsters.append(summoned)
	grid.play_spell_vfx([spawner.cell, spawn_cell], spawner.color)
	hud.post("%s summons %s!" % [spawner.display_name, summoned.display_name.to_lower()])


func _ranged_monster_attack(attacker: Actor, defender: Actor) -> void:
	var arc: Array[Vector2] = [grid.cell_to_pixel(attacker.cell), grid.cell_to_pixel(defender.cell)]
	grid.play_spell_vfx([defender.cell], attacker.color, arc)
	var damage := maxi(1, attacker.total_attack() - defender.total_defense() + _rng.randi_range(-1, 1))
	defender.take_damage(damage, attacker.color)
	hud.post("%s blasts %s from afar for %d." % [attacker.display_name, defender.display_name.to_lower(), damage])
	if defender.is_dead() and defender == player:
		_dead = true
		hud.post("You die. Press R to start over.")


func _process_actor_statuses(actor: Actor) -> bool:
	if actor.statuses.is_empty():
		return false
	for i in range(actor.statuses.size() - 1, -1, -1):
		var st := actor.statuses[i]
		if st.skips_turn:
			continue
		st.turns_left -= 1
		if st.damage_per_turn > 0:
			actor.take_damage(st.damage_per_turn, st.color)
			hud.post("%s takes %d %s damage." % [actor.display_name, st.damage_per_turn, st.display_name.to_lower()])
		if st.turns_left <= 0:
			actor.statuses.remove_at(i)
		actor.queue_redraw()
		if actor.is_dead():
			if actor == player:
				_dead = true
				hud.post("You succumb to %s. Press R to start over." % st.display_name.to_lower())
			else:
				_handle_monster_death(actor)
			return true
	return false


func _monster_step(m: Actor) -> Vector2i:
	if HexGrid.distance(m.cell, player.cell) <= monster_sight:
		var others := _monster_cells(m)
		var path := grid.find_path(m.cell, player.cell, others, true)
		if not path.is_empty():
			return path[0]
		return m.cell
	if _rng.randf() < 0.5:
		return m.cell
	var options: Array[Vector2i] = []
	for n in grid.walkable_neighbors(m.cell):
		if grid.is_in_current_room(n) and not _is_occupied(n):
			options.append(n)
	if options.is_empty():
		return m.cell
	return options[_rng.randi_range(0, options.size() - 1)]
