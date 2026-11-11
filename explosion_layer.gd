class_name ExplosionLayer
extends Node2D
## Rift Wizard-style explosion overlay: each hex of an AoE bursts in turn, rippling outward
## ring by ring from the epicenter with a white-hot flash, an expanding shock ring and sparks.

const RING_DELAY := 0.05
const BURST_LIFE := 0.34
const SPARKS_PER_CELL := 5

var hex_size := 26.0
var _corners: PackedVector2Array = PackedVector2Array()
var _bursts: Array[Dictionary] = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 50
	_rng.randomize()
	set_process(false)


func setup(size: float, corners: PackedVector2Array) -> void:
	hex_size = size
	_corners = corners


## Queues one burst per pixel position. `rings[i]` is the ring index (distance from epicenter)
## used to stagger the burst. Returns the total duration of the explosion in seconds.
func explode(positions: Array[Vector2], rings: Array[int], color: Color) -> float:
	var max_ring := 0
	for i in positions.size():
		var ring := rings[i] if i < rings.size() else 0
		max_ring = maxi(max_ring, ring)
		var sparks: Array[Dictionary] = []
		for _s in SPARKS_PER_CELL:
			var ang := _rng.randf() * TAU
			sparks.append({
				"dir": Vector2(cos(ang), sin(ang)),
				"speed": hex_size * _rng.randf_range(0.6, 1.25),
				"size": _rng.randf_range(1.8, 3.6),
				"tint": color.lightened(_rng.randf_range(0.0, 0.55)),
			})
		_bursts.append({
			"pos": positions[i],
			"start": _time + RING_DELAY * float(ring),
			"color": color,
			"sparks": sparks,
			"rot": _rng.randf() * TAU,
		})
	set_process(true)
	queue_redraw()
	return RING_DELAY * float(max_ring) + BURST_LIFE


func _process(delta: float) -> void:
	_time += delta
	for i in range(_bursts.size() - 1, -1, -1):
		if _time - float(_bursts[i]["start"]) > BURST_LIFE:
			_bursts.remove_at(i)
	if _bursts.is_empty():
		_time = 0.0
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for b in _bursts:
		var t := (_time - float(b["start"])) / BURST_LIFE
		if t < 0.0 or t > 1.0:
			continue
		var pos: Vector2 = b["pos"]
		var col: Color = b["color"]
		var fade := 1.0 - t

		# 1. Hex flash: white-hot at the start, cooling into the element colour.
		var flash := Color.WHITE.lerp(col, clampf(t * 2.5, 0.0, 1.0))
		flash.a = 0.85 * fade
		var poly := PackedVector2Array()
		for c in _corners:
			poly.append(pos + c * (0.92 + 0.08 * fade))
		draw_colored_polygon(poly, flash)

		# 2. Bright core that pops then shrinks.
		var core_r := hex_size * (0.55 * sin(minf(t * 2.0, 1.0) * PI * 0.5 + 0.2)) * fade
		if core_r > 0.5:
			draw_circle(pos, core_r, Color(1.0, 1.0, 0.92, 0.9 * fade))

		# 3. Expanding shock ring.
		var ring_r := hex_size * (0.25 + 0.8 * t)
		draw_arc(pos, ring_r, 0.0, TAU, 18, Color(col.r, col.g, col.b, 0.9 * fade).lightened(0.25), 2.5 * fade + 0.5)

		# 4. Rotating debris cross (gives that chunky Rift Wizard pixel-burst feel).
		var rot: float = float(b["rot"]) + t * 2.0
		var arm := hex_size * 0.5 * (0.4 + t)
		for k in 3:
			var a := rot + float(k) * PI / 3.0
			var d := Vector2(cos(a), sin(a)) * arm
			draw_line(pos - d, pos + d, Color(1.0, 1.0, 1.0, 0.55 * fade), 1.5)

		# 5. Sparks flying outward.
		for s in b["sparks"]:
			var sdir: Vector2 = s["dir"]
			var sp := pos + sdir * float(s["speed"]) * (1.0 - pow(1.0 - t, 2.0))
			var tint: Color = s["tint"]
			tint.a = fade
			var sz := float(s["size"]) * (0.4 + fade)
			draw_rect(Rect2(sp - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), tint)
