extends Node3D

@onready var grid_manager = $GridManager
@onready var ui = $UI
@onready var sfx = $SfxPlayer

var all_towers: Dictionary = {}
var level_towers: Array = []
var selected_tower_id: String = "pulse"
var inspected_cell := Vector2i(-1, -1)

var current_level_index: int = 1
var max_levels: int = 20
var gold: int = 220
var cores: int = 10
var current_wave: int = 0
var total_waves: int = 10
var current_speed: int = 1
var level_name: String = "01. Neon Bend"
var last_msg_key: String = "msg_ready"


func _ready() -> void:
	_load_towers_catalog()
	current_speed = SettingsManager.default_speed if SettingsManager.is_fast_speed_unlocked() else 1
	grid_manager.game_speed = float(current_speed)
	ui.set_speed_display(current_speed)

	grid_manager.level_loaded.connect(_on_level_loaded)
	grid_manager.tower_place_requested.connect(_on_tower_place_requested)
	grid_manager.tower_remove_requested.connect(_on_tower_remove_requested)
	grid_manager.tower_inspected.connect(_on_tower_inspected)
	grid_manager.tower_inspection_cleared.connect(_on_tower_inspection_cleared)
	grid_manager.build_preview_changed.connect(_on_build_preview_changed)
	grid_manager.build_preview_cleared.connect(_on_build_preview_cleared)
	grid_manager.placement_rejected.connect(_on_placement_rejected)
	grid_manager.enemy_killed.connect(_on_enemy_killed)
	grid_manager.core_damaged.connect(_on_core_damaged)
	grid_manager.wave_state_changed.connect(_on_wave_state_changed)
	grid_manager.wave_cleared.connect(_on_wave_cleared)
	grid_manager.level_victory.connect(func():
		SettingsManager.mark_level_completed(current_level_index)
		ui.show_result(true)
	)
	grid_manager.level_defeat.connect(func(): ui.show_result(false))
	grid_manager.sfx_requested.connect(func(n: String): sfx.play(n))

	ui.overlay_visibility_changed.connect(_on_overlay_changed)
	ui.level_selected.connect(_load_level)
	ui.next_level_requested.connect(func():
		if current_level_index < max_levels:
			_load_level(current_level_index + 1)
	)
	ui.retry_level_requested.connect(func(): _load_level(current_level_index))
	ui.start_wave_requested.connect(_on_start_wave)
	ui.speed_cycle_requested.connect(_on_cycle_speed)
	ui.zoom_in_requested.connect(func(): grid_manager.zoom_by(0.84))
	ui.zoom_out_requested.connect(func(): grid_manager.zoom_by(1.18))
	ui.reset_camera_requested.connect(func(): grid_manager.reset_camera())
	ui.tower_selected.connect(_select_tower)
	ui.upgrade_inspected_requested.connect(_on_upgrade_inspected)
	ui.sell_inspected_requested.connect(_on_sell_inspected)
	ui.close_inspector_requested.connect(func(): grid_manager.clear_inspection())
	ui.confirm_build_requested.connect(func(): grid_manager.confirm_pending_build())
	ui.cancel_build_requested.connect(func(): grid_manager.clear_build_preview())
	SettingsManager.language_changed.connect(func(_c: String): _refresh_hud())
	SettingsManager.difficulty_changed.connect(_on_difficulty_changed)

	_load_level(1)


func _load_towers_catalog() -> void:
	var path := "res://data/towers.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		for t in parsed.get("towers", []):
			all_towers[str(t.get("id", ""))] = t


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke: InputEventKey = event
	if not ke.pressed or ke.echo:
		return

	if ke.keycode == KEY_ESCAPE:
		if ui.is_any_overlay_open():
			ui.close_overlays()
		elif grid_manager.pending_build_cell != Vector2i(-1, -1):
			grid_manager.clear_build_preview()
		elif inspected_cell != Vector2i(-1, -1):
			grid_manager.clear_inspection()
		else:
			ui.show_settings()
		return
	if ui.is_any_overlay_open():
		return

	if ke.keycode == KEY_0:
		grid_manager.reset_camera()
		return
	if ke.keycode == KEY_SPACE:
		_on_start_wave()
		return

	if ke.keycode == KEY_U and inspected_cell != Vector2i(-1, -1):
		_on_upgrade_inspected()
		return
	if ke.keycode == KEY_X and inspected_cell != Vector2i(-1, -1):
		_on_sell_inspected()
		return

	if int(ke.keycode) >= int(KEY_1) and int(ke.keycode) <= int(KEY_6):
		var idx: int = int(ke.keycode) - int(KEY_1)
		if idx >= 0 and idx < level_towers.size():
			_select_tower(str(level_towers[idx].get("id", "pulse")))
		return

	pass


func _on_overlay_changed(is_open: bool) -> void:
	grid_manager.input_enabled = not is_open


func _load_level(idx: int) -> void:
	if not SettingsManager.is_level_unlocked(idx):
		return
	current_level_index = idx
	inspected_cell = Vector2i(-1, -1)
	ui.hide_inspector()
	ui.hide_build_preview()
	var path: String = "res://data/levels/level_%02d.json" % idx
	grid_manager.load_level_from_file(path)


func _on_level_loaded(data: Dictionary) -> void:
	level_name = str(data.get("name", "Level %02d" % current_level_index))
	var mods: Dictionary = SettingsManager.get_difficulty_mods()
	gold = int(roundf(float(data.get("start_gold", 220)) * float(mods.get("gold_mult", 1.0))))
	cores = int(mods.get("cores", 10))
	current_wave = 0
	var waves: Array = data.get("waves", [])
	total_waves = waves.size()
	last_msg_key = "msg_ready"

	level_towers.clear()
	var ids: Array = data.get("available_towers", ["pulse", "cannon"])
	for tid in ids:
		if all_towers.has(str(tid)):
			level_towers.append(all_towers[str(tid)])

	if not level_towers.is_empty():
		selected_tower_id = str(level_towers[0].get("id", "pulse"))
		grid_manager.set_selected_tower(level_towers[0])

	ui.set_available_towers(level_towers, selected_tower_id, gold)
	_refresh_hud()


func _select_tower(tid: String) -> void:
	if not all_towers.has(tid):
		return
	selected_tower_id = tid
	grid_manager.set_selected_tower(all_towers[tid])
	ui.update_shop_state(selected_tower_id, gold)


func _on_tower_inspected(cell: Vector2i, info: Dictionary) -> void:
	inspected_cell = cell
	ui.show_inspector(info, gold)


func _on_tower_inspection_cleared() -> void:
	inspected_cell = Vector2i(-1, -1)
	ui.hide_inspector()


func _on_build_preview_changed(cell: Vector2i, on_boost: bool) -> void:
	if all_towers.has(selected_tower_id):
		ui.show_build_preview(all_towers[selected_tower_id], gold, on_boost)


func _on_build_preview_cleared() -> void:
	ui.hide_build_preview()
	ui.hide_build_preview()


func _on_upgrade_inspected() -> void:
	if inspected_cell == Vector2i(-1, -1):
		return
	var info: Dictionary = grid_manager.get_inspected_tower_info(inspected_cell)
	if info.is_empty():
		return
	if int(info["level"]) >= int(info["max_level"]):
		last_msg_key = "msg_max_level"
		_refresh_hud()
		return
	var cost: int = int(info["upgrade_cost"])
	if gold < cost:
		last_msg_key = "msg_no_gold"
		_refresh_hud()
		return
	gold -= cost
	var updated: Dictionary = grid_manager.commit_upgrade_tower(inspected_cell)
	last_msg_key = "msg_upgraded"
	ui.show_inspector(updated, gold)
	_refresh_hud()


func _on_sell_inspected() -> void:
	if inspected_cell == Vector2i(-1, -1):
		return
	var info: Dictionary = grid_manager.get_inspected_tower_info(inspected_cell)
	if info.is_empty():
		return
	_on_tower_remove_requested(inspected_cell, int(info["sell_refund"]))


func _on_start_wave() -> void:
	if grid_manager.start_next_wave():
		last_msg_key = "msg_wave_started"
		_refresh_hud()


func _on_cycle_speed() -> void:
	if not SettingsManager.is_fast_speed_unlocked():
		current_speed = 1
		grid_manager.game_speed = 1.0
		ui.set_speed_display(1)
		last_msg_key = "msg_speed_locked"
		_refresh_hud()
		return
	current_speed = 1 if current_speed >= 3 else current_speed + 1
	grid_manager.game_speed = float(current_speed)
	ui.set_speed_display(current_speed)


func _on_wave_state_changed(wave_num: int, t_waves: int, active: bool) -> void:
	current_wave = wave_num
	total_waves = t_waves
	ui.set_wave_button_active(active)
	_refresh_hud()


func _on_difficulty_changed(_diff_id: String) -> void:
	if current_wave == 0 and not grid_manager.is_wave_active() and grid_manager._placed_towers.is_empty():
		_load_level(current_level_index)
	else:
		_refresh_hud()


func _on_wave_cleared(bonus_gold: int) -> void:
	var b_mult: float = float(SettingsManager.get_difficulty_mods().get("bounty_mult", 1.0))
	var interest: int = int(floorf(float(gold) * 0.05))
	gold += int(roundf(float(bonus_gold) * b_mult)) + interest
	last_msg_key = "msg_wave_cleared"
	_refresh_hud()


func _on_enemy_killed(bounty: int) -> void:
	var b_mult: float = float(SettingsManager.get_difficulty_mods().get("bounty_mult", 1.0))
	gold += max(1, int(roundf(float(bounty) * b_mult)))
	_refresh_hud()


func _on_core_damaged(remaining_cores: int) -> void:
	cores = remaining_cores
	_refresh_hud()


func _on_tower_place_requested(cell: Vector2i, on_boost: bool) -> void:
	if not all_towers.has(selected_tower_id):
		return
	var cfg: Dictionary = all_towers[selected_tower_id]
	var cost: int = int(cfg.get("cost", 25))
	if gold < cost:
		last_msg_key = "msg_no_gold"
		_refresh_hud()
		return

	gold -= cost
	grid_manager.commit_place_tower(cell, cfg)
	last_msg_key = "msg_placed_boost" if on_boost else "msg_placed"
	_refresh_hud()


func _on_tower_remove_requested(cell: Vector2i, refund: int) -> void:
	gold += refund
	grid_manager.commit_remove_tower(cell)
	last_msg_key = "msg_removed"
	_refresh_hud()


func _on_placement_rejected(_cell: Vector2i, reason_key: String) -> void:
	last_msg_key = reason_key
	_refresh_hud()


func _refresh_hud() -> void:
	ui.update_hud(level_name, gold, cores, current_wave, total_waves, last_msg_key)
	if inspected_cell != Vector2i(-1, -1):
		var info: Dictionary = grid_manager.get_inspected_tower_info(inspected_cell)
		if not info.is_empty():
			ui.show_inspector(info, gold)
	if grid_manager.pending_build_cell != Vector2i(-1, -1) and all_towers.has(selected_tower_id):
		ui.show_build_preview(all_towers[selected_tower_id], gold, grid_manager._boost_set.has(grid_manager.pending_build_cell))
