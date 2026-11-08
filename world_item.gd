class_name WorldItem
extends Node2D
## An item, portal, or Deal pedestal lying on the ground. Walk over it to interact.

const FONT_SIZE := 22

var data: ItemData
var cell := Vector2i.ZERO
var is_pedestal := false
var is_angel_pedestal := false


func setup(item: ItemData, grid: HexGrid, target_cell: Vector2i, pedestal := false, angel_pedestal := false) -> void:
	data = item
	cell = target_cell
	is_pedestal = pedestal
	is_angel_pedestal = angel_pedestal
	position = grid.cell_to_pixel(cell)
	queue_redraw()


func _draw() -> void:
	if data == null:
		return
	var font := ThemeDB.fallback_font
	if data.type in [
		ItemData.Type.DEVIL_PORTAL,
		ItemData.Type.ANGEL_PORTAL,
		ItemData.Type.TREASURE_PORTAL,
		ItemData.Type.SHOP_PORTAL,
		ItemData.Type.RETURN_PORTAL,
	]:
		draw_circle(Vector2.ZERO, FONT_SIZE * 0.72, Color(data.color.r, data.color.g, data.color.b, 0.22))
		draw_arc(Vector2.ZERO, FONT_SIZE * 0.78, 0.0, TAU, 24, data.color, 2.5)
		draw_arc(Vector2.ZERO, FONT_SIZE * 0.52, 0.0, TAU, 20, Color.WHITE, 1.4)
	elif data.type in [ItemData.Type.SHRINE_OF_CHANCE, ItemData.Type.BLOOD_ALTAR]:
		var altar_col := data.color
		draw_circle(Vector2.ZERO, FONT_SIZE * 0.68, Color(altar_col.r, altar_col.g, altar_col.b, 0.18))
		draw_arc(Vector2.ZERO, FONT_SIZE * 0.72, 0.0, TAU, 6, altar_col, 2.2)
		draw_rect(Rect2(Vector2(-14, 5), Vector2(28, 8)), Color(0.14, 0.14, 0.18, 0.95))
		draw_rect(Rect2(Vector2(-14, 5), Vector2(28, 8)), altar_col, false, 1.5)
		var shrine_tag := "%d¢" % data.gold_cost if data.type == ItemData.Type.SHRINE_OF_CHANCE else "-%d HP" % data.hp_cost
		var shrine_tag_col := Color(1.0, 0.9, 0.35) if data.type == ItemData.Type.SHRINE_OF_CHANCE else Color(1.0, 0.35, 0.4)
		draw_string(font, Vector2(-FONT_SIZE * 1.2, FONT_SIZE * 1.18), shrine_tag, HORIZONTAL_ALIGNMENT_CENTER, FONT_SIZE * 2.4, 11, shrine_tag_col)
	elif is_pedestal:
		var base_col := Color(0.95, 0.85, 0.45, 0.7) if is_angel_pedestal else Color(0.85, 0.22, 0.28, 0.75)
		if data.gold_cost > 0:
			base_col = Color(1.0, 0.42, 0.22, 0.9) if data.is_on_sale else Color(0.35, 0.95, 0.65, 0.8)
		draw_rect(Rect2(Vector2(-13, 4), Vector2(26, 9)), Color(0.18, 0.18, 0.22, 0.95))
		draw_rect(Rect2(Vector2(-13, 4), Vector2(26, 9)), base_col, false, 1.6)
		var tag := "FREE"
		var tag_col := Color(1.0, 0.92, 0.45)
		if data.gold_cost > 0:
			tag = "%d¢ SALE!" % data.gold_cost if data.is_on_sale else "%d¢" % data.gold_cost
			tag_col = Color(1.0, 0.42, 0.22) if data.is_on_sale else Color(1.0, 0.88, 0.28)
		elif data.hp_cost > 0:
			tag = "-%d HP" % data.hp_cost
			tag_col = Color(1.0, 0.35, 0.38)
		draw_string(font, Vector2(-FONT_SIZE * 1.35, FONT_SIZE * 1.15), tag, HORIZONTAL_ALIGNMENT_CENTER, FONT_SIZE * 2.7, 11, tag_col)
	elif data.type == ItemData.Type.GOLD:
		var coin_rad := FONT_SIZE * (0.52 if data.gold_amount >= 10 else (0.46 if data.gold_amount >= 5 else 0.40))
		draw_circle(Vector2.ZERO, coin_rad, Color(data.color.r, data.color.g, data.color.b, 0.28))
		draw_arc(Vector2.ZERO, coin_rad, 0.0, TAU, 20, data.color, 2.0)
	elif data.type == ItemData.Type.RELIC:
		draw_arc(Vector2.ZERO, FONT_SIZE * 0.62, 0.0, TAU, 20, Color(data.color.r, data.color.g, data.color.b, 0.55), 2.0)

	var offset := Vector2(-FONT_SIZE, FONT_SIZE * 0.35)
	draw_string(font, offset, data.glyph, HORIZONTAL_ALIGNMENT_CENTER, FONT_SIZE * 2.0, FONT_SIZE, data.color)
