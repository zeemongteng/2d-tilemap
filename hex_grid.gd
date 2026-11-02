class_name HexGrid
extends Node2D
## Pointy-top hex grid using axial coordinates (x = q, y = r).
## Owns the cave layout, pathfinding, spell targeting overlays, and drawing.

const SQRT3 := 1.7320508075688772
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

@export var radius := 12
@export var hex_size := 26.0
## 0 = a different cave every run.
@export var rng_seed := 0
@export_range(0.0, 1.0) var fill_chance := 0.46
@export var smooth_passes := 3

@export_group("Colors")
@export var floor_color := Color("1c2a24")
@export var wall_color := Color("0b0f0d")
@export var line_color := Color("2f4a3e")
@export var hover_color := Color(1, 1, 1, 0.18)
@export var path_color := Color("e8c547")

## cell -> true if wall, false if floor.
var _tiles: Dictionary = {}
var _astar := AStar2D.new()
var _ids: Dictionary = {}
var _cells: Array[Vector2i] = []
var _corners := PackedVector2Array()

var hover_cell := Vector2i(1 << 20, 1 << 20)
var path_preview: Array[Vector2i] = []

var spell_range_cells: Array[Vector2i] = []
var spell_aoe_cells: Array[Vector2i] = []
var spell_preview_color := Color(1.0, 0.5, 0.2)

var vfx_cells: Array[Vector2i] = []
var vfx_arc_points: Array[Vector2] = []
var vfx_color := Color.WHITE
var vfx_alpha := 0.0


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


func cell_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(hex_size * SQRT3 * (cell.x + cell.y * 0.5), hex_size * 1.5 * cell.y)


func pixel_to_cell(p: Vector2) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.y / 3.0) / hex_size
	var r := (2.0 / 3.0 * p.y) / hex_size
	return _axial_round(q, r)


func is_walkable(cell: Vector2i) -> bool:
	return _tiles.has(cell) and not _tiles[cell]


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


## Returns cells along the straight hex line from `from` (exclusive) to `to` (inclusive),
## stopping if a wall is encountered.
func hex_line(from: Vector2i, to: Vector2i, stop_at_walls := true) -> Array[Vector2i]:
	var n := distance(from, to)
	var result: Array[Vector2i] = []
	if n == 0:
		return result
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		# Small nudge prevents ties right on hex edges from zig-zagging.
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


func random_floor_cell(rng: RandomNumberGenerator, min_distance_from_center := 0) -> Vector2i:
	var options: Array[Vector2i] = []
	for c in _cells:
		if distance(c, Vector2i.ZERO) >= min_distance_from_center:
			options.append(c)
	if options.is_empty():
		return Vector2i.ZERO
	return options[rng.randi_range(0, options.size() - 1)]


func generate() -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

	var region: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			region.append(Vector2i(q, r))

	_tiles.clear()
	for c in region:
		_tiles[c] = rng.randf() < fill_chance

	for i in smooth_passes:
		var next := {}
		for c in region:
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
		_tiles = next

	# Guarantee open ground around the spawn point.
	for c in region:
		if distance(c, Vector2i.ZERO) <= 2:
			_tiles[c] = false

	# Fill in pockets the player could never reach.
	var reachable := {Vector2i.ZERO: true}
	var stack: Array[Vector2i] = [Vector2i.ZERO]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRECTIONS:
			var n := c + d
			if is_walkable(n) and not reachable.has(n):
				reachable[n] = true
				stack.append(n)
	for c in region:
		if not reachable.has(c):
			_tiles[c] = true

	_build_astar()
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
func find_path(from: Vector2i, to: Vector2i, blocked: Array[Vector2i] = []) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if from == to or not _ids.has(from) or not _ids.has(to) or blocked.has(to):
		return result
	var disabled: Array[int] = []
	for c in blocked:
		if c != from and _ids.has(c):
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
		draw_colored_polygon(points, wall_color if _tiles[c] else floor_color)
		points.append(points[0])
		draw_polyline(points, line_color, 1.0)

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
