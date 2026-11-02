extends Node2D
## Turn loop: every player action (a step, an attack, casting a spell, using an item, waiting)
## is followed by one action from each monster. Clicking a far hex auto-walks
## one step per turn.

const STEP_TIME := 0.08
const MAX_INVENTORY := 9
const SPELL_HOTKEYS: Array[Key] = [KEY_Q, KEY_W, KEY_E, KEY_F, KEY_G, KEY_C]

@export var player_scene: PackedScene
@export var monster_scene: PackedScene
@export var world_item_scene: PackedScene
@export var item_pool: Array[Resource]
@export var starting_items: Array[Resource]
@export var starting_spells: Array[Resource]
@export var spell_catalog: Array[Resource]
@export var monster_count := 8
@export var item_count := 8
@export var monster_sight := 6

@onready var grid: HexGrid = $HexGrid
@onready var hud: Hud = $Hud

var player: Actor
var monsters: Array[Actor] = []
var items: Array[WorldItem] = []
var turn := 0
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

	player = _spawn_actor(player_scene, Vector2i.ZERO)
	for res in starting_items:
		if res is ItemData:
			player.inventory.append(res as ItemData)
	for res in starting_spells:
		if res is SpellData:
			player.learn_spell(res as SpellData)

	for i in monster_count:
		var cell := grid.random_floor_cell(_rng, 5)
		if not _is_occupied(cell):
			monsters.append(_spawn_actor(monster_scene, cell))
	for i in item_count:
		var cell := grid.random_floor_cell(_rng, 3)
		if not _is_occupied(cell) and _item_at(cell) == null:
			_spawn_item(_random_item(), cell)

	hud.post("Click hexes to move/attack. Click Spells (or Q/W/E/F) to aim & cast. [B] opens Grimoire.")
	hud.refresh(player, turn, _active_spell_index)


func _process(_delta: float) -> void:
	$Camera2D.position = player.position


# --- spawning -------------------------------------------------------------

func _spawn_actor(scene: PackedScene, cell: Vector2i) -> Actor:
	var actor := scene.instantiate() as Actor
	grid.add_child(actor)
	actor.place(grid, cell)
	return actor


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


# --- lookups --------------------------------------------------------------

func _is_occupied(cell: Vector2i) -> bool:
	return (player != null and player.cell == cell) or _monster_at(cell) != null


func _monster_at(cell: Vector2i) -> Actor:
	for m in monsters:
		if m.cell == cell:
			return m
	return null


func _item_at(cell: Vector2i) -> WorldItem:
	for item in items:
		if item.cell == cell:
			return item
	return null


func _monster_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for m in monsters:
		cells.append(m.cell)
	return cells


func _monster_adjacent() -> bool:
	for m in monsters:
		if HexGrid.distance(m.cell, player.cell) == 1:
			return true
	return false


# --- input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().reload_current_scene()
		return
	if _dead:
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

	if hud.is_spellbook_open():
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
			if target != null and HexGrid.distance(player.cell, cell) == 1:
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


## Path to a cell; clicking a monster paths up to (not into) it.
func _path_to(cell: Vector2i) -> Array[Vector2i]:
	var target := _monster_at(cell)
	var blocked := _monster_cells()
	if target != null:
		blocked.erase(cell)
	var path := grid.find_path(player.cell, cell, blocked)
	if target != null and not path.is_empty():
		path.pop_back()
	return path


func _refresh_hover() -> void:
	var cell := grid.pixel_to_cell(grid.get_local_mouse_position())
	var world_item := _item_at(cell)
	hud.show_world_item_popup(world_item.data if world_item != null else null)
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
		# Pressing or clicking a self-targeted NOVA spell a second time casts it immediately.
		if spell.pattern == SpellData.Pattern.NOVA:
			_try_cast_active_spell(player.cell)
		else:
			_cancel_spell_aim()
		return
	_active_spell_index = index
	hud.refresh(player, turn, _active_spell_index)
	_refresh_hover()


func _cancel_spell_aim() -> void:
	_active_spell_index = -1
	grid.clear_spell_preview()
	hud.refresh(player, turn, _active_spell_index)
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
	hud.refresh(player, turn, _active_spell_index)


func _on_spell_upgrade_requested(spell: SpellData) -> void:
	if _busy or _dead or not spell.can_upgrade() or player.spell_points < spell.upgrade_cost:
		return
	player.spell_points -= spell.upgrade_cost
	spell.upgrade()
	hud.post("Upgraded %s to Lv.%d!" % [spell.display_name, spell.level])
	hud.refresh(player, turn, _active_spell_index)


# --- spell targeting & casting --------------------------------------------

func _valid_spell_targets(spell: SpellData) -> Array[Vector2i]:
	if spell.pattern == SpellData.Pattern.NOVA:
		return grid.cells_in_radius(player.cell, spell.effective_radius(), true)
	var r := spell.effective_range()
	var candidates := grid.cells_in_radius(player.cell, r, true)
	var valid: Array[Vector2i] = []
	for c in candidates:
		if c == player.cell:
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
	for _i in max_jumps:
		var best_cell := current
		var best_dist := 999
		for m in monsters:
			if result.has(m.cell):
				continue
			var d := HexGrid.distance(current, m.cell)
			if d <= jump_range and d < best_dist:
				best_dist = d
				best_cell = m.cell
		if best_cell == current:
			break
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

	spell.charges = maxi(0, spell.charges - 1)
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
	for c in aoe_cells:
		var m := _monster_at(c)
		if m != null and not hit_monsters.has(m):
			hit_monsters.append(m)

	for m in hit_monsters:
		var dmg := spell.effective_damage()
		# Fire melts frozen targets for +50% bonus damage!
		if spell.element == SpellData.Element.FIRE and m.frozen_turns > 0:
			dmg = int(ceil(float(dmg) * 1.5))
		m.take_damage(dmg, spell.color)
		if spell.status_duration > 0:
			if spell.element == SpellData.Element.FIRE:
				m.apply_burn(spell.status_duration, 2)
			elif spell.element in [SpellData.Element.ICE, SpellData.Element.ARCANE]:
				m.apply_freeze(spell.status_duration)
		hit_names.append("%s (%d)" % [m.display_name.to_lower(), dmg])

	if hit_names.is_empty():
		hud.post("You cast %s." % spell.display_name)
	else:
		hud.post("You cast %s, hitting %s." % [spell.display_name, ", ".join(hit_names)])

	for m in hit_monsters:
		if m.is_dead():
			_handle_monster_death(m)

	await vfx_tween.finished
	await _advance_turn()


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
		hud.refresh(player, turn, _active_spell_index)
		if picked_up:
			break
	_finish_action()


func _advance_turn() -> void:
	await _monsters_act()
	turn += 1
	_finish_action()


func _finish_action() -> void:
	_busy = false
	_cancel_walk = false
	hud.refresh(player, turn, _active_spell_index)
	_refresh_hover()


func _pickup() -> bool:
	var item := _item_at(player.cell)
	if item == null:
		return false
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


# --- combat ---------------------------------------------------------------

func _attack(attacker: Actor, defender: Actor) -> void:
	var damage := maxi(1, attacker.total_attack() - defender.total_defense() + _rng.randi_range(-1, 1))
	var shattered := false
	if defender.frozen_turns > 0:
		damage = int(ceil(float(damage) * 1.5))
		defender.frozen_turns = 0
		shattered = true
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
	_kills += 1
	var sp_msg := ""
	if _kills % 2 == 0:
		player.spell_points += 1
		sp_msg = " (+1 SP)"
	hud.post("%s dies.%s" % [defender.display_name, sp_msg])
	if _rng.randf() < defender.loot_chance and _item_at(defender.cell) == null:
		_spawn_item(_random_item(), defender.cell)
	defender.queue_free()


# --- monster turns --------------------------------------------------------

func _monsters_act() -> void:
	if _process_actor_statuses(player):
		return
	var tween: Tween
	var acting_monsters := monsters.duplicate()
	for m in acting_monsters:
		if not is_instance_valid(m) or m.is_dead():
			continue
		if _process_actor_statuses(m):
			continue
		if m.frozen_turns > 0:
			m.frozen_turns -= 1
			m.queue_redraw()
			continue
		if HexGrid.distance(m.cell, player.cell) == 1:
			_attack(m, player)
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


func _process_actor_statuses(actor: Actor) -> bool:
	if actor.burn_turns <= 0:
		return false
	actor.burn_turns -= 1
	actor.take_damage(actor.burn_damage, Color(1.0, 0.45, 0.1))
	hud.post("%s burns for %d." % [actor.display_name, actor.burn_damage])
	if actor.is_dead():
		if actor == player:
			_dead = true
			hud.post("You burn to death. Press R to start over.")
		else:
			_handle_monster_death(actor)
		return true
	return false


func _monster_step(m: Actor) -> Vector2i:
	if HexGrid.distance(m.cell, player.cell) <= monster_sight:
		var others: Array[Vector2i] = []
		for other in monsters:
			if other != m:
				others.append(other.cell)
		var path := grid.find_path(m.cell, player.cell, others)
		if not path.is_empty():
			return path[0]
		return m.cell
	if _rng.randf() < 0.5:
		return m.cell
	var options: Array[Vector2i] = []
	for n in grid.walkable_neighbors(m.cell):
		if not _is_occupied(n):
			options.append(n)
	if options.is_empty():
		return m.cell
	return options[_rng.randi_range(0, options.size() - 1)]
