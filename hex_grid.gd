class_name HexGrid
extends Node2D
## Pointy-top hex grid using axial coordinates (x = q, y = r).
## Supports generating connected adjacent hex rooms of identical size with shared walls.

const SQRT3 := 1.7320508075688772
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

enum Terrain { NONE, WATER, OIL, FIRE, ICE }

@export var radius := 12
@export var hex_size := 26.0
## 0 = a different cave every run.
@export var rng_seed := 0
@export_range(0.0, 1.0) var fill_chance := 0.44
@export var smooth_passes := 3

@export_group("Colors")
@export var floor_color := Color("1c2a24")
@export var wall_color := Color("0b0f0d")
@export var line_color := Color("2f4a3e")
@export var hover_color := Color(1, 1, 1, 0.18)
@export var path_color := Color("e8c547")
@export var exit_locked_color := Color(0.95, 0.45, 0.2, 0.45)
@export var exit_ready_color := Color(0.35, 0.95, 0.55, 0.75)

## cell -> true if wall, false if floor.
var _tiles: Dictionary = {}
## cell -> Terrain enum value (WATER, OIL, FIRE, ICE).
var _terrain: Dictionary = {}
## cell -> remaining turns for temporary terrain (e.g. FIRE).
var _terrain_timers: Dictionary = {}
var _astar := AStar2D.new()
var _ids: Dictionary = {}
var _cells: Array[Vector2i] = []
var _corners := PackedVector2Array()
var _rng := RandomNumberGenerator.new()

var current_room_center := Vector2i.ZERO
var generated_rooms: Array[Vector2i] = []
var exit_cells: Array[Vector2i] = []
var treasure_exit_cells: Array[Vector2i] = []
var shop_exit_cells: Array[Vector2i] = []
var treasure_face := -1
var shop_face := -1
var room_cleared := false
var in_sanctuary := false
var active_sanctuary_center := Vector2i.ZERO
var active_sanctuary_radius := 5
var _sanctuary_themes: Dictionary = {}

var hover_cell := Vector2i(1 << 20, 1 << 20)
var path_preview: Array[Vector2i] = []

var spell_range_cells: Array[Vector2i] = []
var spell_aoe_cells: Array[Vector2i] = []
var spell_preview_color := Color(1.0, 0.5, 0.2)
var danger_cells: Array[Vector2i] = []

var vfx_cells: Array[Vector2i] = []
var vfx_arc_points: Array[Vector2] = []
var vfx_color := Color.WHITE
var vfx_alpha := 0.0
var _explosion_layer: ExplosionLayer


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return maxi(maxi(absi(dq), absi(dr)), absi(dq + dr))


static func _axial_round(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


func _ready() -> void:
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 30.0)
		_corners.append(Vector2(cos(angle), sin(angle)) * hex_size)
	_explosion_layer = ExplosionLayer.new()
	_explosion_layer.name = "ExplosionLayer"
	add_child(_explosion_layer)
	_explosion_layer.setup(hex_size, PackedVector2Array(_corners))


## Rift Wizard-style rippling explosion: every hex in `cells` bursts in turn, ring by ring
## outward from `center`. Returns a tween that finishes when the last burst fades.
func play_explosion(center: Vector2i, cells: Array[Vector2i], color: Color) -> Tween:
	var positions: Array[Vector2] = []
	var rings: Array[int] = []
	for c in cells:
		positions.append(cell_to_pixel(c))
		rings.append(distance(c, center))
	var duration := _explosion_layer.explode(positions, rings, color)
	var tween := create_tween()
	tween.tween_interval(duration)
	return tween


func cell_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(hex_size * SQRT3 * (cell.x + cell.y * 0.5), hex_size * 1.5 * cell.y)


func pixel_to_cell(p: Vector2) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.y / 3.0) / hex_size
	var r := (2.0 / 3.0 * p.y) / hex_size
	return _axial_round(q, r)


func is_walkable(cell: Vector2i) -> bool:
	return _tiles.has(cell) and not _tiles[cell]


func is_in_current_room(cell: Vector2i) -> bool:
	if in_sanctuary:
		return distance(cell, active_sanctuary_center) <= active_sanctuary_radius
	return distance(cell, current_room_center) <= radius


func walkable_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		if is_walkable(cell + d):
			result.append(cell + d)
	return result


func cells_in_radius(center: Vector2i, r: int, walkable_only := true) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dq in range(-r, r + 1):
		for dr in range(maxi(-r, -dq - r), mini(r, -dq + r) + 1):
			var c := center + Vector2i(dq, dr)
			if not walkable_only or is_walkable(c):
				result.append(c)
	return result


## Returns the 6 face-to-face offsets for hex rooms of `radius` so adjacent rooms share a 13-hex border wall.
func _room_face_offsets() -> Array[Vector2i]:
	var r := radius
	return [
		Vector2i(2 * r, -r),
		Vector2i(r, r),
		Vector2i(-r, 2 * r),
		Vector2i(-2 * r, r),
		Vector2i(-r, -r),
		Vector2i(r, -2 * r),
	]


## Midpoint on the rim of `center` for face `face_idx` (0..5).
func _face_midpoint(center: Vector2i, face_idx: int) -> Vector2i:
	var r := radius
	var half := r / 2
	match face_idx:
		0:
			return center + Vector2i(r, -half)
		1:
			return center + Vector2i(r - half, half)
		2:
			return center + Vector2i(-half, r)
		3:
			return center + Vector2i(-r, half)
		4:
			return center + Vector2i(-r + half, -half)
		_:
			return center + Vector2i(half, -r)


func get_face_index(center: Vector2i, edge_cell: Vector2i) -> int:
	var dq := edge_cell.x - center.x
	var dr := edge_cell.y - center.y
	var ds := -dq - dr
	var r := radius
	if dq == r:
		return 0
	if ds == -r:
		return 1
	if dr == r:
		return 2
	if dq == -r:
		return 3
	if ds == r:
		return 4
	return 5


func get_adjacent_room_center(center: Vector2i, edge_cell: Vector2i) -> Vector2i:
	var offsets := _room_face_offsets()
	var face_idx := get_face_index(center, edge_cell)
	return center + offsets[face_idx]


func is_unvisited_edge_cell(cell: Vector2i) -> bool:
	if not is_walkable(cell):
		return false
	if distance(cell, current_room_center) != radius:
		return false
	var adj_center := get_adjacent_room_center(current_room_center, cell)
	return not generated_rooms.has(adj_center)


## Returns cells along the straight hex line from `from` (exclusive) to `to` (inclusive),
## stopping if a wall is encountered.
func hex_line(from: Vector2i, to: Vector2i, stop_at_walls := true) -> Array[Vector2i]:
	var n := distance(from, to)
	var result: Array[Vector2i] = []
	if n == 0:
		return result
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var q := lerpf(float(from.x) + 1e-6, float(to.x) + 1e-6, t)
		var r := lerpf(float(from.y) + 2e-6, float(to.y) + 2e-6, t)
		var c := _axial_round(q, r)
		if stop_at_walls and not is_walkable(c):
			break
		result.append(c)
	return result


func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	if not is_walkable(to):
		return false
	if from == to:
		return true
	var line := hex_line(from, to, true)
	return not line.is_empty() and line[line.size() - 1] == to


func random_floor_cell(rng: RandomNumberGenerator, min_distance_from_center := 0, avoid_cell := Vector2i(1 << 20, 1 << 20), min_avoid_dist := 0) -> Vector2i:
	var options: Array[Vector2i] = []
	for c in _cells:
		if distance(c, current_room_center) >= radius:
			continue
		if distance(c, current_room_center) >= min_distance_from_center and distance(c, avoid_cell) >= min_avoid_dist:
			options.append(c)
	if options.is_empty():
		return current_room_center
	return options[rng.randi_range(0, options.size() - 1)]


func generate() -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_tiles.clear()
	_terrain.clear()
	_terrain_timers.clear()
	_sanctuary_themes.clear()
	in_sanctuary = false
	generated_rooms.clear()
	generate_room(Vector2i.ZERO, Vector2i.ZERO)


func generate_sanctuary_room(center: Vector2i, sanct_radius: int, is_angel: bool, theme_override := "") -> void:
	in_sanctuary = true
	active_sanctuary_center = center
	active_sanctuary_radius = sanct_radius
	var theme_key := theme_override if not theme_override.is_empty() else ("angel" if is_angel else "devil")
	for dq in range(-sanct_radius, sanct_radius + 1):
		for dr in range(maxi(-sanct_radius, -dq - sanct_radius), mini(sanct_radius, -dq + sanct_radius) + 1):
			var c := center + Vector2i(dq, dr)
			_tiles[c] = (distance(c, center) == sanct_radius)
			_sanctuary_themes[c] = theme_key
	_build_astar()
	queue_redraw()


func exit_sanctuary_room() -> void:
	in_sanctuary = false
	queue_redraw()


## Generates a room of `radius` centered at `center` while preserving any shared boundary tiles
## from already-generated adjacent rooms so walls and doorways connect seamlessly.
func generate_room(center: Vector2i, entry_cell: Vector2i, is_boss_room := false, is_treasure_room := false, is_shop_room := false) -> void:
	current_room_center = center
	danger_cells.clear()
	if not generated_rooms.has(center):
		generated_rooms.append(center)

	var region: Array[Vector2i] = []
	var locked: Dictionary = {}
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			var c := center + Vector2i(dq, dr)
			region.append(c)
			if is_treasure_room:
				_sanctuary_themes[c] = "treasure"
			elif is_shop_room:
				_sanctuary_themes[c] = "shop"
			if _tiles.has(c):
				locked[c] = true
			elif distance(c, center) == radius:
				# Outer rim defaults to solid cave wall until exit doorways are carved.
				_tiles[c] = true
			elif is_treasure_room or is_shop_room:
				_tiles[c] = (distance(c, center) >= 6 and _rng.randf() < 0.25)
			else:
				_tiles[c] = _rng.randf() < fill_chance

	for _pass in smooth_passes:
		var next := {}
		for c in region:
			if locked.has(c) or distance(c, center) == radius:
				next[c] = _tiles[c]
				continue
			var walls := 0
			for d in DIRECTIONS:
				if _tiles.get(c + d, true):
					walls += 1
			if walls >= 4:
				next[c] = true
			elif walls <= 2:
				next[c] = false
			else:
				next[c] = _tiles[c]
		for c in region:
			_tiles[c] = next[c]

	# Guarantee open ground around the room's center and around the entry cell.
	var open_center_radius := 5 if (is_boss_room or is_treasure_room or is_shop_room) else 2
	for c in region:
		if distance(c, center) <= open_center_radius and not locked.has(c):
			_tiles[c] = false
		if entry_cell != center and distance(c, entry_cell) <= 1 and distance(c, center) < radius and not locked.has(c):
			_tiles[c] = false

	# Connect the entry doorway directly to the new room's center.
	if entry_cell != center:
		_carve_corridor(entry_cell, center, locked)

	# Carve exit doorways on the 6 faces leading to unvisited adjacent rooms.
	var offsets := _room_face_offsets()
	var unvisited_faces: Array[int] = []
	for face_idx in 6:
		var adj_center := center + offsets[face_idx]
		var mid := _face_midpoint(center, face_idx)
		if not generated_rooms.has(adj_center):
			unvisited_faces.append(face_idx)
			# Carve a 2-hex doorway on the rim and connect it to the room center.
			_tiles[mid] = false
			for d in DIRECTIONS:
				var neighbor_rim := mid + d
				if distance(neighbor_rim, center) == radius and not locked.has(neighbor_rim):
					_tiles[neighbor_rim] = false
					break
			_carve_corridor(mid, center, locked)
		else:
			# Ensure any existing doorway on a shared wall connects into this room's center.
			for c in region:
				if locked.has(c) and not _tiles[c] and get_face_index(center, c) == face_idx:
					_carve_corridor(c, center, locked)

	if not is_boss_room and not is_treasure_room and not is_shop_room and not unvisited_faces.is_empty():
		var t_idx := _rng.randi_range(0, unvisited_faces.size() - 1)
		treasure_face = unvisited_faces[t_idx]
		var remaining_faces: Array[int] = []
		for f in unvisited_faces:
			if f != treasure_face:
				remaining_faces.append(f)
		if not remaining_faces.is_empty():
			shop_face = remaining_faces[_rng.randi_range(0, remaining_faces.size() - 1)]
		else:
			shop_face = -1
	else:
		treasure_face = -1
		shop_face = -1

	# Fill in unreachable interior pockets inside this room.
	var reachable := {center: true}
	var stack: Array[Vector2i] = [center]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRECTIONS:
			var n := c + d
			if distance(n, center) <= radius and is_walkable(n) and not reachable.has(n):
				reachable[n] = true
				stack.append(n)
	for c in region:
		if not reachable.has(c) and not locked.has(c):
			_tiles[c] = true

	_build_astar()
	_refresh_exit_cells()
	if not is_treasure_room and not is_shop_room:
		_generate_room_terrain(center, entry_cell, is_boss_room)
	queue_redraw()


func get_terrain(cell: Vector2i) -> int:
	return int(_terrain.get(cell, Terrain.NONE))


func set_terrain(cell: Vector2i, terrain_type: int, duration := 0) -> void:
	if not is_walkable(cell):
		return
	if terrain_type == Terrain.NONE:
		_terrain.erase(cell)
		_terrain_timers.erase(cell)
	else:
		_terrain[cell] = terrain_type
		if duration > 0:
			_terrain_timers[cell] = duration
		else:
			_terrain_timers.erase(cell)
	queue_redraw()


func connected_terrain(start_cell: Vector2i, terrain_type: int, max_cells := 24) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if get_terrain(start_cell) != terrain_type:
		return result
	var visited := {start_cell: true}
	var queue: Array[Vector2i] = [start_cell]
	while not queue.is_empty() and result.size() < max_cells:
		var cur: Vector2i = queue.pop_front()
		result.append(cur)
		for d in DIRECTIONS:
			var n := cur + d
			if not visited.has(n) and is_in_current_room(n) and get_terrain(n) == terrain_type:
				visited[n] = true
				queue.append(n)
	return result


func tick_terrain() -> void:
	var expired: Array[Vector2i] = []
	for c in _terrain_timers:
		var left: int = int(_terrain_timers[c]) - 1
		if left <= 0:
			expired.append(c)
		else:
			_terrain_timers[c] = left
	for c in expired:
		_terrain_timers.erase(c)
		_terrain.erase(c)
	if not expired.is_empty():
		queue_redraw()


static func terrain_name(t: int) -> String:
	match t:
		Terrain.WATER:
			return "Water Tile"
		Terrain.OIL:
			return "Oil Slick"
		Terrain.FIRE:
			return "Burning Ground"
		Terrain.ICE:
			return "Frozen Ice"
	return ""


static func terrain_description(t: int) -> String:
	match t:
		Terrain.WATER:
			return "Applies Wet (+50% Lightning DMG, extinguishes Burn). Lightning conducts across the entire connected puddle; Ice freezes it solid!"
		Terrain.OIL:
			return "Highly flammable! Any Fire spell ignites the entire connected Oil slick in a chain explosion."
		Terrain.FIRE:
			return "Scorches non-Fire units standing on it (2 DMG + Burn). Extinguished by Water spells."
		Terrain.ICE:
			return "Slippery frost. Fire spells melt Ice back into Water."
	return ""


static func terrain_color(t: int) -> Color:
	match t:
		Terrain.WATER:
			return Color(0.28, 0.72, 1.0)
		Terrain.OIL:
			return Color(0.68, 0.45, 0.85)
		Terrain.FIRE:
			return Color(1.0, 0.45, 0.15)
		Terrain.ICE:
			return Color(0.55, 0.92, 1.0)
	return Color.WHITE


func _generate_room_terrain(center: Vector2i, entry_cell: Vector2i, is_boss_room: bool) -> void:
	var patch_count := 4 if is_boss_room else _rng.randi_range(2, 4)
	var types: Array[int] = [Terrain.WATER, Terrain.WATER, Terrain.OIL, Terrain.ICE]
	if is_boss_room:
		types.append(Terrain.FIRE)
	for _p in patch_count:
		var t_type: int = types[_rng.randi_range(0, types.size() - 1)]
		var seed_cell := random_floor_cell(_rng, 2, entry_cell, 3)
		if not is_walkable(seed_cell) or distance(seed_cell, center) >= radius:
			continue
		var target_size := _rng.randi_range(3, 6)
		var frontier: Array[Vector2i] = [seed_cell]
		var placed := 0
		while not frontier.is_empty() and placed < target_size:
			var idx := _rng.randi_range(0, frontier.size() - 1)
			var cur: Vector2i = frontier[idx]
			frontier.remove_at(idx)
			if not is_walkable(cur) or distance(cur, center) >= radius or distance(cur, entry_cell) < 2:
				continue
			if get_terrain(cur) != Terrain.NONE:
				continue
			_terrain[cur] = t_type
			if t_type == Terrain.FIRE:
				_terrain_timers[cur] = 8
			placed += 1
			for n in walkable_neighbors(cur):
				if distance(n, center) < radius and get_terrain(n) == Terrain.NONE and not frontier.has(n):
					frontier.append(n)


func _carve_corridor(from: Vector2i, to: Vector2i, locked: Dictionary) -> void:
	var line := hex_line(from, to, false)
	for c in line:
		if not locked.has(c):
			_tiles[c] = false
		for d in DIRECTIONS:
			var side := c + d
			if distance(side, current_room_center) < radius and not locked.has(side) and _rng.randf() < 0.35:
				_tiles[side] = false


func _refresh_exit_cells() -> void:
	exit_cells.clear()
	treasure_exit_cells.clear()
	shop_exit_cells.clear()
	for c in _cells:
		if is_unvisited_edge_cell(c):
			exit_cells.append(c)
			var face := get_face_index(current_room_center, c)
			if treasure_face >= 0 and face == treasure_face:
				treasure_exit_cells.append(c)
			elif shop_face >= 0 and face == shop_face:
				shop_exit_cells.append(c)


func is_treasure_edge_cell(cell: Vector2i) -> bool:
	return treasure_exit_cells.has(cell)


func is_shop_edge_cell(cell: Vector2i) -> bool:
	return shop_exit_cells.has(cell)


func set_room_cleared(cleared: bool) -> void:
	room_cleared = cleared
	_refresh_exit_cells()
	queue_redraw()


func _build_astar() -> void:
	_astar.clear()
	_ids.clear()
	_cells.clear()
	for c in _tiles:
		if not _tiles[c]:
			var id := _cells.size()
			_cells.append(c)
			_ids[c] = id
			_astar.add_point(id, cell_to_pixel(c))
	for c in _cells:
		for d in DIRECTIONS:
			if _ids.has(c + d):
				_astar.connect_points(_ids[c], _ids[c + d])


## Returns the cells to walk through, excluding `from`. Empty if unreachable.
## `blocked` cells (e.g. other creatures) are treated as walls for this query.
func find_path(from: Vector2i, to: Vector2i, blocked: Array[Vector2i] = [], restrict_to_current_room := false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if from == to or not _ids.has(from) or not _ids.has(to) or blocked.has(to):
		return result
	if restrict_to_current_room and not is_in_current_room(to):
		return result
	var disabled: Array[int] = []
	for c in blocked:
		if c != from and _ids.has(c):
			_astar.set_point_disabled(_ids[c], true)
			disabled.append(_ids[c])
	if restrict_to_current_room:
		for c in _cells:
			if c != from and not is_in_current_room(c) and _ids.has(c):
				_astar.set_point_disabled(_ids[c], true)
				disabled.append(_ids[c])
	var id_path := _astar.get_id_path(_ids[from], _ids[to])
	for id in disabled:
		_astar.set_point_disabled(id, false)
	for i in range(1, id_path.size()):
		result.append(_cells[id_path[i]])
	return result


func set_hover(cell: Vector2i, preview: Array[Vector2i]) -> void:
	hover_cell = cell
	path_preview = preview
	queue_redraw()


func set_spell_preview(range_cells: Array[Vector2i], aoe_cells: Array[Vector2i], color: Color) -> void:
	spell_range_cells = range_cells
	spell_aoe_cells = aoe_cells
	spell_preview_color = color
	queue_redraw()


func clear_spell_preview() -> void:
	spell_range_cells.clear()
	spell_aoe_cells.clear()
	queue_redraw()


func set_danger_cells(cells: Array[Vector2i]) -> void:
	danger_cells = cells.duplicate()
	queue_redraw()


## Crushes interior cave walls within `r` of `center_cell` into walkable floor tiles.
func crush_walls_in_radius(center_cell: Vector2i, r: int) -> bool:
	var crushed := false
	for c in cells_in_radius(center_cell, r, false):
		if distance(c, current_room_center) < radius and _tiles.get(c, true):
			_tiles[c] = false
			crushed = true
	if crushed:
		_build_astar()
		queue_redraw()
	return crushed


func play_spell_vfx(cells: Array[Vector2i], color: Color, arc_points: Array[Vector2] = []) -> Tween:
	vfx_cells = cells.duplicate()
	vfx_arc_points = arc_points.duplicate()
	vfx_color = color
	vfx_alpha = 0.75
	queue_redraw()
	var tween := create_tween()
	tween.tween_method(func(a: float) -> void:
		vfx_alpha = a
		queue_redraw()
	, 0.75, 0.0, 0.24)
	tween.tween_callback(func() -> void:
		vfx_cells.clear()
		vfx_arc_points.clear()
		queue_redraw()
	)
	return tween


func _hex_polygon(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner in _corners:
		points.append(center + corner)
	return points


func _draw() -> void:
	for c in _tiles:
		var points := _hex_polygon(cell_to_pixel(c))
		var in_active := is_in_current_room(c)
		var base_col := wall_color if _tiles[c] else floor_color
		if _sanctuary_themes.has(c):
			if _sanctuary_themes[c] == "devil":
				base_col = Color("160609") if _tiles[c] else Color("2b0d14")
			elif _sanctuary_themes[c] == "treasure":
				base_col = Color("1f1806") if _tiles[c] else Color("382c0b")
			elif _sanctuary_themes[c] == "shop":
				base_col = Color("0c1c1e") if _tiles[c] else Color("173438")
			else:
				base_col = Color("101b24") if _tiles[c] else Color("1f3345")
		if not in_active:
			base_col = base_col.darkened(0.28)
		draw_colored_polygon(points, base_col)

		if not _tiles[c] and _terrain.has(c):
			var t_type: int = int(_terrain[c])
			var cpx := cell_to_pixel(c)
			var dim := 0.55 if not in_active else 1.0
			match t_type:
				Terrain.WATER:
					draw_colored_polygon(points, Color(0.12, 0.44, 0.82, 0.56 * dim))
					draw_arc(cpx + Vector2(0, 2), hex_size * 0.42, PI * 1.15, PI * 1.85, 8, Color(0.55, 0.88, 1.0, 0.65 * dim), 1.4)
					draw_arc(cpx + Vector2(0, -3), hex_size * 0.28, PI * 0.15, PI * 0.85, 6, Color(0.65, 0.92, 1.0, 0.5 * dim), 1.2)
				Terrain.OIL:
					draw_colored_polygon(points, Color(0.07, 0.04, 0.11, 0.82 * dim))
					draw_arc(cpx, hex_size * 0.46, 0.0, TAU, 12, Color(0.55, 0.3, 0.72, 0.45 * dim), 1.5)
					draw_circle(cpx + Vector2(-4, -3), 3.0, Color(0.35, 0.7, 0.65, 0.32 * dim))
				Terrain.FIRE:
					draw_colored_polygon(points, Color(0.95, 0.28, 0.06, 0.55 * dim))
					var flame := PackedVector2Array([
						cpx + Vector2(0, -hex_size * 0.42),
						cpx + Vector2(hex_size * 0.26, hex_size * 0.18),
						cpx + Vector2(0, hex_size * 0.05),
						cpx + Vector2(-hex_size * 0.26, hex_size * 0.18),
					])
					draw_colored_polygon(flame, Color(1.0, 0.78, 0.22, 0.75 * dim))
				Terrain.ICE:
					draw_colored_polygon(points, Color(0.45, 0.86, 0.98, 0.48 * dim))
					var r := hex_size * 0.36
					draw_line(cpx + Vector2(-r, -r * 0.3), cpx + Vector2(r, r * 0.3), Color(0.9, 0.98, 1.0, 0.65 * dim), 1.3)
					draw_line(cpx + Vector2(r * 0.3, -r), cpx + Vector2(-r * 0.3, r), Color(0.9, 0.98, 1.0, 0.55 * dim), 1.3)

	# Highlight exit doorway hexes on the outer rim of the current room.
	var exit_col := exit_ready_color if room_cleared else exit_locked_color
	var exit_fill := Color(exit_col.r, exit_col.g, exit_col.b, 0.22 if room_cleared else 0.1)
	var gold_col := Color(1.0, 0.86, 0.25, 0.92) if room_cleared else Color(0.85, 0.68, 0.18, 0.55)
	var gold_fill := Color(1.0, 0.85, 0.22, 0.32 if room_cleared else 0.14)
	var shop_col := Color(0.25, 0.95, 0.85, 0.92) if room_cleared else Color(0.2, 0.65, 0.6, 0.55)
	var shop_fill := Color(0.22, 0.92, 0.82, 0.32 if room_cleared else 0.14)
	for c in exit_cells:
		var is_treasure_door := treasure_exit_cells.has(c)
		var is_shop_door := shop_exit_cells.has(c)
		var poly := _hex_polygon(cell_to_pixel(c))
		var d_fill := gold_fill if is_treasure_door else (shop_fill if is_shop_door else exit_fill)
		var d_col := gold_col if is_treasure_door else (shop_col if is_shop_door else exit_col)
		draw_colored_polygon(poly, d_fill)
		poly.append(poly[0])
		draw_polyline(poly, d_col, 2.5 if (is_treasure_door or is_shop_door) else 2.0)

	# Draw telegraphed boss Ground Slam danger hexes.
	if not danger_cells.is_empty():
		var danger_fill := Color(1.0, 0.15, 0.2, 0.32)
		var danger_outline := Color(1.0, 0.25, 0.25, 0.95)
		for c in danger_cells:
			var center_px := cell_to_pixel(c)
			var poly := _hex_polygon(center_px)
			draw_colored_polygon(poly, danger_fill)
			poly.append(poly[0])
			draw_polyline(poly, danger_outline, 2.2)
			var d := hex_size * 0.35
			draw_line(center_px + Vector2(-d, -d), center_px + Vector2(d, d), danger_outline, 2.0)
			draw_line(center_px + Vector2(-d, d), center_px + Vector2(d, -d), danger_outline, 2.0)

	# Draw valid cast range cells when aiming a spell.
	if not spell_range_cells.is_empty():
		var range_fill := Color(spell_preview_color.r, spell_preview_color.g, spell_preview_color.b, 0.12)
		var range_outline := Color(spell_preview_color.r, spell_preview_color.g, spell_preview_color.b, 0.4)
		for c in spell_range_cells:
			var poly := _hex_polygon(cell_to_pixel(c))
			draw_colored_polygon(poly, range_fill)
			poly.append(poly[0])
			draw_polyline(poly, range_outline, 1.2)

	# Draw affected AoE / beam / chain cells when aiming a spell.
	if not spell_aoe_cells.is_empty():
		var aoe_fill := Color(spell_preview_color.r, spell_preview_color.g, spell_preview_color.b, 0.38)
		var aoe_outline := Color(spell_preview_color.r, spell_preview_color.g, spell_preview_color.b, 0.95)
		for c in spell_aoe_cells:
			var poly := _hex_polygon(cell_to_pixel(c))
			draw_colored_polygon(poly, aoe_fill)
			poly.append(poly[0])
			draw_polyline(poly, aoe_outline, 2.2)

	# Draw active spell VFX burst/arcs.
	if vfx_alpha > 0.01:
		var burst_fill := Color(vfx_color.r, vfx_color.g, vfx_color.b, vfx_alpha)
		var burst_outline := Color(1.0, 1.0, 1.0, vfx_alpha)
		for c in vfx_cells:
			var poly := _hex_polygon(cell_to_pixel(c))
			draw_colored_polygon(poly, burst_fill)
			poly.append(poly[0])
			draw_polyline(poly, burst_outline, 2.5)
		if vfx_arc_points.size() >= 2:
			draw_polyline(PackedVector2Array(vfx_arc_points), Color(1.0, 1.0, 1.0, vfx_alpha), 3.5)
			draw_polyline(PackedVector2Array(vfx_arc_points), Color(vfx_color.r, vfx_color.g, vfx_color.b, vfx_alpha), 6.0)

	for c in path_preview:
		draw_circle(cell_to_pixel(c), hex_size * 0.18, path_color)
	if not path_preview.is_empty():
		var end := path_preview[path_preview.size() - 1]
		var outline := _hex_polygon(cell_to_pixel(end))
		outline.append(outline[0])
		draw_polyline(outline, path_color, 2.0)

	if is_walkable(hover_cell):
		draw_colored_polygon(_hex_polygon(cell_to_pixel(hover_cell)), hover_color)
