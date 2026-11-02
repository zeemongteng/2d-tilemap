class_name WorldItem
extends Node2D
## An item lying on the ground. Walk over it to pick it up.

const FONT_SIZE := 22

var data: ItemData
var cell := Vector2i.ZERO


func setup(item: ItemData, grid: HexGrid, target_cell: Vector2i) -> void:
	data = item
	cell = target_cell
	position = grid.cell_to_pixel(cell)
	queue_redraw()


func _draw() -> void:
	if data == null:
		return
	var offset := Vector2(-FONT_SIZE, FONT_SIZE * 0.35)
	draw_string(ThemeDB.fallback_font, offset, data.glyph, HORIZONTAL_ALIGNMENT_CENTER, FONT_SIZE * 2.0, FONT_SIZE, data.color)
