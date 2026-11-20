class_name WorldItem
extends Node2D
## An item, portal, or Deal pedestal lying on the ground. Walk over it to interact.

const FONT_SIZE := 22

var data: ItemData
var cell := Vector2i.ZERO
var is_pedestal := false
var is_angel_pedestal := false

var _anim_time := 0.0
var _bob_phase := 0.0


func setup(item: ItemData, grid: HexGrid, target_cell: Vector2i, pedestal := false, angel_pedestal := false) -> void:
	data = item
	cell = target_cell
	is_pedestal = pedestal
	is_angel_pedestal = angel_pedestal
	position = grid.cell_to_pixel(cell)
	_bob_phase = float((cell.x * 19 + cell.y * 37) & 255) * 0.05
	queue_redraw()


func _process(delta: float) -> void:
	if data == null:
		return
	_anim_time += delta
	queue_redraw()


func _is_portal() -> bool:
	return data.type in [
		ItemData.Type.DEVIL_PORTAL,
		ItemData.Type.ANGEL_PORTAL,
		ItemData.Type.TREASURE_PORTAL,
		ItemData.Type.SHOP_PORTAL,
		ItemData.Type.RETURN_PORTAL,
	]


func _is_altar() -> bool:
	return data.type in [ItemData.Type.SHRINE_OF_CHANCE, ItemData.Type.BLOOD_ALTAR]


func _draw() -> void:
	if data == null:
		return
	var font := ThemeDB.fallback_font
	if _is_portal():
		var pulse := 1.0 + 0.06 * sin(_anim_time * 3.5 + _bob_phase)
		draw_circle(Vector2.ZERO, FONT_SIZE * 0.72 * pulse, Color(data.color.r, data.color.g, data.color.b, 0.22))
		draw_arc(Vector2.ZERO, FONT_SIZE * 0.78 * pulse, 0.0, TAU, 24, data.color, 2.5)
		draw_arc(Vector2.ZERO, FONT_SIZE * 0.52, 0.0, TAU, 20, Color.WHITE, 1.4)
		var offset := Vector2(-FONT_SIZE, FONT_SIZE * 0.35)
		draw_string(font, offset, data.glyph, HORIZONTAL_ALIGNMENT_CENTER, FONT_SIZE * 2.0, FONT_SIZE, data.color)
		return

	if _is_altar():
		var altar_col := data.color
		draw_circle(Vector2.ZERO, FONT_SIZE * 0.68, Color(altar_col.r, altar_col.g, altar_col.b, 0.18))
		draw_arc(Vector2.ZERO, FONT_SIZE * 0.72, 0.0, TAU, 6, altar_col, 2.2)
		draw_rect(Rect2(Vector2(-14, 5), Vector2(28, 8)), Color(0.14, 0.14, 0.18, 0.95))
		draw_rect(Rect2(Vector2(-14, 5), Vector2(28, 8)), altar_col, false, 1.5)
		var shrine_tag := "%d¢" % data.gold_cost if data.type == ItemData.Type.SHRINE_OF_CHANCE else "-%d HP" % data.hp_cost
		var shrine_tag_col := Color(1.0, 0.9, 0.35) if data.type == ItemData.Type.SHRINE_OF_CHANCE else Color(1.0, 0.35, 0.4)
		draw_string(font, Vector2(-FONT_SIZE * 1.2, FONT_SIZE * 1.18), shrine_tag, HORIZONTAL_ALIGNMENT_CENTER, FONT_SIZE * 2.4, 11, shrine_tag_col)
		var offset := Vector2(-FONT_SIZE, FONT_SIZE * 0.35)
		draw_string(font, offset, data.glyph, HORIZONTAL_ALIGNMENT_CENTER, FONT_SIZE * 2.0, FONT_SIZE, data.color)
		return

	if is_pedestal:
		var base_col := Color(0.95, 0.85, 0.45, 0.75) if is_angel_pedestal else Color(0.85, 0.22, 0.28, 0.8)
		if data.gold_cost > 0:
			base_col = Color(1.0, 0.42, 0.22, 0.92) if data.is_on_sale else Color(0.35, 0.95, 0.65, 0.85)
		draw_rect(Rect2(Vector2(-13, 5), Vector2(26, 8)), Color(0.16, 0.16, 0.21, 0.96))
		draw_rect(Rect2(Vector2(-13, 5), Vector2(26, 8)), base_col, false, 1.6)
		var tag := "FREE"
		var tag_col := Color(1.0, 0.92, 0.45)
		if data.gold_cost > 0:
			tag = "%d¢ SALE!" % data.gold_cost if data.is_on_sale else "%d¢" % data.gold_cost
			tag_col = Color(1.0, 0.42, 0.22) if data.is_on_sale else Color(1.0, 0.88, 0.28)
		elif data.hp_cost > 0:
			tag = "-%d HP" % data.hp_cost
			tag_col = Color(1.0, 0.35, 0.38)
		draw_string(font, Vector2(-FONT_SIZE * 1.35, FONT_SIZE * 1.18), tag, HORIZONTAL_ALIGNMENT_CENTER, FONT_SIZE * 2.7, 11, tag_col)

	var bob := sin(_anim_time * 3.0 + _bob_phase) * 1.4
	var center := Vector2(0.0, (-5.5 if is_pedestal else 0.0) + bob)

	# Ground shadow under loose items so they visually sit on the floor rather than standing like monsters.
	if not is_pedestal:
		draw_set_transform(Vector2(0.0, 9.0), 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, 9.5, Color(0.0, 0.0, 0.0, 0.38))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_item_icon(center, font)


func _draw_item_icon(c: Vector2, font: Font) -> void:
	var col := data.color
	var dark_bg := Color(0.08, 0.09, 0.12, 0.92)
	var light_col := col.lightened(0.45)

	match data.type:
		ItemData.Type.POTION, ItemData.Type.MANA_POTION:
			# Glass flask silhouette with colored liquid & cork.
			draw_circle(c + Vector2(0, 2.5), 7.8, dark_bg)
			draw_circle(c + Vector2(0, 2.5), 6.2, col)
			draw_arc(c + Vector2(0, 2.5), 7.6, 0.0, TAU, 18, light_col, 1.4)
			# Narrow neck + cork stopper.
			draw_rect(Rect2(c + Vector2(-3.0, -7.5), Vector2(6.0, 4.5)), dark_bg)
			draw_rect(Rect2(c + Vector2(-3.0, -7.5), Vector2(6.0, 4.5)), light_col, false, 1.3)
			draw_rect(Rect2(c + Vector2(-2.2, -9.8), Vector2(4.4, 2.6)), Color(0.72, 0.52, 0.3))
			# Specular glass shine.
			draw_circle(c + Vector2(-2.4, 0.6), 1.7, Color(1.0, 1.0, 1.0, 0.8))

		ItemData.Type.WEAPON:
			# Tilted diamond loot badge + diagonal sword blade.
			var box := PackedVector2Array([
				c + Vector2(0, -10.5),
				c + Vector2(10.5, 0),
				c + Vector2(0, 10.5),
				c + Vector2(-10.5, 0),
			])
			draw_colored_polygon(box, dark_bg)
			box.append(box[0])
			draw_polyline(box, col, 1.6)
			# Sword blade & crossguard inside.
			draw_line(c + Vector2(-5.5, 5.5), c + Vector2(5.5, -5.5), light_col, 2.6)
			draw_line(c + Vector2(-4.5, 1.0), c + Vector2(-1.0, 4.5), col, 2.2)
			draw_circle(c + Vector2(-5.8, 5.8), 1.6, col)

		ItemData.Type.ARMOR:
			# Heater shield silhouette.
			var shield := PackedVector2Array([
				c + Vector2(-8.0, -7.5),
				c + Vector2(8.0, -7.5),
				c + Vector2(7.5, 1.0),
				c + Vector2(0.0, 9.5),
				c + Vector2(-7.5, 1.0),
			])
			draw_colored_polygon(shield, dark_bg)
			var inner := PackedVector2Array([
				c + Vector2(-5.8, -5.5),
				c + Vector2(5.8, -5.5),
				c + Vector2(5.4, 0.5),
				c + Vector2(0.0, 6.8),
				c + Vector2(-5.4, 0.5),
			])
			draw_colored_polygon(inner, Color(col.r, col.g, col.b, 0.48))
			shield.append(shield[0])
			draw_polyline(shield, light_col, 1.6)
			draw_line(c + Vector2(0.0, -5.5), c + Vector2(0.0, 6.8), light_col, 1.2)

		ItemData.Type.BOMB:
			# Round iron bomb + curved fuse + flickering spark.
			draw_circle(c + Vector2(-0.5, 1.8), 7.5, Color(0.14, 0.14, 0.18, 0.98))
			draw_arc(c + Vector2(-0.5, 1.8), 7.5, 0.0, TAU, 18, col, 1.6)
			draw_circle(c + Vector2(-3.0, -0.5), 2.0, Color(1.0, 1.0, 1.0, 0.55))
			draw_rect(Rect2(c + Vector2(-2.5, -7.2), Vector2(4.5, 2.6)), col)
			draw_line(c + Vector2(0.0, -7.2), c + Vector2(5.0, -10.5), Color(0.85, 0.75, 0.55), 1.6)
			var spark_r := 2.4 + 0.8 * sin(_anim_time * 14.0 + _bob_phase)
			draw_circle(c + Vector2(5.5, -10.8), spark_r, Color(1.0, 0.85, 0.25))
			draw_circle(c + Vector2(5.5, -10.8), spark_r * 0.5, Color.WHITE)

		ItemData.Type.PILL:
			# Two-tone capsule pill.
			draw_circle(c + Vector2(-3.5, 2.0), 4.8, Color(0.95, 0.95, 0.98))
			draw_circle(c + Vector2(3.5, -2.0), 4.8, col)
			var mid := PackedVector2Array([
				c + Vector2(-5.8, -2.0),
				c + Vector2(1.2, -6.0),
				c + Vector2(5.8, 2.0),
				c + Vector2(-1.2, 6.0),
			])
			draw_colored_polygon(mid, Color(col.r, col.g, col.b, 0.85))
			draw_circle(c + Vector2(-3.5, 2.0), 4.4, Color(0.95, 0.95, 0.98))
			draw_arc(c + Vector2(-3.5, 2.0), 4.6, 0.0, TAU, 12, dark_bg, 1.3)
			draw_arc(c + Vector2(3.5, -2.0), 4.6, 0.0, TAU, 12, dark_bg, 1.3)

		ItemData.Type.SPELL_ORB:
			# Glowing faceted soul crystal.
			var glow := 0.24 + 0.1 * sin(_anim_time * 4.0 + _bob_phase)
			draw_circle(c, 11.0, Color(col.r, col.g, col.b, glow))
			var gem := PackedVector2Array([
				c + Vector2(0, -9.5),
				c + Vector2(7.0, 0),
				c + Vector2(0, 9.5),
				c + Vector2(-7.0, 0),
			])
			draw_colored_polygon(gem, col)
			gem.append(gem[0])
			draw_polyline(gem, Color.WHITE, 1.4)
			draw_circle(c + Vector2(-1.5, -2.5), 2.2, Color(1.0, 1.0, 1.0, 0.85))

		ItemData.Type.GOLD:
			# Metallic coin disc scaled by coin denomination (Penny / Nickel / Dime).
			var coin_r := 8.5 if data.gold_amount >= 10 else (7.4 if data.gold_amount >= 5 else 6.4)
			draw_circle(c, coin_r, col.darkened(0.2))
			draw_circle(c, coin_r - 1.5, col)
			draw_arc(c, coin_r, 0.0, TAU, 18, light_col, 1.4)
			draw_string(font, c + Vector2(-coin_r, 4.0), "¢", HORIZONTAL_ALIGNMENT_CENTER, coin_r * 2.0, 12, dark_bg)

		ItemData.Type.RELIC:
			# Ornate glowing relic diamond plaque with corner pips & '?' sigil.
			var pulse := 0.22 + 0.1 * sin(_anim_time * 3.8 + _bob_phase)
			draw_circle(c, 12.5, Color(col.r, col.g, col.b, pulse))
			var plaque := PackedVector2Array([
				c + Vector2(0, -11.5),
				c + Vector2(11.5, 0),
				c + Vector2(0, 11.5),
				c + Vector2(-11.5, 0),
			])
			draw_colored_polygon(plaque, dark_bg)
			plaque.append(plaque[0])
			draw_polyline(plaque, col, 2.0)
			for pt in [Vector2(0, -11.5), Vector2(11.5, 0), Vector2(0, 11.5), Vector2(-11.5, 0)]:
				draw_circle(c + pt, 1.8, light_col)
			draw_string(font, c + Vector2(-10.0, 5.0), "?", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 14, light_col)

		ItemData.Type.SPELL_PEDESTAL:
			# Glowing grimoire / spell tome icon with star rune.
			var glow := 0.22 + 0.1 * sin(_anim_time * 4.0 + _bob_phase)
			draw_circle(c, 12.0, Color(col.r, col.g, col.b, glow))
			draw_rect(Rect2(c + Vector2(-8.5, -7.5), Vector2(17.0, 15.0)), dark_bg)
			draw_rect(Rect2(c + Vector2(-8.5, -7.5), Vector2(17.0, 15.0)), col, false, 1.8)
			draw_line(c + Vector2(0.0, -7.5), c + Vector2(0.0, 7.5), col, 1.3)
			draw_string(font, c + Vector2(-10.0, 4.8), "★", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 13, light_col)

		_:
			# Fallback framed loot badge.
			draw_rect(Rect2(c + Vector2(-8.5, -8.5), Vector2(17.0, 17.0)), dark_bg)
			draw_rect(Rect2(c + Vector2(-8.5, -8.5), Vector2(17.0, 17.0)), col, false, 1.6)
			draw_string(font, c + Vector2(-10.0, 5.0), data.glyph, HORIZONTAL_ALIGNMENT_CENTER, 20.0, 14, col)
