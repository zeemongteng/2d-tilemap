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
	if data.type in [ItemData.Type.DEVIL_PORTAL, ItemData.Type.ANGEL_PORTAL, ItemData.Type.RETURN_PORTAL]:
		draw_circle(Vector2.ZERO, FONT_SIZE * 0.72, Color(data.color.r, data.color.g, data.color.b, 0.22))
		draw_arc(Vector2.ZERO, FONT_SIZE * 0.78, 0.0, TAU, 24, data.color, 2.5)
		draw_arc(Vector2.ZERO, FONT_SIZE * 0.52, 0.0, TAU, 20, Color.WHITE, 1.4)
	elif is_pedestal:
		var base_col := Color(0.95, 0.85, 0.45, 0.7) if is_angel_pedestal else Color(0.85, 0.22, 0.28, 0.75)
		draw_rect(Rect2(Vector2(-13, 4), Vector2(26, 9)), Color(0.18, 0.18, 0.22, 0.95))
		draw_rect(Rect2(Vector2(-13, 4), Vector2(26, 9)), base_col, false, 1.6)
		var tag := "FREE" if data.hp_cost <= 0 else "-%d HP" % data.hp_cost
		var tag_col := Color(1.0, 0.92, 0.45) if data.hp_cost <= 0 else Color(1.0, 0.35, 0.38)
		draw_string(font, Vector2(-FONT_SIZE * 1.2, FONT_SIZE * 1.15), tag, HORIZONTAL_ALIGNMENT_CENTER, FONT_SIZE * 2.4, 11, tag_col)
	elif data.type == ItemData.Type.RELIC:
		draw_arc(Vector2.ZERO, FONT_SIZE * 0.62, 0.0, TAU, 20, Color(data.color.r, data.color.g, data.color.b, 0.55), 2.0)

	var offset := Vector2(-FONT_SIZE, FONT_SIZE * 0.35)
	draw_string(font, offset, data.glyph, HORIZONTAL_ALIGNMENT_CENTER, FONT_SIZE * 2.0, FONT_SIZE, data.color)
