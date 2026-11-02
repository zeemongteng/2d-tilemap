class_name Actor
extends Node2D
## Anything that occupies one hex and takes a turn: the player, monsters, spawners.

@export var display_name := "Actor"
@export_multiline var description := ""
@export var glyph := "@"
@export var color := Color.WHITE
@export var font_size := 28
@export var stats: Stats
## Chance (0-1) of dropping a random item on death.
@export var loot_chance := 0.0

@export_group("Monster Abilities")
@export var attack_range := 1
@export var regen_per_turn := 0
@export var is_spawner := false
@export var spawn_interval := 4
@export var spawn_scene: PackedScene

var cell := Vector2i.ZERO
var grid: HexGrid
var inventory: Array[ItemData] = []
var spells: Array[SpellData] = []
var spell_points := 2
var weapon: ItemData
var armor: ItemData

var burn_turns := 0
var burn_damage := 2
var frozen_turns := 0
var spawn_cooldown := 3


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


func total_attack() -> int:
	return stats.attack + (weapon.attack_bonus if weapon != null else 0)


func total_defense() -> int:
	return stats.defense + (armor.defense_bonus if armor != null else 0)


func is_dead() -> bool:
	return stats.hp <= 0


func take_damage(amount: int, flash_color := Color(1, 0.3, 0.3)) -> void:
	stats.hp = maxi(0, stats.hp - amount)
	modulate = flash_color
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.25)
	queue_redraw()


func heal(amount: int) -> void:
	stats.hp = mini(stats.max_hp, stats.hp + amount)
	queue_redraw()


func apply_burn(turns: int, dmg := 2) -> void:
	burn_turns = maxi(burn_turns, turns)
	burn_damage = maxi(burn_damage, dmg)
	if frozen_turns > 0:
		frozen_turns = 0
	queue_redraw()


func apply_freeze(turns: int) -> void:
	frozen_turns = maxi(frozen_turns, turns)
	if burn_turns > 0:
		burn_turns = 0
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
	if frozen_turns > 0:
		draw_col = color.lerp(Color(0.35, 0.9, 1.0), 0.65)
	elif burn_turns > 0:
		draw_col = color.lerp(Color(1.0, 0.45, 0.1), 0.55)

	if is_spawner:
		draw_arc(Vector2.ZERO, font_size * 0.58, 0.0, TAU, 24, Color(draw_col.r, draw_col.g, draw_col.b, 0.45), 2.0)

	var offset := Vector2(-font_size, font_size * 0.35)
	draw_string(font, offset, glyph, HORIZONTAL_ALIGNMENT_CENTER, font_size * 2.0, font_size, draw_col)

	if frozen_turns > 0 or burn_turns > 0:
		var badge := "*%d" % frozen_turns if frozen_turns > 0 else "~%d" % burn_turns
		var badge_col := Color(0.4, 0.9, 1.0) if frozen_turns > 0 else Color(1.0, 0.5, 0.15)
		draw_string(font, Vector2(-font_size, -font_size * 0.38), badge, HORIZONTAL_ALIGNMENT_CENTER, font_size * 2.0, 12, badge_col)
	elif is_spawner:
		var timer_txt := "⏳%d" % spawn_cooldown if spawn_cooldown > 1 else "!"
		draw_string(font, Vector2(-font_size, -font_size * 0.38), timer_txt, HORIZONTAL_ALIGNMENT_CENTER, font_size * 2.0, 12, Color(0.95, 0.65, 1.0))

	if stats != null and stats.hp < stats.max_hp and stats.hp > 0:
		var bar_w := 24.0
		var bar_h := 3.5
		var ratio := clampf(float(stats.hp) / float(stats.max_hp), 0.0, 1.0)
		var bar_pos := Vector2(-bar_w * 0.5, font_size * 0.48)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.15, 0.05, 0.05, 0.85))
		draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), Color(0.9, 0.25, 0.25, 0.95))
