class_name Hud
extends CanvasLayer

signal spell_selected(index: int)
signal item_selected(index: int)
signal spell_learn_requested(template: SpellData)
signal spell_upgrade_requested(spell: SpellData, branch_id: String)
signal next_room_confirmed(edge_cell: Vector2i)
signal debug_action_requested(action: String)
signal debug_spawn_monster_requested(scene: PackedScene, as_ally: bool)
signal debug_spawn_item_requested(item: ItemData, grant_directly: bool)
signal debug_spawn_spell_requested(spell: SpellData, grant_directly: bool)

const MAX_LOG_LINES := 6
const SPELL_KEYS: Array[String] = ["Q", "W", "E", "F", "G", "C", "Z", "X", "V", "T"]

@onready var stats_label: Label = $Stats
@onready var boss_panel: VBoxContainer = $BossPanel
@onready var boss_title: Label = $BossPanel/BossTitle
@onready var boss_hp_bar: ProgressBar = $BossPanel/BossHpBar
@onready var cleared_banner: Label = $SpellPanel/ClearedBanner
@onready var spell_list: VBoxContainer = $SpellPanel/SpellList
@onready var spellbook_button: Button = $SpellPanel/SpellbookButton
@onready var debug_button: Button = $SpellPanel/DebugButton
@onready var targeting_banner: Label = $SpellPanel/TargetingBanner
@onready var relic_list: HFlowContainer = $InventoryPanel/RelicList
@onready var inventory_list: VBoxContainer = $InventoryPanel/InventoryList
@onready var log_label: Label = $Log
@onready var spellbook_modal: PanelContainer = $SpellbookModal
@onready var spellbook_title: Label = $SpellbookModal/Margin/VBox/TopBar/Title
@onready var close_button: Button = $SpellbookModal/Margin/VBox/TopBar/CloseButton
@onready var catalog_list: VBoxContainer = $SpellbookModal/Margin/VBox/Scroll/CatalogList

@onready var confirm_modal: PanelContainer = $ConfirmRoomModal
@onready var confirm_title: Label = $ConfirmRoomModal/Margin/VBox/ConfirmTitle
@onready var confirm_text: Label = $ConfirmRoomModal/Margin/VBox/ConfirmText
@onready var yes_button: Button = $ConfirmRoomModal/Margin/VBox/Buttons/YesButton
@onready var no_button: Button = $ConfirmRoomModal/Margin/VBox/Buttons/NoButton

@onready var debug_modal: PanelContainer = $DebugModal
@onready var close_debug_button: Button = $DebugModal/Margin/VBox/TopBar/CloseDebugButton
@onready var debug_list: VBoxContainer = $DebugModal/Margin/VBox/Scroll/DebugList

@onready var info_popup: PanelContainer = $InfoPopup
@onready var popup_title: Label = $InfoPopup/Margin/VBox/PopupTitle
@onready var popup_subtitle: Label = $InfoPopup/Margin/VBox/PopupSubtitle
@onready var popup_body: Label = $InfoPopup/Margin/VBox/PopupBody

var _lines := PackedStringArray()
var _spell_catalog: Array[SpellData] = []
var _debug_monsters: Array[Dictionary] = []
var _debug_relics: Array[ItemData] = []
var _debug_items: Array[ItemData] = []
var _debug_spells: Array[SpellData] = []
var _last_player: Actor
var _last_turn := 0
var _active_spell_index := -1
var _ui_hover_active := false
var _pending_edge_cell := Vector2i.ZERO
var _branch_choice_spell: SpellData


func _ready() -> void:
	spellbook_button.pressed.connect(toggle_spellbook)
	close_button.pressed.connect(close_spellbook)
	yes_button.pressed.connect(confirm_next_room)
	no_button.pressed.connect(close_confirm_modal)
	debug_button.pressed.connect(toggle_debug_menu)
	close_debug_button.pressed.connect(close_debug_menu)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.1, 0.96)
	style.border_color = Color(0.45, 0.62, 0.52, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	info_popup.add_theme_stylebox_override("panel", style)
	confirm_modal.add_theme_stylebox_override("panel", style)
	debug_modal.add_theme_stylebox_override("panel", style)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.14, 0.05, 0.07, 0.92)
	bar_bg.border_color = Color(0.75, 0.25, 0.3, 0.9)
	bar_bg.set_border_width_all(2)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.92, 0.2, 0.28, 0.95)
	bar_fill.set_corner_radius_all(3)
	boss_hp_bar.add_theme_stylebox_override("background", bar_bg)
	boss_hp_bar.add_theme_stylebox_override("fill", bar_fill)


func _process(_delta: float) -> void:
	if info_popup.visible:
		_update_popup_position()


func set_spell_catalog(catalog: Array[SpellData]) -> void:
	_spell_catalog = catalog


func setup_debug_catalog(
	monsters_info: Array[Dictionary],
	relics: Array[ItemData],
	items: Array[ItemData],
	spells: Array[SpellData]
) -> void:
	_debug_monsters = monsters_info
	_debug_relics = relics
	_debug_items = items
	_debug_spells = spells


func is_spellbook_open() -> bool:
	return spellbook_modal.visible


func is_confirm_open() -> bool:
	return confirm_modal.visible


func is_debug_open() -> bool:
	return debug_modal.visible


func is_any_modal_open() -> bool:
	return spellbook_modal.visible or confirm_modal.visible or debug_modal.visible


func prompt_next_room(next_room_num: int, edge_cell: Vector2i, is_boss_room := false, boss_name := "", is_treasure_room := false) -> void:
	_pending_edge_cell = edge_cell
	hide_popup()
	if is_treasure_room:
		confirm_title.text = "⚜ GOLDEN TREASURE ROOM ⚜"
		confirm_title.modulate = Color(1.0, 0.88, 0.28)
		confirm_text.text = "A shimmering golden doorway beckons!\nEnter the adjacent Treasure Vault to claim a free Relic or Spell?"
		yes_button.text = "[Y / Enter] Enter Treasure Room"
	elif is_boss_room:
		confirm_title.text = "⚠ BOSS LAIR — ENTER ROOM %d? ⚠" % next_room_num
		confirm_title.modulate = Color(1.0, 0.38, 0.38)
		confirm_text.text = "Tremors shake the cavern beyond this doorway.\n%s awaits in Room %d!" % [boss_name if not boss_name.is_empty() else "A boss", next_room_num]
		yes_button.text = "[Y / Enter] Enter Room %d" % next_room_num
	else:
		confirm_title.text = "ENTER ROOM %d?" % next_room_num
		confirm_title.modulate = Color(0.45, 1.0, 0.6)
		confirm_text.text = "You have reached the edge of the room.\nGenerate and enter Room %d in this direction?" % next_room_num
		yes_button.text = "[Y / Enter] Enter Room %d" % next_room_num
	confirm_modal.visible = true


func confirm_next_room() -> void:
	if not confirm_modal.visible:
		return
	confirm_modal.visible = false
	next_room_confirmed.emit(_pending_edge_cell)


func close_confirm_modal() -> void:
	confirm_modal.visible = false


func toggle_spellbook() -> void:
	debug_modal.visible = false
	spellbook_modal.visible = not spellbook_modal.visible
	_branch_choice_spell = null
	hide_popup()
	if spellbook_modal.visible and _last_player != null:
		_rebuild_spellbook(_last_player)


func close_spellbook() -> void:
	spellbook_modal.visible = false
	_branch_choice_spell = null


func toggle_debug_menu() -> void:
	spellbook_modal.visible = false
	debug_modal.visible = not debug_modal.visible
	hide_popup()
	if debug_modal.visible:
		_rebuild_debug_menu()


func close_debug_menu() -> void:
	debug_modal.visible = false


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
	var bonus_dmg := 0
	if _last_player != null:
		bonus_dmg = _last_player.total_spell_damage_bonus() + _last_player.element_mastery_bonus(spell)
	var bonus_rng := _last_player.total_spell_range_bonus() if _last_player != null else 0
	var eff_rng := spell.effective_range() + (bonus_rng if spell.effective_range() > 0 else 0)
	popup_title.text = "%s (Lv.%d/%d)" % [spell.display_name, spell.level, spell.max_level]
	popup_title.modulate = spell.color.lerp(Color.WHITE, 0.35)
	var range_part := "  •  Rng %d" % eff_rng if eff_rng > 0 else ""
	var dmg_part := ""
	if spell.pattern == SpellData.Pattern.SUMMON:
		dmg_part = "Summon Ally"
	elif spell.pattern == SpellData.Pattern.DASH:
		dmg_part = "Evade Attacks"
	else:
		dmg_part = "%d DMG" % (spell.effective_damage() + bonus_dmg)
	var resource_part := ""
	if spell.uses_cooldown():
		resource_part = "Ready (%dt CD)" % spell.effective_cooldown() if spell.cooldown_remaining <= 0 else "Cooldown: %d/%dt" % [spell.cooldown_remaining, spell.effective_cooldown()]
	else:
		resource_part = "%d/%d Charges" % [spell.charges, spell.effective_max_charges()]
	popup_subtitle.text = "%s  •  %s  •  %s%s  •  %s" % [
		spell.element_name(), spell.pattern_name(),
		dmg_part, range_part,
		resource_part
	]
	popup_body.text = spell.description
	if not spell.branches.is_empty():
		popup_body.text += "\nBranches: %s" % spell.branch_summary()
	info_popup.reset_size()
	info_popup.visible = true
	_update_popup_position()


func show_actor_popup(actor: Actor) -> void:
	if actor == null:
		return
	_ui_hover_active = false
	var boss_tag := ""
	if actor.is_boss:
		boss_tag = " [BOSS • 7-HEX]" if actor.footprint_radius > 0 else " [BOSS]"
		if actor.is_enraged:
			boss_tag += " [ENRAGED]"
	elif actor.was_charmed_enemy:
		boss_tag = " [CHARMED ALLY]"
	elif actor.is_elite:
		boss_tag = " [ELITE]"
	elif actor.is_allies:
		boss_tag = " [ALLY]"
	popup_title.text = "%s %s%s" % [actor.glyph, actor.display_name.capitalize(), boss_tag]
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
	var spell_info := ""
	if not actor.spells.is_empty():
		var sp_parts: Array[String] = []
		for sp in actor.spells:
			var cd_tag := "Ready" if sp.is_ready() else "CD %dt" % sp.cooldown_remaining
			sp_parts.append("%s (%s)" % [sp.display_name, cd_tag])
		spell_info = "\nSpells: %s" % ", ".join(sp_parts)
	var status_info := "\nStatuses: %s" % actor.describe_statuses() if actor.has_any_status() else ""
	var base_desc := actor.description if not actor.description.is_empty() else "Hostile creature."
	popup_body.text = "%s%s%s" % [base_desc, spell_info, status_info]
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


func refresh(
	player: Actor,
	turn: int,
	active_spell_idx := -1,
	room := 1,
	remaining_foes := 0,
	room_cleared := false,
	active_boss: Actor = null,
	room_turns := 0,
	par_turns := 18,
	flawless := true,
	synergies := ""
) -> void:
	_last_player = player
	_last_turn = turn
	_active_spell_index = active_spell_idx
	if _ui_hover_active:
		hide_popup()

	var weapon := player.weapon.describe() if player.weapon != null else "none"
	var armor := player.armor.describe() if player.armor != null else "none"
	var status_parts: Array[String] = []
	if player.evade_turns > 0:
		status_parts.append("Evasion (Dodging)")
	if player.holy_mantle_shield:
		status_parts.append("Holy Mantle Shield")
	if player.has_any_status():
		status_parts.append(player.describe_statuses())
	var status_line := "\nStatus: " + ", ".join(status_parts) if not status_parts.is_empty() else ""
	if not synergies.is_empty():
		status_line += "\n✦ Synergies: " + synergies

	var room_status := "★ CLEARED ★" if room_cleared else "Foes: %d" % remaining_foes
	var devil_tag := "ψ OK" if room_turns <= par_turns else "missed"
	var angel_tag := "† OK" if flawless else "hit"
	var deal_line := "Par %d/%dt (%s)  |  No-Hit (%s)" % [room_turns, par_turns, devil_tag, angel_tag]
	stats_label.text = "Room %d (%s)  |  Turn %d  |  SP: %d\n%s\nHP %d/%d   ATK %d   DEF %d\nWeapon: %s   Armor: %s%s" % [
		room, room_status, turn, player.spell_points,
		deal_line,
		player.stats.hp, player.stats.max_hp,
		player.total_attack(), player.total_defense(),
		weapon, armor, status_line,
	]

	if active_boss != null and is_instance_valid(active_boss) and not active_boss.is_dead():
		boss_panel.visible = true
		var enrage_tag := " 🔥 ENRAGED" if active_boss.is_enraged else ""
		var boss_status := "  [%s]" % active_boss.describe_statuses() if active_boss.has_any_status() else ""
		boss_title.text = "%s %s%s — %d / %d HP%s" % [
			active_boss.glyph, active_boss.display_name.to_upper(), enrage_tag,
			active_boss.stats.hp, active_boss.stats.max_hp, boss_status
		]
		boss_hp_bar.max_value = active_boss.stats.max_hp
		boss_hp_bar.value = active_boss.stats.hp
	else:
		boss_panel.visible = false

	cleared_banner.visible = room_cleared

	spellbook_button.text = "[B] Grimoire / Upgrade Spells (%d SP)" % player.spell_points
	_rebuild_spells(player, active_spell_idx)
	_rebuild_relics(player)
	_rebuild_inventory(player)
	if spellbook_modal.visible:
		_rebuild_spellbook(player)


func _rebuild_spells(player: Actor, active_spell_idx: int) -> void:
	for child in spell_list.get_children():
		child.queue_free()

	var bonus_dmg := player.total_spell_damage_bonus()
	for i in player.spells.size():
		var spell := player.spells[i]
		var spell_bonus := bonus_dmg + player.element_mastery_bonus(spell)
		var key_label: String = SPELL_KEYS[i] if i < SPELL_KEYS.size() else str(i + 1)
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var active_prefix := ">> " if i == active_spell_idx else ""
		var stat_suffix := ""
		if spell.pattern == SpellData.Pattern.SUMMON:
			stat_suffix = "SUMMON"
		elif spell.pattern == SpellData.Pattern.DASH:
			stat_suffix = "DODGE"
		else:
			stat_suffix = "%d DMG" % (spell.effective_damage() + spell_bonus)
		btn.text = "%s%s  •  %s" % [active_prefix, spell.describe_button(key_label), stat_suffix]
		if not spell.is_ready():
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


func _rebuild_relics(player: Actor) -> void:
	for child in relic_list.get_children():
		child.queue_free()

	if player.relics.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "(None yet — look for ? on the floor)"
		none_lbl.modulate = Color(0.65, 0.65, 0.65)
		relic_list.add_child(none_lbl)
		return

	for relic in player.relics:
		var badge := Button.new()
		badge.focus_mode = Control.FOCUS_NONE
		badge.text = "? %s" % relic.display_name
		badge.modulate = relic.color.lerp(Color.WHITE, 0.4)
		var rel := relic
		badge.mouse_entered.connect(func() -> void:
			show_item_popup(rel, true)
		)
		badge.mouse_exited.connect(hide_popup)
		relic_list.add_child(badge)


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


func _rebuild_branch_choice(player: Actor) -> void:
	var spell := _branch_choice_spell
	spellbook_title.text = "CHOOSE A PATH — %s Lv.%d → Lv.%d  (%d SP, cost %d)" % [
		spell.display_name, spell.level, spell.level + 1, player.spell_points, spell.upgrade_cost
	]
	var offers := SpellBranches.offers_for(spell)
	var affordable := player.spell_points >= spell.upgrade_cost
	for entry in offers:
		var row := PanelContainer.new()
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		row.add_child(hbox)

		var info_box := VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info_box)
		var title := Label.new()
		title.text = "%s%s" % [entry["name"], "  (Capstone)" if int(entry["tier"]) >= 2 else ""]
		title.modulate = spell.color.lerp(Color.WHITE, 0.35)
		info_box.add_child(title)
		var desc := Label.new()
		desc.text = str(entry["desc"])
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.modulate = Color(0.88, 0.88, 0.88)
		info_box.add_child(desc)

		var pick_btn := Button.new()
		pick_btn.focus_mode = Control.FOCUS_NONE
		pick_btn.custom_minimum_size = Vector2(140, 38)
		pick_btn.text = "Choose (%d SP)" % spell.upgrade_cost
		pick_btn.disabled = not affordable
		var branch_id := str(entry["id"])
		pick_btn.pressed.connect(func() -> void:
			_branch_choice_spell = null
			spell_upgrade_requested.emit(spell, branch_id)
		)
		hbox.add_child(pick_btn)
		catalog_list.add_child(row)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	if offers.is_empty():
		var plain_btn := Button.new()
		plain_btn.focus_mode = Control.FOCUS_NONE
		plain_btn.text = "Level up (%d SP)" % spell.upgrade_cost
		plain_btn.disabled = not affordable
		plain_btn.pressed.connect(func() -> void:
			_branch_choice_spell = null
			spell_upgrade_requested.emit(spell, "")
		)
		footer.add_child(plain_btn)
	var back_btn := Button.new()
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.text = "← Back to Grimoire"
	back_btn.pressed.connect(func() -> void:
		_branch_choice_spell = null
		_rebuild_spellbook(player)
	)
	footer.add_child(back_btn)
	catalog_list.add_child(footer)


func _rebuild_spellbook(player: Actor) -> void:
	spellbook_title.text = "RIFT GRIMOIRE — Spell Points (SP): %d" % player.spell_points
	for child in catalog_list.get_children():
		child.queue_free()
	if _branch_choice_spell != null:
		if player.spells.has(_branch_choice_spell) and _branch_choice_spell.can_upgrade():
			_rebuild_branch_choice(player)
			return
		_branch_choice_spell = null

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
				_branch_choice_spell = sp
				_rebuild_spellbook(player)
			)
		else:
			action_btn.text = "MAX LEVEL"
			action_btn.disabled = true

		hbox.add_child(action_btn)
		catalog_list.add_child(row)


func _add_debug_header(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	debug_list.add_child(lbl)


func _rebuild_debug_menu() -> void:
	for child in debug_list.get_children():
		child.queue_free()

	# 1. Quick Cheats & Portals
	_add_debug_header("■ QUICK ACTIONS & PORTALS", Color(0.55, 0.9, 1.0))
	var quick_flow := HFlowContainer.new()
	quick_flow.add_theme_constant_override("h_separation", 8)
	quick_flow.add_theme_constant_override("v_separation", 6)
	debug_list.add_child(quick_flow)

	var quick_actions: Array[Dictionary] = [
		{"id": "heal_full", "label": "Heal & Refill Spells", "color": Color(0.5, 1.0, 0.65)},
		{"id": "add_sp", "label": "+5 Spell Points (SP)", "color": Color(0.95, 0.85, 0.4)},
		{"id": "kill_all", "label": "Kill All Hostiles (Clear)", "color": Color(1.0, 0.55, 0.45)},
		{"id": "spawn_devil_portal", "label": "Spawn Devil Portal (ψ)", "color": Color(1.0, 0.35, 0.42)},
		{"id": "spawn_angel_portal", "label": "Spawn Angel Portal (†)", "color": Color(1.0, 0.95, 0.55)},
		{"id": "spawn_treasure_portal", "label": "Spawn Treasure Portal (⚜)", "color": Color(1.0, 0.85, 0.25)},
		{"id": "enter_devil_room", "label": "Teleport → Devil Room", "color": Color(0.95, 0.3, 0.4)},
		{"id": "enter_angel_room", "label": "Teleport → Angel Room", "color": Color(0.65, 0.9, 1.0)},
		{"id": "enter_treasure_room", "label": "Teleport → Treasure Room", "color": Color(1.0, 0.85, 0.25)},
		{"id": "exit_sanctuary", "label": "Return from Sanctuary (O)", "color": Color(0.75, 0.85, 1.0)},
	]
	for entry in quick_actions:
		var act_id: String = entry["id"]
		var act_label: String = entry["label"]
		var act_col: Color = entry["color"]
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = act_label
		btn.modulate = act_col
		btn.pressed.connect(func() -> void:
			debug_action_requested.emit(act_id)
		)
		quick_flow.add_child(btn)

	# 2. Monsters & Allies
	_add_debug_header("■ SPAWN MONSTERS & ALLIES (Near Player)", Color(1.0, 0.55, 0.55))
	for m_info in _debug_monsters:
		var m_scene: PackedScene = m_info["scene"]
		var m_name: String = m_info["name"]
		var m_glyph: String = m_info["glyph"]
		var m_color: Color = m_info["color"]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.text = "%s  %s" % [m_glyph, m_name]
		name_lbl.modulate = m_color.lerp(Color.WHITE, 0.35)
		row.add_child(name_lbl)

		var foe_btn := Button.new()
		foe_btn.focus_mode = Control.FOCUS_NONE
		foe_btn.text = "Spawn Enemy"
		foe_btn.modulate = Color(1.0, 0.55, 0.55)
		foe_btn.pressed.connect(func() -> void:
			debug_spawn_monster_requested.emit(m_scene, false)
		)
		row.add_child(foe_btn)

		var ally_btn := Button.new()
		ally_btn.focus_mode = Control.FOCUS_NONE
		ally_btn.text = "Spawn Ally"
		ally_btn.modulate = Color(0.45, 0.95, 1.0)
		ally_btn.pressed.connect(func() -> void:
			debug_spawn_monster_requested.emit(m_scene, true)
		)
		row.add_child(ally_btn)
		debug_list.add_child(row)

	# 3. Relics
	_add_debug_header("■ SPAWN / GRANT RELICS (?)", Color(0.95, 0.82, 0.38))
	for relic in _debug_relics:
		var rel: ItemData = relic
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		name_lbl.text = "? %s" % rel.display_name
		name_lbl.modulate = rel.color.lerp(Color.WHITE, 0.35)
		name_lbl.mouse_entered.connect(func() -> void:
			show_item_popup(rel, true)
		)
		name_lbl.mouse_exited.connect(hide_popup)
		row.add_child(name_lbl)

		var floor_btn := Button.new()
		floor_btn.focus_mode = Control.FOCUS_NONE
		floor_btn.text = "Spawn Floor"
		floor_btn.pressed.connect(func() -> void:
			debug_spawn_item_requested.emit(rel, false)
		)
		row.add_child(floor_btn)

		var grant_btn := Button.new()
		grant_btn.focus_mode = Control.FOCUS_NONE
		grant_btn.text = "+Give Relic"
		grant_btn.modulate = Color(0.95, 0.85, 0.45)
		grant_btn.pressed.connect(func() -> void:
			debug_spawn_item_requested.emit(rel, true)
		)
		row.add_child(grant_btn)
		debug_list.add_child(row)

	# 4. Items & Equipment
	_add_debug_header("■ SPAWN / GIVE ITEMS", Color(0.65, 0.95, 0.65))
	for item in _debug_items:
		var it: ItemData = item
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		name_lbl.text = "%s %s (%s)" % [it.glyph, it.display_name, it.type_name()]
		name_lbl.modulate = it.color.lerp(Color.WHITE, 0.35)
		name_lbl.mouse_entered.connect(func() -> void:
			show_item_popup(it, true)
		)
		name_lbl.mouse_exited.connect(hide_popup)
		row.add_child(name_lbl)

		var floor_btn := Button.new()
		floor_btn.focus_mode = Control.FOCUS_NONE
		floor_btn.text = "Spawn Floor"
		floor_btn.pressed.connect(func() -> void:
			debug_spawn_item_requested.emit(it, false)
		)
		row.add_child(floor_btn)

		var give_btn := Button.new()
		give_btn.focus_mode = Control.FOCUS_NONE
		give_btn.text = "+Give / Equip"
		give_btn.modulate = Color(0.6, 1.0, 0.65)
		give_btn.pressed.connect(func() -> void:
			debug_spawn_item_requested.emit(it, true)
		)
		row.add_child(give_btn)
		debug_list.add_child(row)

	# 5. Spells
	_add_debug_header("■ SPAWN SPELL PEDESTALS / LEARN SPELLS", Color(0.75, 0.65, 1.0))
	for spell in _debug_spells:
		var sp: SpellData = spell
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		name_lbl.text = "✦ %s (%s • %s)" % [sp.display_name, sp.element_name(), sp.pattern_name()]
		name_lbl.modulate = sp.color.lerp(Color.WHITE, 0.35)
		name_lbl.mouse_entered.connect(func() -> void:
			show_spell_popup(sp, true)
		)
		name_lbl.mouse_exited.connect(hide_popup)
		row.add_child(name_lbl)

		var ped_btn := Button.new()
		ped_btn.focus_mode = Control.FOCUS_NONE
		ped_btn.text = "Spawn Pedestal"
		ped_btn.pressed.connect(func() -> void:
			debug_spawn_spell_requested.emit(sp, false)
		)
		row.add_child(ped_btn)

		var learn_btn := Button.new()
		learn_btn.focus_mode = Control.FOCUS_NONE
		learn_btn.text = "+Learn / Upgrade"
		learn_btn.modulate = Color(0.8, 0.7, 1.0)
		learn_btn.pressed.connect(func() -> void:
			debug_spawn_spell_requested.emit(sp, true)
		)
		row.add_child(learn_btn)
		debug_list.add_child(row)
