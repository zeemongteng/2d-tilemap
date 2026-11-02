class_name Hud
extends CanvasLayer

signal spell_selected(index: int)
signal item_selected(index: int)
signal spell_learn_requested(template: SpellData)
signal spell_upgrade_requested(spell: SpellData)
signal next_room_requested()

const MAX_LOG_LINES := 6
const SPELL_KEYS: Array[String] = ["Q", "W", "E", "F", "G", "C"]

@onready var stats_label: Label = $Stats
@onready var next_room_button: Button = $SpellPanel/NextRoomButton
@onready var spell_list: VBoxContainer = $SpellPanel/SpellList
@onready var spellbook_button: Button = $SpellPanel/SpellbookButton
@onready var targeting_banner: Label = $SpellPanel/TargetingBanner
@onready var inventory_list: VBoxContainer = $InventoryPanel/InventoryList
@onready var log_label: Label = $Log
@onready var spellbook_modal: PanelContainer = $SpellbookModal
@onready var spellbook_title: Label = $SpellbookModal/Margin/VBox/TopBar/Title
@onready var close_button: Button = $SpellbookModal/Margin/VBox/TopBar/CloseButton
@onready var catalog_list: VBoxContainer = $SpellbookModal/Margin/VBox/Scroll/CatalogList

@onready var info_popup: PanelContainer = $InfoPopup
@onready var popup_title: Label = $InfoPopup/Margin/VBox/PopupTitle
@onready var popup_subtitle: Label = $InfoPopup/Margin/VBox/PopupSubtitle
@onready var popup_body: Label = $InfoPopup/Margin/VBox/PopupBody

var _lines := PackedStringArray()
var _spell_catalog: Array[SpellData] = []
var _last_player: Actor
var _last_turn := 0
var _active_spell_index := -1
var _ui_hover_active := false


func _ready() -> void:
	spellbook_button.pressed.connect(toggle_spellbook)
	close_button.pressed.connect(close_spellbook)
	next_room_button.pressed.connect(func() -> void:
		next_room_requested.emit()
	)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.1, 0.96)
	style.border_color = Color(0.45, 0.62, 0.52, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	info_popup.add_theme_stylebox_override("panel", style)


func _process(_delta: float) -> void:
	if info_popup.visible:
		_update_popup_position()


func set_spell_catalog(catalog: Array[SpellData]) -> void:
	_spell_catalog = catalog


func is_spellbook_open() -> bool:
	return spellbook_modal.visible


func toggle_spellbook() -> void:
	spellbook_modal.visible = not spellbook_modal.visible
	hide_popup()
	if spellbook_modal.visible and _last_player != null:
		_rebuild_spellbook(_last_player)


func close_spellbook() -> void:
	spellbook_modal.visible = false


func show_item_popup(item: ItemData, from_ui := true) -> void:
	if item == null:
		return
	_ui_hover_active = from_ui
	popup_title.text = "%s %s" % [item.glyph, item.display_name]
	popup_title.modulate = item.color.lerp(Color.WHITE, 0.35)
	popup_subtitle.text = item.type_name()
	popup_body.text = item.description if not item.description.is_empty() else "Click to use."
	info_popup.reset_size()
	info_popup.visible = true
	_update_popup_position()


func show_spell_popup(spell: SpellData, from_ui := true) -> void:
	if spell == null:
		return
	_ui_hover_active = from_ui
	popup_title.text = "%s (Lv.%d/%d)" % [spell.display_name, spell.level, spell.max_level]
	popup_title.modulate = spell.color.lerp(Color.WHITE, 0.35)
	var range_part := "  •  Rng %d" % spell.effective_range() if spell.effective_range() > 0 else ""
	popup_subtitle.text = "%s  •  %s  •  %d DMG%s  •  %d/%d Charges" % [
		spell.element_name(), spell.pattern_name(),
		spell.effective_damage(), range_part,
		spell.charges, spell.effective_max_charges()
	]
	popup_body.text = spell.description
	info_popup.reset_size()
	info_popup.visible = true
	_update_popup_position()


func show_actor_popup(actor: Actor) -> void:
	if actor == null:
		return
	_ui_hover_active = false
	popup_title.text = "%s %s" % [actor.glyph, actor.display_name.capitalize()]
	popup_title.modulate = actor.color.lerp(Color.WHITE, 0.35)
	if actor.is_spawner:
		popup_subtitle.text = "HP %d/%d  •  DEF %d  •  Spawns in %d turn(s)" % [
			actor.stats.hp, actor.stats.max_hp, actor.total_defense(), actor.spawn_cooldown
		]
	else:
		var rng_str := "  •  Rng %d" % actor.attack_range if actor.attack_range > 1 else ""
		popup_subtitle.text = "HP %d/%d  •  ATK %d  •  DEF %d%s" % [
			actor.stats.hp, actor.stats.max_hp, actor.total_attack(), actor.total_defense(), rng_str
		]
	popup_body.text = actor.description if not actor.description.is_empty() else "Hostile creature."
	info_popup.reset_size()
	info_popup.visible = true
	_update_popup_position()


func show_world_hover_popup(actor: Actor, item: ItemData) -> void:
	if _ui_hover_active:
		return
	if actor != null:
		show_actor_popup(actor)
	elif item != null:
		show_item_popup(item, false)
	else:
		info_popup.visible = false


func hide_popup() -> void:
	_ui_hover_active = false
	info_popup.visible = false


func _update_popup_position() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var mouse := get_viewport().get_mouse_position()
	var pop_size := info_popup.size
	var pos := mouse + Vector2(18, 16)
	if pos.x + pop_size.x + 12 > vp_size.x:
		pos.x = mouse.x - pop_size.x - 18
	if pos.y + pop_size.y + 12 > vp_size.y:
		pos.y = vp_size.y - pop_size.y - 12
	pos.x = maxf(8.0, pos.x)
	pos.y = maxf(8.0, pos.y)
	info_popup.position = pos


func post(message: String) -> void:
	_lines.append(message)
	if _lines.size() > MAX_LOG_LINES:
		_lines.remove_at(0)
	log_label.text = "\n".join(_lines)


func refresh(player: Actor, turn: int, active_spell_idx := -1, room := 1, remaining_foes := 0, room_cleared := false) -> void:
	_last_player = player
	_last_turn = turn
	_active_spell_index = active_spell_idx
	if _ui_hover_active:
		hide_popup()

	var weapon := player.weapon.describe() if player.weapon != null else "none"
	var armor := player.armor.describe() if player.armor != null else "none"
	var status_parts: Array[String] = []
	if player.frozen_turns > 0:
		status_parts.append("FROZEN (%dt)" % player.frozen_turns)
	if player.burn_turns > 0:
		status_parts.append("BURNING (%dt)" % player.burn_turns)
	var status_line := "\nStatus: " + ", ".join(status_parts) if not status_parts.is_empty() else ""

	var room_status := "★ CLEARED ★" if room_cleared else "Foes: %d" % remaining_foes
	stats_label.text = "Room %d (%s)  |  Turn %d  |  SP: %d\nHP %d/%d   ATK %d   DEF %d\nWeapon: %s\nArmor: %s%s" % [
		room, room_status, turn, player.spell_points,
		player.stats.hp, player.stats.max_hp,
		player.total_attack(), player.total_defense(),
		weapon, armor, status_line,
	]

	next_room_button.visible = room_cleared
	next_room_button.text = "★ ROOM CLEARED — [N] Enter Room %d ★" % (room + 1)

	spellbook_button.text = "[B] Grimoire / Upgrade Spells (%d SP)" % player.spell_points
	_rebuild_spells(player, active_spell_idx)
	_rebuild_inventory(player)
	if spellbook_modal.visible:
		_rebuild_spellbook(player)


func _rebuild_spells(player: Actor, active_spell_idx: int) -> void:
	for child in spell_list.get_children():
		child.queue_free()

	for i in player.spells.size():
		var spell := player.spells[i]
		var key_label: String = SPELL_KEYS[i] if i < SPELL_KEYS.size() else str(i + 1)
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var active_prefix := ">> " if i == active_spell_idx else ""
		btn.text = "%s%s  •  %d DMG" % [active_prefix, spell.describe_button(key_label), spell.effective_damage()]
		if spell.charges <= 0:
			btn.modulate = Color(0.55, 0.55, 0.55)
		elif i == active_spell_idx:
			btn.modulate = Color(1.0, 0.92, 0.45)
		else:
			btn.modulate = spell.color.lerp(Color.WHITE, 0.45)
		var idx := i
		var sp := spell
		btn.pressed.connect(func() -> void:
			spell_selected.emit(idx)
		)
		btn.mouse_entered.connect(func() -> void:
			show_spell_popup(sp, true)
		)
		btn.mouse_exited.connect(hide_popup)
		spell_list.add_child(btn)

	if active_spell_idx >= 0 and active_spell_idx < player.spells.size():
		var active := player.spells[active_spell_idx]
		targeting_banner.visible = true
		targeting_banner.text = "Aiming %s (%s)\nClick highlighted hex to cast • Right-click/Esc to cancel" % [
			active.display_name, active.pattern_name()
		]
	else:
		targeting_banner.visible = false


func _rebuild_inventory(player: Actor) -> void:
	for child in inventory_list.get_children():
		child.queue_free()

	if player.inventory.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(Empty)"
		empty_lbl.modulate = Color(0.7, 0.7, 0.7)
		inventory_list.add_child(empty_lbl)
		return

	for i in player.inventory.size():
		var item := player.inventory[i]
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "[%d] %s" % [i + 1, item.describe()]
		btn.modulate = item.color.lerp(Color.WHITE, 0.45)
		var idx := i
		var it := item
		btn.pressed.connect(func() -> void:
			item_selected.emit(idx)
		)
		btn.mouse_entered.connect(func() -> void:
			show_item_popup(it, true)
		)
		btn.mouse_exited.connect(hide_popup)
		inventory_list.add_child(btn)


func _rebuild_spellbook(player: Actor) -> void:
	spellbook_title.text = "RIFT GRIMOIRE — Spell Points (SP): %d" % player.spell_points
	for child in catalog_list.get_children():
		child.queue_free()

	for template in _spell_catalog:
		var learned := player.get_learned_spell(template.display_name)
		var display_spell := learned if learned != null else template

		var row := PanelContainer.new()
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		row.add_child(hbox)

		var info_box := VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info_box)

		var title := Label.new()
		var status_tag := " (Learned Lv.%d/%d)" % [learned.level, learned.max_level] if learned != null else " (Unlearned)"
		title.text = "%s%s" % [display_spell.display_name, status_tag]
		title.modulate = display_spell.color.lerp(Color.WHITE, 0.35)
		info_box.add_child(title)

		var details := Label.new()
		details.text = display_spell.describe_details()
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.modulate = Color(0.88, 0.88, 0.88)
		info_box.add_child(details)

		var action_btn := Button.new()
		action_btn.focus_mode = Control.FOCUS_NONE
		action_btn.custom_minimum_size = Vector2(140, 38)
		if learned == null:
			action_btn.text = "Learn (%d SP)" % template.learn_cost
			action_btn.disabled = player.spell_points < template.learn_cost
			var tmpl := template
			action_btn.pressed.connect(func() -> void:
				spell_learn_requested.emit(tmpl)
			)
		elif learned.can_upgrade():
			action_btn.text = "Upgrade (%d SP)" % learned.upgrade_cost
			action_btn.disabled = player.spell_points < learned.upgrade_cost
			var sp := learned
			action_btn.pressed.connect(func() -> void:
				spell_upgrade_requested.emit(sp)
			)
		else:
			action_btn.text = "MAX LEVEL"
			action_btn.disabled = true

		hbox.add_child(action_btn)
		catalog_list.add_child(row)
