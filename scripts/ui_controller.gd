class_name UIController
extends CanvasLayer

## Интерфейс игры:
## 1. Первичная страница настроек (7 языков в 1 строку, звук, опции)
## 2. Экран "Как играть" с легендой и правилами
## 3. Выбор из 20 уровней
## 4. Верхний HUD (START WAVE, скорость 1x-3x, уровни, помощь, настройки) + Нижняя панель башен
## 5. Окно Победы / Поражения

signal play_requested()
signal start_wave_requested()
signal speed_cycle_requested()
signal zoom_in_requested()
signal zoom_out_requested()
signal reset_camera_requested()
signal level_selected(level_id: int)
signal next_level_requested()
signal retry_level_requested()
signal new_game_requested()
signal tower_selected(tower_id: String)
signal upgrade_inspected_requested()
signal sell_inspected_requested()
signal close_inspector_requested()
signal confirm_build_requested()
signal cancel_build_requested()
signal overlay_visibility_changed(is_open: bool)

var _has_started: bool = false
var _campaign_levels: Array = []
var _current_available_towers: Array = []
var _selected_tower_id: String = ""
var _current_gold: int = 0
var _wave_active: bool = false
var _current_speed: int = 1
var _last_result_is_victory: bool = true

# HUD
var _hud_bar: PanelContainer
var _btn_level_pill: Button
var _pill_diff: PanelContainer
var _lbl_diff: Label
var _pill_credits: PanelContainer
var _lbl_credits: Label
var _pill_cores: PanelContainer
var _lbl_cores: Label
var _pill_wave: PanelContainer
var _lbl_wave: Label
var _hud_btn_zoom_out: Button
var _hud_btn_zoom_in: Button
var _hud_btn_reset_cam: Button
var _status_toast: PanelContainer
var _hud_status_label: Label
var _hud_btn_wave: Button
var _hud_btn_speed: Button
var _hud_btn_guide: Button
var _hud_btn_settings: Button

# Bottom Tower Shop
var _shop_bar: PanelContainer
var _shop_title_label: Label
var _shop_cards_box: HBoxContainer
var _shop_scroll: ScrollContainer

# Tower Inspector Bar (for 5-level upgrades)
var _inspector_panel: PanelContainer
var _insp_flow: HFlowContainer
var _insp_info_box: HBoxContainer
var _insp_icon: TextureRect
var _insp_title: Label
var _insp_stats: Label
var _insp_btn_upgrade: Button
var _insp_btn_sell: Button
var _insp_btn_close: Button
var _insp_info: Dictionary = {}

# Build Preview Bar (2-click confirmation)
var _preview_panel: PanelContainer
var _prev_flow: HFlowContainer
var _prev_info_box: HBoxContainer
var _prev_icon: TextureRect
var _prev_title: Label
var _prev_hint: Label
var _prev_btn_build: Button
var _prev_btn_cancel: Button

# Overlays
var _backdrop: ColorRect
var _settings_panel: PanelContainer
var _guide_panel: PanelContainer
var _levels_panel: PanelContainer
var _result_panel: PanelContainer
var _confirm_reset_panel: PanelContainer

# Settings controls
var _lbl_game_title: Label
var _lbl_subtitle: Label
var _lbl_settings_title: Label
var _lbl_lang: Label
var _lang_buttons: Dictionary = {}
var _lbl_diff_title: Label
var _lbl_diff_desc: Label
var _diff_buttons_settings: Dictionary = {}
var _diff_buttons_levels: Dictionary = {}
var _lbl_levels_diff_desc: Label
var _lbl_master: Label
var _lbl_sfx: Label
var _lbl_music: Label
var _slider_labels: Array[Label] = []
var _val_master: Label
var _val_sfx: Label
var _val_music: Label
var _slider_master: HSlider
var _slider_sfx: HSlider
var _slider_music: HSlider
var _chk_mute: CheckBox
var _chk_path: CheckBox
var _chk_grid: CheckBox
var _lbl_speed: Label
var _speed_buttons: Array[Button] = []
var _lbl_speed_hint: Label
var _btn_play: Button
var _btn_open_guide: Button
var _btn_open_levels: Button
var _btn_new_game: Button

# Guide controls
var _lbl_guide_title: Label
var _guide_lang_buttons: Dictionary = {}
var _lbl_welcome_title: Label
var _lbl_welcome_body: Label
var _lbl_goal_t: Label
var _lbl_goal_b: Label
var _lbl_maze_t: Label
var _lbl_maze_b: Label
var _lbl_tiles_t: Label
var _tile_labels: Dictionary = {}
var _lbl_ctrl_t: Label
var _lbl_ctrl_b: Label
var _btn_guide_back: Button
var _btn_guide_play: Button

# Levels controls
var _lbl_levels_title: Label
var _levels_grid: GridContainer
var _btn_levels_back: Button

# Result modal controls
var _lbl_result_title: Label
var _lbl_result_body: Label
var _btn_result_retry: Button
var _btn_result_next: Button

# New Game confirmation controls
var _lbl_reset_title: Label
var _lbl_reset_body: Label
var _btn_reset_confirm: Button
var _btn_reset_cancel: Button


func _ready() -> void:
	_load_campaign_index()
	_current_speed = SettingsManager.default_speed
	_build_hud()
	_build_tower_shop()
	_build_inspector()
	_build_preview_bar()
	_build_overlays()
	SettingsManager.language_changed.connect(_on_language_changed)
	SettingsManager.difficulty_changed.connect(func(_d: String): _sync_difficulty_ui())
	get_viewport().size_changed.connect(_on_viewport_resized)
	_hud_bar.resized.connect(func(): call_deferred("_update_dynamic_bars"))
	_shop_bar.resized.connect(func(): call_deferred("_update_dynamic_bars"))
	call_deferred("_on_viewport_resized")
	_apply_translations()
	if not SettingsManager.intro_seen:
		show_guide()
	else:
		show_settings()


func _load_campaign_index() -> void:
	var path := "res://data/levels/campaign.json"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_campaign_levels = parsed.get("levels", [])


func is_any_overlay_open() -> bool:
	return _backdrop.visible


func show_settings() -> void:
	_backdrop.visible = true
	_settings_panel.visible = true
	_guide_panel.visible = false
	_levels_panel.visible = false
	_result_panel.visible = false
	_confirm_reset_panel.visible = false
	_sync_settings_controls()
	_apply_translations()
	overlay_visibility_changed.emit(true)


func show_guide() -> void:
	_backdrop.visible = true
	_settings_panel.visible = false
	_guide_panel.visible = true
	_levels_panel.visible = false
	_result_panel.visible = false
	_confirm_reset_panel.visible = false
	_apply_translations()
	overlay_visibility_changed.emit(true)


func show_levels() -> void:
	_backdrop.visible = true
	_settings_panel.visible = false
	_guide_panel.visible = false
	_levels_panel.visible = true
	_result_panel.visible = false
	_confirm_reset_panel.visible = false
	_rebuild_level_buttons()
	_apply_translations()
	overlay_visibility_changed.emit(true)


func show_result(is_victory: bool) -> void:
	_last_result_is_victory = is_victory
	_backdrop.visible = true
	_settings_panel.visible = false
	_guide_panel.visible = false
	_levels_panel.visible = false
	_result_panel.visible = true
	_confirm_reset_panel.visible = false
	_btn_result_next.visible = is_victory
	_apply_translations()
	overlay_visibility_changed.emit(true)


func close_overlays() -> void:
	_has_started = true
	SettingsManager.mark_intro_seen()
	_backdrop.visible = false
	_settings_panel.visible = false
	_guide_panel.visible = false
	_levels_panel.visible = false
	_result_panel.visible = false
	_confirm_reset_panel.visible = false
	overlay_visibility_changed.emit(false)
	play_requested.emit()


func show_confirm_new_game() -> void:
	_backdrop.visible = true
	_settings_panel.visible = false
	_guide_panel.visible = false
	_levels_panel.visible = false
	_result_panel.visible = false
	_confirm_reset_panel.visible = true
	_apply_translations()
	overlay_visibility_changed.emit(true)


func set_wave_button_active(active: bool) -> void:
	_wave_active = active
	if _hud_btn_wave:
		_hud_btn_wave.disabled = active
		_hud_btn_wave.text = SettingsManager.tr_key("btn_wave_active") if active else SettingsManager.tr_key("btn_start_wave")
		_style_button(_hud_btn_wave, Color("#F97316") if active else Color("#10B981"), not active, active)


func set_speed_display(spd: int) -> void:
	_current_speed = spd
	if _hud_btn_speed:
		var unlocked: bool = SettingsManager.is_fast_speed_unlocked()
		_hud_btn_speed.text = ("%dx" % spd) if unlocked else "1x"
		_style_button(_hud_btn_speed, Color("#F59E0B") if unlocked else Color("#64748B"), false, not unlocked)


func set_available_towers(towers: Array, selected_id: String, gold: int) -> void:
	_current_available_towers = towers
	_selected_tower_id = selected_id
	_current_gold = gold
	_rebuild_tower_shop_cards()


func update_shop_state(selected_id: String, gold: int) -> void:
	_selected_tower_id = selected_id
	_current_gold = gold
	_rebuild_tower_shop_cards()


func update_hud(level_name: String, gold: int, cores: int, cur_wave: int, total_waves: int, msg_key: String) -> void:
	_current_gold = gold
	if not _btn_level_pill:
		return
	_btn_level_pill.text = level_name.to_upper()
	var d_mods: Dictionary = SettingsManager.get_difficulty_mods()
	var d_id: String = str(d_mods.get("id", "easy"))
	var d_col := Color(str(d_mods.get("color", "#10B981")))
	var max_cores: int = int(d_mods.get("cores", 10))
	_pill_diff.add_theme_stylebox_override("panel", _make_pill_style(Color(d_col.r * 0.22, d_col.g * 0.22, d_col.b * 0.22, 1.0), d_col))
	_lbl_diff.text = SettingsManager.tr_key("diff_" + d_id).to_upper()
	_lbl_diff.add_theme_color_override("font_color", d_col.lightened(0.35))
	_lbl_credits.text = "%s: %d" % [SettingsManager.tr_key("hud_credits").to_upper(), gold]
	_lbl_cores.text = "%s: %d/%d" % [SettingsManager.tr_key("hud_cores").to_upper(), cores, max_cores]
	_lbl_wave.text = "%s: %d/%d" % [SettingsManager.tr_key("hud_waves").to_upper(), cur_wave, total_waves]

	# Красная тревога на бейдже Ядер, если осталось <= 3
	var core_accent := Color("#EF4444") if cores <= 3 else Color("#38BDF8")
	var core_bg := Color("#2D0A12") if cores <= 3 else Color("#082032")
	_pill_cores.add_theme_stylebox_override("panel", _make_pill_style(core_bg, core_accent))
	_lbl_cores.add_theme_color_override("font_color", Color("#FCA5A5") if cores <= 3 else Color("#7DD3FC"))

	_hud_status_label.text = SettingsManager.tr_key(msg_key)
	_rebuild_tower_shop_cards()


func _make_pill_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _make_hud_pill(parent: Control, bg: Color, border: Color, text_col: Color) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _make_pill_style(bg, border))
	parent.add_child(p)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", text_col)
	p.add_child(l)
	return [p, l]


func _on_language_changed(_code: String) -> void:
	_apply_translations()
	_rebuild_tower_shop_cards()


func _make_panel_style(bg: Color, border: Color, radius: int = 10, border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _style_button(btn: Button, accent := Color("#00E5FF"), filled := false, dimmed := false) -> void:
	var border_col: Color = accent.darkened(0.5) if dimmed else accent
	var normal_bg: Color = accent.darkened(0.62) if filled else Color("#111827")
	if dimmed:
		normal_bg = Color("#0D111A")
	var hover_bg: Color = accent.darkened(0.45) if filled else Color("#1F2937")
	var pressed_bg: Color = accent.darkened(0.30)

	var sb_n := _make_panel_style(normal_bg, border_col, 6, 2 if filled else 1)
	sb_n.content_margin_left = 10
	sb_n.content_margin_right = 10
	sb_n.content_margin_top = 5
	sb_n.content_margin_bottom = 5

	var sb_h: StyleBoxFlat = sb_n.duplicate()
	sb_h.bg_color = hover_bg
	sb_h.set_border_width_all(2)

	var sb_p: StyleBoxFlat = sb_n.duplicate()
	sb_p.bg_color = pressed_bg

	btn.add_theme_stylebox_override("normal", sb_n)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_p)
	btn.add_theme_stylebox_override("focus", sb_h)
	btn.add_theme_stylebox_override("disabled", sb_n)
	btn.add_theme_color_override("font_color", Color("#64748B") if dimmed else Color("#F8FAFC"))
	btn.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _build_hud() -> void:
	_hud_bar = PanelContainer.new()
	_hud_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_bar.offset_bottom = 0.0
	var bar_style := _make_panel_style(Color("#0D1321"), Color("#1E293B"), 0, 1)
	bar_style.content_margin_top = 6
	bar_style.content_margin_bottom = 6
	bar_style.content_margin_left = 8
	bar_style.content_margin_right = 8
	_hud_bar.add_theme_stylebox_override("panel", bar_style)
	add_child(_hud_bar)

	var hbox := HFlowContainer.new()
	hbox.alignment = FlowContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("h_separation", 6)
	hbox.add_theme_constant_override("v_separation", 6)
	_hud_bar.add_child(hbox)

	_btn_level_pill = Button.new()
	_btn_level_pill.custom_minimum_size = Vector2(130, 32)
	_btn_level_pill.clip_text = true
	_btn_level_pill.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_btn_level_pill.add_theme_font_size_override("font_size", 13)
	_btn_level_pill.add_theme_color_override("font_color", Color("#E0F7FA"))
	_btn_level_pill.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	var lvl_n := _make_pill_style(Color("#071E2E"), Color("#00E5FF"))
	var lvl_h := _make_pill_style(Color("#0C3048"), Color("#38BDF8"))
	_btn_level_pill.add_theme_stylebox_override("normal", lvl_n)
	_btn_level_pill.add_theme_stylebox_override("hover", lvl_h)
	_btn_level_pill.add_theme_stylebox_override("pressed", lvl_h)
	_btn_level_pill.pressed.connect(show_levels)
	hbox.add_child(_btn_level_pill)

	var p_dif: Array = _make_hud_pill(hbox, Color("#07221B"), Color("#10B981"), Color("#6EE7B7"))
	_pill_diff = p_dif[0]
	_lbl_diff = p_dif[1]

	var p_cr: Array = _make_hud_pill(hbox, Color("#261D06"), Color("#FACC15"), Color("#FEF08A"))
	_pill_credits = p_cr[0]
	_lbl_credits = p_cr[1]

	var p_co: Array = _make_hud_pill(hbox, Color("#082032"), Color("#38BDF8"), Color("#7DD3FC"))
	_pill_cores = p_co[0]
	_lbl_cores = p_co[1]

	var p_wv: Array = _make_hud_pill(hbox, Color("#291306"), Color("#F97316"), Color("#FDBA74"))
	_pill_wave = p_wv[0]
	_lbl_wave = p_wv[1]

	_status_toast = PanelContainer.new()
	_status_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status_toast.grow_vertical = Control.GROW_DIRECTION_END
	_status_toast.offset_left = -260.0
	_status_toast.offset_right = 260.0
	_status_toast.offset_top = 52.0
	_status_toast.offset_bottom = 52.0
	_status_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var toast_sb := _make_panel_style(Color(0.05, 0.08, 0.14, 0.86), Color("#1E293B"), 10, 1)
	toast_sb.content_margin_top = 4
	toast_sb.content_margin_bottom = 4
	toast_sb.content_margin_left = 10
	toast_sb.content_margin_right = 10
	_status_toast.add_theme_stylebox_override("panel", toast_sb)
	add_child(_status_toast)

	_hud_status_label = Label.new()
	_hud_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_status_label.add_theme_color_override("font_color", Color("#CBD5E1"))
	_hud_status_label.add_theme_font_size_override("font_size", 12)
	_status_toast.add_child(_hud_status_label)

	_hud_btn_wave = Button.new()
	_hud_btn_wave.custom_minimum_size = Vector2(126, 32)
	_style_button(_hud_btn_wave, Color("#10B981"), true)
	_hud_btn_wave.pressed.connect(func(): start_wave_requested.emit())
	hbox.add_child(_hud_btn_wave)

	_hud_btn_speed = Button.new()
	_hud_btn_speed.text = "%dx" % _current_speed
	_hud_btn_speed.custom_minimum_size = Vector2(44, 32)
	_style_button(_hud_btn_speed, Color("#F59E0B"))
	_hud_btn_speed.pressed.connect(func(): speed_cycle_requested.emit())
	hbox.add_child(_hud_btn_speed)

	_hud_btn_zoom_out = Button.new()
	_hud_btn_zoom_out.text = "-"
	_hud_btn_zoom_out.custom_minimum_size = Vector2(30, 32)
	_style_button(_hud_btn_zoom_out, Color("#00E5FF"))
	_hud_btn_zoom_out.pressed.connect(func(): zoom_out_requested.emit())
	hbox.add_child(_hud_btn_zoom_out)

	_hud_btn_zoom_in = Button.new()
	_hud_btn_zoom_in.text = "+"
	_hud_btn_zoom_in.custom_minimum_size = Vector2(30, 32)
	_style_button(_hud_btn_zoom_in, Color("#00E5FF"))
	_hud_btn_zoom_in.pressed.connect(func(): zoom_in_requested.emit())
	hbox.add_child(_hud_btn_zoom_in)

	_hud_btn_reset_cam = Button.new()
	_hud_btn_reset_cam.text = "1:1"
	_hud_btn_reset_cam.custom_minimum_size = Vector2(36, 32)
	_style_button(_hud_btn_reset_cam, Color("#00E5FF"))
	_hud_btn_reset_cam.pressed.connect(func(): reset_camera_requested.emit())
	hbox.add_child(_hud_btn_reset_cam)

	_hud_btn_guide = Button.new()
	_style_button(_hud_btn_guide, Color("#10B981"))
	_hud_btn_guide.pressed.connect(show_guide)
	hbox.add_child(_hud_btn_guide)

	_hud_btn_settings = Button.new()
	_style_button(_hud_btn_settings, Color("#00E5FF"))
	_hud_btn_settings.pressed.connect(show_settings)
	hbox.add_child(_hud_btn_settings)


func _build_tower_shop() -> void:
	_shop_bar = PanelContainer.new()
	_shop_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_shop_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_shop_bar.offset_top = -124.0
	_shop_bar.offset_bottom = 0.0
	var shop_style := _make_panel_style(Color("#0D1321"), Color("#1E293B"), 0, 1)
	shop_style.content_margin_top = 6
	shop_style.content_margin_bottom = 8
	shop_style.content_margin_left = 10
	shop_style.content_margin_right = 10
	_shop_bar.add_theme_stylebox_override("panel", shop_style)
	add_child(_shop_bar)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	_shop_bar.add_child(vbox)

	_shop_title_label = Label.new()
	_shop_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_title_label.add_theme_font_size_override("font_size", 12)
	_shop_title_label.add_theme_color_override("font_color", Color("#94A3B8"))
	vbox.add_child(_shop_title_label)

	_shop_scroll = ScrollContainer.new()
	_shop_scroll.custom_minimum_size = Vector2(0, 96)
	_shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_shop_scroll)

	_shop_cards_box = HBoxContainer.new()
	_shop_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_cards_box.add_theme_constant_override("separation", 8)
	_shop_scroll.add_child(_shop_cards_box)


func _rebuild_tower_shop_cards() -> void:
	if not _shop_cards_box:
		return
	for child in _shop_cards_box.get_children():
		child.queue_free()

	var dmg_l: String = SettingsManager.tr_key("stat_dmg")
	var rng_l: String = SettingsManager.tr_key("stat_rng")
	var rof_l: String = SettingsManager.tr_key("stat_rof")
	var cost_l: String = SettingsManager.tr_key("stat_cost")

	for i in _current_available_towers.size():
		var cfg: Dictionary = _current_available_towers[i]
		var tid: String = str(cfg.get("id", "pulse"))
		var tname: String = str(cfg.get("name", tid))
		var cost: int = int(cfg.get("cost", 25))
		var dmg: int = int(cfg.get("damage", 10))
		var rng: int = int(cfg.get("range", 180))
		var rof: float = float(cfg.get("fire_rate", 1.0))
		var col := Color(str(cfg.get("color", "#00E5FF")))
		var role: String = SettingsManager.tr_key("role_" + tid)

		var can_afford: bool = _current_gold >= cost
		var is_sel: bool = (tid == _selected_tower_id)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(262, 92)
		btn.expand_icon = true
		btn.clip_text = true
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var icon_path: String = "res://assets/sprites/towers/%s.png" % tid
		if ResourceLoader.exists(icon_path):
			btn.icon = load(icon_path)
			btn.add_theme_constant_override("icon_max_width", 52)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		btn.text = "[%d] %s  —  %d %s\n%s: %d | %s: %d | %s: %.1f/s\n%s" % [
			i + 1, tname, cost, cost_l,
			dmg_l, dmg, rng_l, rng, rof_l, rof,
			role
		]
		_style_button(btn, col, is_sel, not can_afford)
		btn.pressed.connect(func(): tower_selected.emit(tid))
		_shop_cards_box.add_child(btn)


func _build_inspector() -> void:
	_inspector_panel = PanelContainer.new()
	_inspector_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_inspector_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_inspector_panel.offset_left = -360.0
	_inspector_panel.offset_right = 360.0
	_inspector_panel.offset_top = -134.0
	_inspector_panel.offset_bottom = -134.0
	_inspector_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#0F172A"), Color("#FACC15"), 10, 2))
	_inspector_panel.visible = false
	add_child(_inspector_panel)

	_insp_flow = HFlowContainer.new()
	_insp_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_insp_flow.add_theme_constant_override("h_separation", 10)
	_insp_flow.add_theme_constant_override("v_separation", 8)
	_inspector_panel.add_child(_insp_flow)

	_insp_info_box = HBoxContainer.new()
	_insp_info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insp_info_box.add_theme_constant_override("separation", 10)
	_insp_flow.add_child(_insp_info_box)

	_insp_icon = TextureRect.new()
	_insp_icon.custom_minimum_size = Vector2(44, 44)
	_insp_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_insp_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_insp_info_box.add_child(_insp_icon)

	var info_v := VBoxContainer.new()
	info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_v.add_theme_constant_override("separation", 2)
	_insp_info_box.add_child(info_v)

	_insp_title = Label.new()
	_insp_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insp_title.add_theme_font_size_override("font_size", 14)
	_insp_title.add_theme_color_override("font_color", Color("#FACC15"))
	info_v.add_child(_insp_title)

	_insp_stats = Label.new()
	_insp_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insp_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insp_stats.add_theme_font_size_override("font_size", 12)
	_insp_stats.add_theme_color_override("font_color", Color("#E2E8F0"))
	info_v.add_child(_insp_stats)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	_insp_flow.add_child(btns)

	_insp_btn_upgrade = Button.new()
	_insp_btn_upgrade.custom_minimum_size = Vector2(138, 42)
	_insp_btn_upgrade.clip_text = true
	_insp_btn_upgrade.pressed.connect(func(): upgrade_inspected_requested.emit())
	btns.add_child(_insp_btn_upgrade)

	_insp_btn_sell = Button.new()
	_insp_btn_sell.custom_minimum_size = Vector2(110, 42)
	_insp_btn_sell.clip_text = true
	_style_button(_insp_btn_sell, Color("#EF4444"), true)
	_insp_btn_sell.pressed.connect(func(): sell_inspected_requested.emit())
	btns.add_child(_insp_btn_sell)

	_insp_btn_close = Button.new()
	_insp_btn_close.text = "X"
	_insp_btn_close.custom_minimum_size = Vector2(34, 42)
	_style_button(_insp_btn_close, Color("#94A3B8"))
	_insp_btn_close.pressed.connect(func(): close_inspector_requested.emit())
	btns.add_child(_insp_btn_close)


func show_inspector(info: Dictionary, gold: int) -> void:
	_insp_info = info
	if not _inspector_panel:
		return
	_inspector_panel.visible = true
	var tid: String = str(info.get("id", "pulse"))
	var ip: String = "res://assets/sprites/towers/%s.png" % tid
	if ResourceLoader.exists(ip):
		_insp_icon.texture = load(ip)

	var lvl: int = int(info.get("level", 1))
	var max_lvl: int = int(info.get("max_level", 5))
	var stars: String = ""
	for k in max_lvl:
		stars += "*" if k < lvl else "-"
	var lv_word: String = SettingsManager.tr_key("lbl_lv")
	_insp_title.text = "%s  |  %s %d/%d [%s]" % [str(info.get("name", tid)), lv_word, lvl, max_lvl, stars]

	var dmg_l: String = SettingsManager.tr_key("stat_dmg")
	var rng_l: String = SettingsManager.tr_key("stat_rng")
	var rof_l: String = SettingsManager.tr_key("stat_rof")
	var cost_l: String = SettingsManager.tr_key("stat_cost")

	if lvl < max_lvl:
		_insp_stats.text = "%s: %d -> %d  |  %s: %d -> %d  |  %s: %.1f -> %.1f/s" % [
			dmg_l, int(info["cur_dmg"]), int(info["next_dmg"]),
			rng_l, int(info["cur_rng"]), int(info["next_rng"]),
			rof_l, float(info["cur_rof"]), float(info["next_rof"])
		]
		var up_cost: int = int(info["upgrade_cost"])
		var can_aff: bool = gold >= up_cost
		_insp_btn_upgrade.disabled = not can_aff
		_insp_btn_upgrade.text = "%s [U]
%d %s" % [SettingsManager.tr_key("btn_upgrade"), up_cost, cost_l]
		_style_button(_insp_btn_upgrade, Color("#10B981"), can_aff, not can_aff)
	else:
		_insp_stats.text = "%s: %d  |  %s: %d  |  %s: %.1f/s  |  %s" % [
			dmg_l, int(info["cur_dmg"]), rng_l, int(info["cur_rng"]),
			rof_l, float(info["cur_rof"]), SettingsManager.tr_key("lbl_max_level")
		]
		_insp_btn_upgrade.disabled = true
		_insp_btn_upgrade.text = "MAX"
		_style_button(_insp_btn_upgrade, Color("#FACC15"), false, true)

	_insp_btn_sell.text = "%s [X]
+%d %s" % [SettingsManager.tr_key("btn_sell"), int(info["sell_refund"]), cost_l]


func hide_inspector() -> void:
	_insp_info.clear()
	if _inspector_panel:
		_inspector_panel.visible = false


func _build_preview_bar() -> void:
	_preview_panel = PanelContainer.new()
	_preview_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_preview_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_preview_panel.offset_left = -330.0
	_preview_panel.offset_right = 330.0
	_preview_panel.offset_top = -134.0
	_preview_panel.offset_bottom = -134.0
	_preview_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#0F172A"), Color("#00E5FF"), 10, 2))
	_preview_panel.visible = false
	add_child(_preview_panel)

	_prev_flow = HFlowContainer.new()
	_prev_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_prev_flow.add_theme_constant_override("h_separation", 10)
	_prev_flow.add_theme_constant_override("v_separation", 8)
	_preview_panel.add_child(_prev_flow)

	_prev_info_box = HBoxContainer.new()
	_prev_info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prev_info_box.add_theme_constant_override("separation", 10)
	_prev_flow.add_child(_prev_info_box)

	_prev_icon = TextureRect.new()
	_prev_icon.custom_minimum_size = Vector2(44, 44)
	_prev_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_prev_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_prev_info_box.add_child(_prev_icon)

	var info_v := VBoxContainer.new()
	info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_v.add_theme_constant_override("separation", 2)
	_prev_info_box.add_child(info_v)

	_prev_title = Label.new()
	_prev_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prev_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prev_title.add_theme_font_size_override("font_size", 14)
	_prev_title.add_theme_color_override("font_color", Color("#00E5FF"))
	info_v.add_child(_prev_title)

	_prev_hint = Label.new()
	_prev_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prev_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prev_hint.add_theme_font_size_override("font_size", 12)
	_prev_hint.add_theme_color_override("font_color", Color("#E2E8F0"))
	info_v.add_child(_prev_hint)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	_prev_flow.add_child(btns)

	_prev_btn_build = Button.new()
	_prev_btn_build.custom_minimum_size = Vector2(138, 42)
	_prev_btn_build.clip_text = true
	_prev_btn_build.pressed.connect(func(): confirm_build_requested.emit())
	btns.add_child(_prev_btn_build)

	_prev_btn_cancel = Button.new()
	_prev_btn_cancel.custom_minimum_size = Vector2(102, 42)
	_prev_btn_cancel.clip_text = true
	_style_button(_prev_btn_cancel, Color("#94A3B8"), true)
	_prev_btn_cancel.pressed.connect(func(): cancel_build_requested.emit())
	btns.add_child(_prev_btn_cancel)


func show_build_preview(cfg: Dictionary, gold: int, on_boost: bool) -> void:
	if not _preview_panel or cfg.is_empty():
		return
	_preview_panel.visible = true
	var tid: String = str(cfg.get("id", "pulse"))
	var ip: String = "res://assets/sprites/towers/%s.png" % tid
	if ResourceLoader.exists(ip):
		_prev_icon.texture = load(ip)
	var boost_tag: String = "  [+20% BOOST]" if on_boost else ""
	_prev_title.text = "%s%s" % [str(cfg.get("name", tid)), boost_tag]
	_prev_title.add_theme_color_override("font_color", Color("#10B981") if on_boost else Color("#00E5FF"))
	_prev_hint.text = SettingsManager.tr_key("hint_confirm_build")
	var cost: int = int(cfg.get("cost", 25))
	var cost_l: String = SettingsManager.tr_key("stat_cost")
	var can_aff: bool = gold >= cost
	_prev_btn_build.disabled = not can_aff
	_prev_btn_build.text = "%s
-%d %s" % [SettingsManager.tr_key("btn_build"), cost, cost_l]
	_style_button(_prev_btn_build, Color("#10B981"), can_aff, not can_aff)
	_prev_btn_cancel.text = SettingsManager.tr_key("btn_cancel")


func hide_build_preview() -> void:
	if _preview_panel:
		_preview_panel.visible = false


func _build_overlays() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.03, 0.05, 0.09, 0.90)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_child(center)

	_build_settings_panel(center)
	_build_guide_panel(center)
	_build_levels_panel(center)
	_build_result_panel(center)
	_build_confirm_reset_panel(center)


func _build_settings_panel(parent: Control) -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.custom_minimum_size = Vector2(760, 590)
	_settings_panel.clip_contents = true
	_settings_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#0F172A"), Color("#00E5FF"), 12, 2))
	parent.add_child(_settings_panel)

	var outer_v := VBoxContainer.new()
	outer_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_v.add_theme_constant_override("separation", 8)
	_settings_panel.add_child(outer_v)

	var s_scroll := ScrollContainer.new()
	s_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_v.add_child(s_scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	s_scroll.add_child(vbox)

	_lbl_game_title = Label.new()
	_lbl_game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_game_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_game_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_game_title.add_theme_font_size_override("font_size", 28)
	_lbl_game_title.add_theme_color_override("font_color", Color("#00E5FF"))
	vbox.add_child(_lbl_game_title)

	_lbl_subtitle = Label.new()
	_lbl_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_subtitle.add_theme_font_size_override("font_size", 14)
	_lbl_subtitle.add_theme_color_override("font_color", Color("#94A3B8"))
	vbox.add_child(_lbl_subtitle)

	vbox.add_child(HSeparator.new())

	_lbl_settings_title = Label.new()
	_lbl_settings_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_settings_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_settings_title.add_theme_font_size_override("font_size", 18)
	_lbl_settings_title.add_theme_color_override("font_color", Color("#F8FAFC"))
	vbox.add_child(_lbl_settings_title)

	_lbl_lang = Label.new()
	_lbl_lang.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_lang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_lang.add_theme_color_override("font_color", Color("#CBD5E1"))
	vbox.add_child(_lbl_lang)

	# Все 7 языков в одну ровную строку
	var lang_row := HFlowContainer.new()
	lang_row.add_theme_constant_override("h_separation", 6)
	lang_row.add_theme_constant_override("v_separation", 6)
	lang_row.alignment = FlowContainer.ALIGNMENT_CENTER
	vbox.add_child(lang_row)

	for lang in SettingsManager.languages:
		var code: String = str(lang.get("code", "en"))
		var b := Button.new()
		b.text = str(lang.get("name", code.to_upper()))
		b.custom_minimum_size = Vector2(96, 32)
		_style_button(b, Color("#00E5FF"))
		b.pressed.connect(func(): SettingsManager.set_language(code))
		lang_row.add_child(b)
		_lang_buttons[code] = b

	_lbl_diff_title = Label.new()
	_lbl_diff_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_diff_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_diff_title.add_theme_color_override("font_color", Color("#CBD5E1"))
	vbox.add_child(_lbl_diff_title)

	var diff_row := HFlowContainer.new()
	diff_row.add_theme_constant_override("h_separation", 8)
	diff_row.add_theme_constant_override("v_separation", 6)
	diff_row.alignment = FlowContainer.ALIGNMENT_CENTER
	vbox.add_child(diff_row)

	for d_cfg in [["easy", "#10B981"], ["hard", "#F59E0B"], ["nightmare", "#EF4444"]]:
		var did: String = d_cfg[0]
		var dcol := Color(d_cfg[1])
		var db := Button.new()
		db.custom_minimum_size = Vector2(140, 34)
		db.clip_text = true
		_style_button(db, dcol)
		db.pressed.connect(func(): SettingsManager.set_difficulty(did))
		diff_row.add_child(db)
		_diff_buttons_settings[did] = db

	_lbl_diff_desc = Label.new()
	_lbl_diff_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_diff_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_diff_desc.add_theme_font_size_override("font_size", 12)
	_lbl_diff_desc.add_theme_color_override("font_color", Color("#94A3B8"))
	vbox.add_child(_lbl_diff_desc)

	vbox.add_child(HSeparator.new())

	var master_row: Array = _make_slider_row(vbox)
	_lbl_master = master_row[0]
	_slider_master = master_row[1]
	_val_master = master_row[2]
	_slider_master.value_changed.connect(func(v: float):
		SettingsManager.set_master_volume(v / 100.0)
		_val_master.text = "%d%%" % int(v)
	)

	var sfx_row: Array = _make_slider_row(vbox)
	_lbl_sfx = sfx_row[0]
	_slider_sfx = sfx_row[1]
	_val_sfx = sfx_row[2]
	_slider_sfx.value_changed.connect(func(v: float):
		SettingsManager.set_sfx_volume(v / 100.0)
		_val_sfx.text = "%d%%" % int(v)
	)

	var music_row: Array = _make_slider_row(vbox)
	_lbl_music = music_row[0]
	_slider_music = music_row[1]
	_val_music = music_row[2]
	_slider_music.value_changed.connect(func(v: float):
		SettingsManager.set_music_volume(v / 100.0)
		_val_music.text = "%d%%" % int(v)
	)

	var toggles := HFlowContainer.new()
	toggles.add_theme_constant_override("h_separation", 16)
	toggles.add_theme_constant_override("v_separation", 6)
	toggles.alignment = FlowContainer.ALIGNMENT_CENTER
	vbox.add_child(toggles)

	_chk_mute = CheckBox.new()
	_chk_mute.toggled.connect(func(on: bool): SettingsManager.set_muted(on))
	toggles.add_child(_chk_mute)

	_chk_path = CheckBox.new()
	_chk_path.toggled.connect(func(on: bool): SettingsManager.set_show_path_preview(on))
	toggles.add_child(_chk_path)

	_chk_grid = CheckBox.new()
	_chk_grid.toggled.connect(func(on: bool): SettingsManager.set_show_grid_lines(on))
	toggles.add_child(_chk_grid)

	var speed_row := HFlowContainer.new()
	speed_row.alignment = FlowContainer.ALIGNMENT_CENTER
	speed_row.add_theme_constant_override("h_separation", 10)
	speed_row.add_theme_constant_override("v_separation", 6)
	vbox.add_child(speed_row)

	_lbl_speed = Label.new()
	_lbl_speed.add_theme_color_override("font_color", Color("#CBD5E1"))
	speed_row.add_child(_lbl_speed)

	for spd in [1, 2, 3]:
		var sb := Button.new()
		sb.text = "%dx" % spd
		sb.custom_minimum_size = Vector2(54, 30)
		_style_button(sb, Color("#3B82F6"))
		sb.pressed.connect(func():
			SettingsManager.set_default_speed(spd)
			_sync_settings_controls()
		)
		speed_row.add_child(sb)
		_speed_buttons.append(sb)

	_lbl_speed_hint = Label.new()
	_lbl_speed_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_speed_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_speed_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_speed_hint.add_theme_font_size_override("font_size", 11)
	_lbl_speed_hint.add_theme_color_override("font_color", Color("#94A3B8"))
	vbox.add_child(_lbl_speed_hint)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(sp)

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 8)
	actions.alignment = FlowContainer.ALIGNMENT_CENTER
	outer_v.add_child(actions)

	_btn_open_guide = Button.new()
	_btn_open_guide.custom_minimum_size = Vector2(150, 42)
	_btn_open_guide.clip_text = true
	_style_button(_btn_open_guide, Color("#10B981"), true)
	_btn_open_guide.pressed.connect(show_guide)
	actions.add_child(_btn_open_guide)

	_btn_open_levels = Button.new()
	_btn_open_levels.custom_minimum_size = Vector2(145, 42)
	_btn_open_levels.clip_text = true
	_style_button(_btn_open_levels, Color("#3B82F6"), true)
	_btn_open_levels.pressed.connect(show_levels)
	actions.add_child(_btn_open_levels)

	_btn_new_game = Button.new()
	_btn_new_game.custom_minimum_size = Vector2(140, 42)
	_btn_new_game.clip_text = true
	_style_button(_btn_new_game, Color("#EF4444"))
	_btn_new_game.pressed.connect(show_confirm_new_game)
	actions.add_child(_btn_new_game)

	_btn_play = Button.new()
	_btn_play.custom_minimum_size = Vector2(155, 42)
	_btn_play.clip_text = true
	_style_button(_btn_play, Color("#00E5FF"), true)
	_btn_play.pressed.connect(close_overlays)
	actions.add_child(_btn_play)


func _make_slider_row(parent: Control) -> Array:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(155, 0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", Color("#CBD5E1"))
	row.add_child(lbl)
	_slider_labels.append(lbl)

	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var val := Label.new()
	val.custom_minimum_size = Vector2(46, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_color", Color("#00E5FF"))
	row.add_child(val)

	return [lbl, slider, val]


func _build_guide_panel(parent: Control) -> void:
	_guide_panel = PanelContainer.new()
	_guide_panel.custom_minimum_size = Vector2(780, 600)
	_guide_panel.clip_contents = true
	_guide_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#0F172A"), Color("#10B981"), 12, 2))
	parent.add_child(_guide_panel)

	var root_v := VBoxContainer.new()
	root_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_theme_constant_override("separation", 10)
	_guide_panel.add_child(root_v)

	_lbl_guide_title = Label.new()
	_lbl_guide_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_guide_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_guide_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_guide_title.add_theme_font_size_override("font_size", 24)
	_lbl_guide_title.add_theme_color_override("font_color", Color("#10B981"))
	root_v.add_child(_lbl_guide_title)

	var lang_bar := HFlowContainer.new()
	lang_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	lang_bar.add_theme_constant_override("h_separation", 6)
	lang_bar.add_theme_constant_override("v_separation", 4)
	root_v.add_child(lang_bar)
	for lang in SettingsManager.languages:
		var code: String = str(lang.get("code", "en"))
		var lb := Button.new()
		lb.text = str(lang.get("name", code.to_upper()))
		lb.custom_minimum_size = Vector2(78, 28)
		lb.add_theme_font_size_override("font_size", 11)
		_style_button(lb, Color("#00E5FF"))
		lb.pressed.connect(func(): SettingsManager.set_language(code))
		lang_bar.add_child(lb)
		_guide_lang_buttons[code] = lb

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	var welcome_card := PanelContainer.new()
	welcome_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	welcome_card.add_theme_stylebox_override("panel", _make_panel_style(Color("#07221B"), Color("#10B981"), 10, 2))
	content.add_child(welcome_card)

	var welcome_v := VBoxContainer.new()
	welcome_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	welcome_v.add_theme_constant_override("separation", 6)
	welcome_card.add_child(welcome_v)

	_lbl_welcome_title = Label.new()
	_lbl_welcome_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_welcome_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_welcome_title.add_theme_font_size_override("font_size", 15)
	_lbl_welcome_title.add_theme_color_override("font_color", Color("#6EE7B7"))
	welcome_v.add_child(_lbl_welcome_title)

	_lbl_welcome_body = _make_body_label(welcome_v)
	_lbl_welcome_body.add_theme_color_override("font_color", Color("#ECFDF5"))

	_lbl_goal_t = _make_section_heading(content)
	_lbl_goal_b = _make_body_label(content)

	_lbl_maze_t = _make_section_heading(content)
	_lbl_maze_b = _make_body_label(content)

	_lbl_tiles_t = _make_section_heading(content)

	var legend_items: Array = [
		["tile_spawn", Color("#F97316")],
		["tile_core", Color("#00E5FF")],
		["tile_path", Color("#111F33")],
		["tile_wall", Color("#334155")],
		["tile_boost", Color("#10B981")],
		["tile_tower", Color("#3B82F6")]
	]
	for item in legend_items:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		content.add_child(row)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.color = item[1]
		row.add_child(swatch)

		var lbl := Label.new()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", Color("#E2E8F0"))
		row.add_child(lbl)
		_tile_labels[item[0]] = lbl

	_lbl_ctrl_t = _make_section_heading(content)
	_lbl_ctrl_b = _make_body_label(content)

	var btns := HFlowContainer.new()
	btns.alignment = FlowContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("h_separation", 12)
	btns.add_theme_constant_override("v_separation", 8)
	root_v.add_child(btns)

	_btn_guide_back = Button.new()
	_btn_guide_back.custom_minimum_size = Vector2(150, 40)
	_btn_guide_back.clip_text = true
	_style_button(_btn_guide_back, Color("#94A3B8"))
	_btn_guide_back.pressed.connect(show_settings)
	btns.add_child(_btn_guide_back)

	_btn_guide_play = Button.new()
	_btn_guide_play.custom_minimum_size = Vector2(180, 40)
	_btn_guide_play.clip_text = true
	_style_button(_btn_guide_play, Color("#00E5FF"), true)
	_btn_guide_play.pressed.connect(close_overlays)
	btns.add_child(_btn_guide_play)


func _make_section_heading(parent: Control) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("#00E5FF"))
	parent.add_child(l)
	return l


func _make_body_label(parent: Control) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", Color("#CBD5E1"))
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)
	return l


func _build_levels_panel(parent: Control) -> void:
	_levels_panel = PanelContainer.new()
	_levels_panel.custom_minimum_size = Vector2(820, 560)
	_levels_panel.clip_contents = true
	_levels_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#0F172A"), Color("#3B82F6"), 12, 2))
	parent.add_child(_levels_panel)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	_levels_panel.add_child(v)

	_lbl_levels_title = Label.new()
	_lbl_levels_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_levels_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_levels_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_levels_title.add_theme_font_size_override("font_size", 22)
	_lbl_levels_title.add_theme_color_override("font_color", Color("#3B82F6"))
	v.add_child(_lbl_levels_title)

	var l_diff_row := HFlowContainer.new()
	l_diff_row.add_theme_constant_override("h_separation", 8)
	l_diff_row.add_theme_constant_override("v_separation", 6)
	l_diff_row.alignment = FlowContainer.ALIGNMENT_CENTER
	v.add_child(l_diff_row)

	for d_cfg in [["easy", "#10B981"], ["hard", "#F59E0B"], ["nightmare", "#EF4444"]]:
		var did: String = d_cfg[0]
		var dcol := Color(d_cfg[1])
		var db := Button.new()
		db.custom_minimum_size = Vector2(135, 32)
		db.clip_text = true
		_style_button(db, dcol)
		db.pressed.connect(func(): SettingsManager.set_difficulty(did))
		l_diff_row.add_child(db)
		_diff_buttons_levels[did] = db

	_lbl_levels_diff_desc = Label.new()
	_lbl_levels_diff_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_levels_diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_levels_diff_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_levels_diff_desc.add_theme_font_size_override("font_size", 12)
	_lbl_levels_diff_desc.add_theme_color_override("font_color", Color("#94A3B8"))
	v.add_child(_lbl_levels_diff_desc)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	_levels_grid = GridContainer.new()
	_levels_grid.columns = 4
	_levels_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_levels_grid.add_theme_constant_override("h_separation", 10)
	_levels_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_levels_grid)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(footer)

	_btn_levels_back = Button.new()
	_btn_levels_back.custom_minimum_size = Vector2(180, 40)
	_style_button(_btn_levels_back, Color("#94A3B8"))
	_btn_levels_back.pressed.connect(show_settings)
	footer.add_child(_btn_levels_back)


func _build_result_panel(parent: Control) -> void:
	_result_panel = PanelContainer.new()
	_result_panel.custom_minimum_size = Vector2(460, 220)
	_result_panel.clip_contents = true
	_result_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#0F172A"), Color("#00E5FF"), 12, 2))
	parent.add_child(_result_panel)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_panel.add_child(v)

	_lbl_result_title = Label.new()
	_lbl_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_result_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_result_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_result_title.add_theme_font_size_override("font_size", 26)
	v.add_child(_lbl_result_title)

	_lbl_result_body = Label.new()
	_lbl_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_result_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_result_body.add_theme_color_override("font_color", Color("#CBD5E1"))
	v.add_child(_lbl_result_body)

	var btns := HFlowContainer.new()
	btns.alignment = FlowContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("h_separation", 12)
	btns.add_theme_constant_override("v_separation", 8)
	v.add_child(btns)

	_btn_result_retry = Button.new()
	_btn_result_retry.custom_minimum_size = Vector2(150, 42)
	_btn_result_retry.clip_text = true
	_style_button(_btn_result_retry, Color("#F97316"), true)
	_btn_result_retry.pressed.connect(func():
		close_overlays()
		retry_level_requested.emit()
	)
	btns.add_child(_btn_result_retry)

	_btn_result_next = Button.new()
	_btn_result_next.custom_minimum_size = Vector2(160, 42)
	_btn_result_next.clip_text = true
	_style_button(_btn_result_next, Color("#10B981"), true)
	_btn_result_next.pressed.connect(func():
		close_overlays()
		next_level_requested.emit()
	)
	btns.add_child(_btn_result_next)


func _build_confirm_reset_panel(parent: Control) -> void:
	_confirm_reset_panel = PanelContainer.new()
	_confirm_reset_panel.custom_minimum_size = Vector2(480, 240)
	_confirm_reset_panel.clip_contents = true
	_confirm_reset_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#0F172A"), Color("#EF4444"), 12, 2))
	parent.add_child(_confirm_reset_panel)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_reset_panel.add_child(v)

	_lbl_reset_title = Label.new()
	_lbl_reset_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_reset_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_reset_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_reset_title.add_theme_font_size_override("font_size", 24)
	_lbl_reset_title.add_theme_color_override("font_color", Color("#EF4444"))
	v.add_child(_lbl_reset_title)

	_lbl_reset_body = Label.new()
	_lbl_reset_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_reset_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_reset_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_reset_body.add_theme_color_override("font_color", Color("#E2E8F0"))
	v.add_child(_lbl_reset_body)

	var btns := HFlowContainer.new()
	btns.alignment = FlowContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("h_separation", 14)
	btns.add_theme_constant_override("v_separation", 8)
	v.add_child(btns)

	_btn_reset_cancel = Button.new()
	_btn_reset_cancel.custom_minimum_size = Vector2(150, 42)
	_style_button(_btn_reset_cancel, Color("#94A3B8"))
	_btn_reset_cancel.pressed.connect(show_settings)
	btns.add_child(_btn_reset_cancel)

	_btn_reset_confirm = Button.new()
	_btn_reset_confirm.custom_minimum_size = Vector2(180, 42)
	_style_button(_btn_reset_confirm, Color("#EF4444"), true)
	_btn_reset_confirm.pressed.connect(func():
		close_overlays()
		new_game_requested.emit()
	)
	btns.add_child(_btn_reset_confirm)


func _rebuild_level_buttons() -> void:
	for c in _levels_grid.get_children():
		c.queue_free()
	var waves_word: String = SettingsManager.tr_key("level_waves_short")
	for lvl in _campaign_levels:
		var id: int = int(lvl.get("id", 1))
		var nm: String = str(lvl.get("name", "Level %02d" % id))
		var w: int = int(lvl.get("waves", 10))
		var done: bool = SettingsManager.is_level_completed(id)
		var unlocked: bool = SettingsManager.is_level_unlocked(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(125, 62)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if unlocked:
			b.text = "%s%s\n(%d %s)" % [nm, " [OK]" if done else "", w, waves_word]
			var b_col: Color = Color("#10B981") if done else (Color("#00E5FF") if not bool(lvl.get("has_air", false)) else Color("#F97316"))
			_style_button(b, b_col, done)
			b.pressed.connect(func():
				level_selected.emit(id)
				close_overlays()
			)
		else:
			b.text = "%s\n[%s]" % [nm, SettingsManager.tr_key("lbl_locked")]
			b.disabled = true
			_style_button(b, Color("#475569"), false, true)
		_levels_grid.add_child(b)


func _sync_settings_controls() -> void:
	_slider_master.set_value_no_signal(roundf(SettingsManager.master_volume * 100.0))
	_slider_sfx.set_value_no_signal(roundf(SettingsManager.sfx_volume * 100.0))
	_slider_music.set_value_no_signal(roundf(SettingsManager.music_volume * 100.0))
	_val_master.text = "%d%%" % int(roundf(SettingsManager.master_volume * 100.0))
	_val_sfx.text = "%d%%" % int(roundf(SettingsManager.sfx_volume * 100.0))
	_val_music.text = "%d%%" % int(roundf(SettingsManager.music_volume * 100.0))
	_chk_mute.set_pressed_no_signal(SettingsManager.muted)
	_chk_path.set_pressed_no_signal(SettingsManager.show_path_preview)
	_chk_grid.set_pressed_no_signal(SettingsManager.show_grid_lines)

	for code in _lang_buttons:
		var b: Button = _lang_buttons[code]
		_style_button(b, Color("#00E5FF"), code == SettingsManager.language)
	for code in _guide_lang_buttons:
		var gb: Button = _guide_lang_buttons[code]
		_style_button(gb, Color("#00E5FF"), code == SettingsManager.language)

	var spd_unlocked: bool = SettingsManager.is_fast_speed_unlocked()
	for i in _speed_buttons.size():
		var spd: int = i + 1
		var btn_s: Button = _speed_buttons[i]
		var is_locked: bool = (spd > 1 and not spd_unlocked)
		btn_s.disabled = is_locked
		_style_button(btn_s, Color("#3B82F6"), spd == SettingsManager.default_speed, is_locked)
	if _lbl_speed_hint:
		_lbl_speed_hint.visible = not spd_unlocked
		_lbl_speed_hint.text = SettingsManager.tr_key("speed_locked_hint") % SettingsManager.get_completed_count()


func _apply_translations() -> void:
	_lbl_game_title.text = SettingsManager.tr_key("game_title")
	_lbl_subtitle.text = SettingsManager.tr_key("subtitle")
	_lbl_settings_title.text = SettingsManager.tr_key("settings_title")
	_lbl_lang.text = SettingsManager.tr_key("language_label")
	_lbl_master.text = SettingsManager.tr_key("master_volume")
	_lbl_sfx.text = SettingsManager.tr_key("sfx_volume")
	_lbl_music.text = SettingsManager.tr_key("music_volume")
	_chk_mute.text = SettingsManager.tr_key("mute_all")
	_chk_path.text = SettingsManager.tr_key("show_path")
	_chk_grid.text = SettingsManager.tr_key("show_grid")
	_lbl_speed.text = SettingsManager.tr_key("default_speed")

	_btn_play.text = SettingsManager.tr_key("btn_resume") if _has_started else SettingsManager.tr_key("btn_play")
	_btn_open_guide.text = SettingsManager.tr_key("btn_how_to_play")
	_btn_open_levels.text = SettingsManager.tr_key("btn_levels")
	_btn_new_game.text = SettingsManager.tr_key("btn_new_game")
	_lbl_reset_title.text = SettingsManager.tr_key("confirm_new_game_title")
	_lbl_reset_body.text = SettingsManager.tr_key("confirm_new_game_body")
	_btn_reset_confirm.text = SettingsManager.tr_key("btn_confirm_reset")
	_btn_reset_cancel.text = SettingsManager.tr_key("btn_cancel")

	var vp_w: float = get_viewport().get_visible_rect().size.x
	_hud_btn_guide.text = "?" if vp_w < 1260.0 else ("? " + SettingsManager.tr_key("btn_how_to_play"))
	_hud_btn_settings.text = SettingsManager.tr_key("btn_settings")
	_shop_title_label.text = SettingsManager.tr_key("shop_title")
	set_speed_display(_current_speed)
	set_wave_button_active(_wave_active)

	_lbl_guide_title.text = SettingsManager.tr_key("guide_title")
	_lbl_welcome_title.text = SettingsManager.tr_key("guide_welcome_title")
	_lbl_welcome_body.text = SettingsManager.tr_key("guide_welcome_body")
	_lbl_goal_t.text = SettingsManager.tr_key("guide_goal_title")
	_lbl_goal_b.text = SettingsManager.tr_key("guide_goal_body")
	_lbl_maze_t.text = SettingsManager.tr_key("guide_maze_title")
	_lbl_maze_b.text = SettingsManager.tr_key("guide_maze_body")
	_lbl_tiles_t.text = SettingsManager.tr_key("guide_tiles_title")
	for key in _tile_labels:
		_tile_labels[key].text = SettingsManager.tr_key(key)
	_lbl_ctrl_t.text = SettingsManager.tr_key("guide_controls_title")
	_lbl_ctrl_b.text = SettingsManager.tr_key("guide_controls_body")
	_btn_guide_back.text = SettingsManager.tr_key("btn_settings")
	if not SettingsManager.intro_seen and not _has_started:
		_btn_guide_play.text = SettingsManager.tr_key("btn_start_playing")
	else:
		_btn_guide_play.text = SettingsManager.tr_key("btn_resume") if _has_started else SettingsManager.tr_key("btn_play")

	_lbl_levels_title.text = SettingsManager.tr_key("levels_title")
	_btn_levels_back.text = SettingsManager.tr_key("btn_back")

	_lbl_result_title.text = SettingsManager.tr_key("victory_title") if _last_result_is_victory else SettingsManager.tr_key("defeat_title")
	_lbl_result_title.add_theme_color_override("font_color", Color("#10B981") if _last_result_is_victory else Color("#EF4444"))
	_lbl_result_body.text = SettingsManager.tr_key("victory_body") if _last_result_is_victory else SettingsManager.tr_key("defeat_body")
	_btn_result_retry.text = SettingsManager.tr_key("btn_retry")
	_btn_result_next.text = SettingsManager.tr_key("btn_next_level")

	_lbl_diff_title.text = SettingsManager.tr_key("diff_label")
	_sync_difficulty_ui()
	_sync_settings_controls()


func _sync_difficulty_ui() -> void:
	var cur_d: String = SettingsManager.difficulty
	var colors := {"easy": Color("#10B981"), "hard": Color("#F59E0B"), "nightmare": Color("#EF4444")}
	for did in ["easy", "hard", "nightmare"]:
		var active: bool = (did == cur_d)
		var col: Color = colors[did]
		var txt: String = SettingsManager.tr_key("diff_" + did)
		if _diff_buttons_settings.has(did):
			var bs: Button = _diff_buttons_settings[did]
			bs.text = txt
			_style_button(bs, col, active)
		if _diff_buttons_levels.has(did):
			var bl: Button = _diff_buttons_levels[did]
			bl.text = txt
			_style_button(bl, col, active)
	var desc_txt: String = SettingsManager.tr_key("diff_desc_" + cur_d)
	var d_col: Color = colors.get(cur_d, Color("#10B981"))
	if _lbl_diff_desc:
		_lbl_diff_desc.text = desc_txt
		_lbl_diff_desc.add_theme_color_override("font_color", d_col.lightened(0.25))
	if _lbl_levels_diff_desc:
		_lbl_levels_diff_desc.text = desc_txt
		_lbl_levels_diff_desc.add_theme_color_override("font_color", d_col.lightened(0.25))


func _on_viewport_resized() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	var pad: float = 24.0
	var max_w: float = maxf(280.0, vp.x - pad)
	var max_h: float = maxf(240.0, vp.y - pad)
	if _settings_panel:
		_settings_panel.custom_minimum_size = Vector2(minf(780.0, max_w), minf(600.0, max_h))
	if _guide_panel:
		_guide_panel.custom_minimum_size = Vector2(minf(800.0, max_w), minf(620.0, max_h))
	if _levels_panel:
		var lp_w: float = minf(840.0, max_w)
		_levels_panel.custom_minimum_size = Vector2(lp_w, minf(580.0, max_h))
		if _levels_grid:
			var inner_w: float = maxf(140.0, lp_w - 48.0)
			_levels_grid.columns = clampi(int(floor((inner_w + 10.0) / 155.0)), 1, 4)
	if _result_panel:
		_result_panel.custom_minimum_size = Vector2(minf(460.0, max_w), minf(220.0, max_h))
	if _confirm_reset_panel:
		_confirm_reset_panel.custom_minimum_size = Vector2(minf(480.0, max_w), minf(240.0, max_h))

	var slider_lbl_w: float = 115.0 if vp.x < 560.0 else 175.0
	for sl in _slider_labels:
		sl.custom_minimum_size.x = slider_lbl_w

	var bar_half_w: float = minf(360.0, (vp.x - 16.0) * 0.5)
	var info_w: float = maxf(200.0, bar_half_w * 2.0 - 28.0)
	if _inspector_panel:
		_inspector_panel.offset_left = -bar_half_w
		_inspector_panel.offset_right = bar_half_w
		if _insp_info_box:
			_insp_info_box.custom_minimum_size.x = minf(340.0, info_w)
	if _preview_panel:
		_preview_panel.offset_left = -bar_half_w
		_preview_panel.offset_right = bar_half_w
		if _prev_info_box:
			_prev_info_box.custom_minimum_size.x = minf(340.0, info_w)
	if _hud_btn_guide:
		_hud_btn_guide.text = "?" if vp.x < 1260.0 else ("? " + SettingsManager.tr_key("btn_how_to_play"))
	call_deferred("_update_dynamic_bars")


func _update_dynamic_bars() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	if _hud_bar and _status_toast:
		var bar_h: float = maxf(_hud_bar.size.y, 44.0)
		var toast_half_w: float = minf(280.0, (vp.x - 20.0) * 0.5)
		_status_toast.offset_left = -toast_half_w
		_status_toast.offset_right = toast_half_w
		_status_toast.offset_top = bar_h + 6.0
		_status_toast.offset_bottom = bar_h + 6.0
	if _shop_bar:
		var shop_h: float = maxf(_shop_bar.size.y, 126.0)
		var bottom_y: float = -(shop_h + 8.0)
		if _inspector_panel:
			_inspector_panel.offset_bottom = bottom_y
			_inspector_panel.offset_top = bottom_y
		if _preview_panel:
			_preview_panel.offset_bottom = bottom_y
			_preview_panel.offset_top = bottom_y
