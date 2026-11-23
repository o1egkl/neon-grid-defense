extends Node2D

@onready var grid_manager: GridManager = $GridManager
@onready var ui: UIController = $UI

var all_towers: Dictionary = {} # id -> Dictionary
var level_towers: Array = []    # Array of Dictionary available on current level
var selected_tower_id: String = "pulse"

var current_level_index: int = 1
var max_levels: int = 20
var gold: int = 220
var cores: int = 10
var total_waves: int = 10
var level_name: String = "01. Neon Bend"
var last_msg_key: String = "msg_ready"


func _ready() -> void:
	_load_towers_catalog()

	grid_manager.level_loaded.connect(_on_level_loaded)
	grid_manager.tower_place_requested.connect(_on_tower_place_requested)
	grid_manager.tower_remove_requested.connect(_on_tower_remove_requested)
	grid_manager.placement_rejected.connect(_on_placement_rejected)

	ui.overlay_visibility_changed.connect(_on_overlay_changed)
	ui.level_selected.connect(_load_level)
	ui.prev_level_requested.connect(func(): _load_level(wrapi(current_level_index - 1, 1, max_levels + 1)))
	ui.next_level_requested.connect(func(): _load_level(wrapi(current_level_index + 1, 1, max_levels + 1)))
	ui.tower_selected.connect(_select_tower)
	SettingsManager.language_changed.connect(func(_c): _refresh_hud())

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
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if ui.is_any_overlay_open():
			ui.close_overlays()
		else:
			ui.show_settings()
		return
	if ui.is_any_overlay_open():
		return

	# Горячие клавиши 1-6 для выбора доступной башни
	if event.keycode >= KEY_1 and event.keycode <= KEY_6:
		var idx := event.keycode - KEY_1
		if idx < level_towers.size():
			_select_tower(str(level_towers[idx].get("id", "pulse")))
		return

	if event.keycode == KEY_BRACKETRIGHT or event.keycode == KEY_PAGEDOWN:
		_load_level(wrapi(current_level_index + 1, 1, max_levels + 1))
	elif event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_PAGEUP:
		_load_level(wrapi(current_level_index - 1, 1, max_levels + 1))


func _on_overlay_changed(is_open: bool) -> void:
	grid_manager.input_enabled = not is_open


func _load_level(idx: int) -> void:
	current_level_index = idx
	var path := "res://data/levels/level_%02d.json" % idx
	grid_manager.load_level_from_file(path)


func _on_level_loaded(data: Dictionary) -> void:
	level_name = str(data.get("name", "Level %02d" % current_level_index))
	gold = int(data.get("start_gold", 220))
	cores = int(data.get("cores_count", 10))
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


func _on_tower_place_requested(cell: Vector2i, on_boost: bool) -> void:
	if not all_towers.has(selected_tower_id):
		return
	var cfg: Dictionary = all_towers[selected_tower_id]
	var cost := int(cfg.get("cost", 25))
	if gold < cost:
		last_msg_key = "msg_no_gold"
		_refresh_hud()
		return

	gold -= cost
	grid_manager.commit_place_tower(cell, cfg)
	last_msg_key = "msg_placed_boost" if on_boost else "msg_placed"
	_refresh_hud()


func _on_tower_remove_requested(cell: Vector2i, tower_id: String) -> void:
	var cfg: Dictionary = all_towers.get(tower_id, {})
	var refund := int(roundf(float(cfg.get("cost", 25)) * 0.75))
	gold += refund
	grid_manager.commit_remove_tower(cell)
	last_msg_key = "msg_removed"
	_refresh_hud()


func _on_placement_rejected(_cell: Vector2i, reason_key: String) -> void:
	last_msg_key = reason_key
	_refresh_hud()


func _refresh_hud() -> void:
	ui.update_hud(level_name, gold, cores, total_waves, last_msg_key)
