extends Node2D

@onready var grid_manager: GridManager = $GridManager
@onready var ui: UIController = $UI

var current_level_index: int = 1
var max_levels: int = 20
var gold: int = 260
var cores: int = 10
var total_waves: int = 10
var level_name: String = "01. Open Grid"
var last_msg_key: String = "msg_ready"


func _ready() -> void:
	grid_manager.level_loaded.connect(_on_level_loaded)
	grid_manager.tower_placed.connect(_on_tower_placed)
	grid_manager.tower_removed.connect(_on_tower_removed)
	grid_manager.placement_rejected.connect(_on_placement_rejected)

	ui.overlay_visibility_changed.connect(_on_overlay_changed)
	ui.level_selected.connect(_load_level)
	ui.prev_level_requested.connect(func(): _load_level(wrapi(current_level_index - 1, 1, max_levels + 1)))
	ui.next_level_requested.connect(func(): _load_level(wrapi(current_level_index + 1, 1, max_levels + 1)))
	SettingsManager.language_changed.connect(func(_c): _refresh_hud())

	_load_level(1)


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
	gold = int(data.get("start_gold", 260))
	cores = int(data.get("cores_count", 10))
	var waves: Array = data.get("waves", [])
	total_waves = waves.size()
	last_msg_key = "msg_ready"
	_refresh_hud()


func _on_tower_placed(_cell: Vector2i, on_boost: bool) -> void:
	gold = max(0, gold - 25)
	last_msg_key = "msg_placed_boost" if on_boost else "msg_placed"
	_refresh_hud()


func _on_tower_removed(_cell: Vector2i) -> void:
	gold += 18
	last_msg_key = "msg_removed"
	_refresh_hud()


func _on_placement_rejected(_cell: Vector2i, reason_key: String) -> void:
	last_msg_key = reason_key
	_refresh_hud()


func _refresh_hud() -> void:
	ui.update_hud(level_name, gold, cores, total_waves, last_msg_key)
