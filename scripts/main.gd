extends Node2D

@onready var grid_manager: GridManager = $GridManager
@onready var status_label: Label = $HUD/TopBar/StatusLabel

var current_level_index: int = 1
var max_levels: int = 20
var gold: int = 260
var cores: int = 10
var total_waves: int = 10
var level_name: String = "01. Open Grid"


func _ready() -> void:
	grid_manager.level_loaded.connect(_on_level_loaded)
	grid_manager.tower_placed.connect(_on_tower_placed)
	grid_manager.tower_removed.connect(_on_tower_removed)
	grid_manager.placement_rejected.connect(_on_placement_rejected)
	_load_level(1)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_BRACKETRIGHT or event.keycode == KEY_PAGEDOWN:
		_load_level(wrapi(current_level_index + 1, 1, max_levels + 1))
	elif event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_PAGEUP:
		_load_level(wrapi(current_level_index - 1, 1, max_levels + 1))


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
	_update_hud("[ / ] — смена уровня | ЛКМ — поставить | ПКМ — убрать")


func _on_tower_placed(_cell: Vector2i, on_boost: bool) -> void:
	gold = max(0, gold - 25)
	var msg := "Башня на Boost-клетке (+20% урона)!" if on_boost else "Башня установлена"
	_update_hud(msg)


func _on_tower_removed(_cell: Vector2i) -> void:
	gold += 18
	_update_hud("Башня продана (+18)")


func _on_placement_rejected(_cell: Vector2i, reason: String) -> void:
	_update_hud(reason)


func _update_hud(msg: String) -> void:
	if status_label:
		status_label.text = "%s  |  Credits: %d  |  Cores: %d  |  Waves: %d  |  %s" % [
			level_name, gold, cores, total_waves, msg
		]
