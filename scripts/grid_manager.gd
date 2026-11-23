class_name GridManager
extends Node2D

## Управляет игровой сеткой с ФИКСИРОВАННЫМИ предзаданными маршрутами врагов.
## Игрок не может менять маршрут и не может строить на дороге (PATH).
## Показывает радиус атаки выбранной башни при наведении и рисует 6 типов башен.

signal tower_place_requested(cell: Vector2i, on_boost: bool)
signal tower_remove_requested(cell: Vector2i, tower_id: String)
signal placement_rejected(cell: Vector2i, reason_key: String)
signal level_loaded(level_data: Dictionary)

enum CellType { EMPTY, WALL, PATH, BOOST, SPAWN, CORE, TOWER }

@export var grid_size := Vector2i(24, 14)
@export var cell_size := Vector2(58.0, 50.0)

@export_group("Colors")
@export var bg_color := Color("#0B0F17")
@export var grid_line_color := Color("#1C2538")
@export var wall_color := Color("#1E293B")
@export var road_color := Color("#111F33")
@export var road_border_color := Color(0.0, 0.898, 1.0, 0.22)
@export var boost_color := Color(0.06, 0.72, 0.51, 0.25)
@export var path_color := Color("#00E5FF")
@export var valid_hover_color := Color(0.0, 0.898, 1.0, 0.28)
@export var invalid_hover_color := Color(1.0, 0.231, 0.361, 0.40)

var current_level_data: Dictionary = {}
var spawns: Array[Vector2i] = []
var core_cell := Vector2i(23, 6)
var fixed_paths: Array = [] # Array of Array[Vector2i]
var walls: Array[Vector2i] = []
var boost_tiles: Array[Vector2i] = []

var input_enabled := false
var selected_tower_config: Dictionary = {}

var _cells: Dictionary = {}        # Vector2i -> CellType
var _placed_towers: Dictionary = {} # Vector2i -> Dictionary (tower config)
var _boost_set: Dictionary = {}    # Vector2i -> bool
var _hover_cell := Vector2i(-1, -1)
var _can_place_hover := false
var _path_lines: Array[Line2D] = []


func _ready() -> void:
	SettingsManager.settings_changed.connect(_on_settings_changed)
	_center_grid_in_viewport()


func _center_grid_in_viewport() -> void:
	var vp_size := get_viewport_rect().size
	var total := Vector2(grid_size) * cell_size
	var top_bar_h := 50.0
	var bottom_bar_h := 128.0
	var avail_h := vp_size.y - top_bar_h - bottom_bar_h
	position = Vector2(
		maxf(12.0, (vp_size.x - total.x) * 0.5),
		top_bar_h + maxf(8.0, (avail_h - total.y) * 0.5)
	)


func _on_settings_changed() -> void:
	for line in _path_lines:
		if is_instance_valid(line):
			line.visible = SettingsManager.show_path_preview
	queue_redraw()


func set_selected_tower(tower_cfg: Dictionary) -> void:
	selected_tower_config = tower_cfg
	queue_redraw()


func load_level_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("Level file not found: " + path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON in level file: " + path)
		return false

	current_level_data = parsed
	var gs: Array = parsed.get("grid_size", [24, 14])
	grid_size = Vector2i(int(gs[0]), int(gs[1]))

	spawns = _parse_vec2i_array(parsed.get("spawns", [[0, 6]]))
	var cp: Array = parsed.get("core_pos", [23, 6])
	core_cell = Vector2i(int(cp[0]), int(cp[1]))
	walls = _parse_vec2i_array(parsed.get("walls", []))
	boost_tiles = _parse_vec2i_array(parsed.get("boost_tiles", []))

	fixed_paths.clear()
	for raw_p in parsed.get("paths", []):
		fixed_paths.append(_parse_vec2i_array(raw_p))

	_hover_cell = Vector2i(-1, -1)
	_placed_towers.clear()
	_center_grid_in_viewport()
	_init_grid()
	level_loaded.emit(current_level_data)
	return true


func _parse_vec2i_array(raw: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for item in raw:
		if item is Array and item.size() >= 2:
			result.append(Vector2i(int(item[0]), int(item[1])))
	return result


func _init_grid() -> void:
	_cells.clear()
	_boost_set.clear()
	for x in grid_size.x:
		for y in grid_size.y:
			_cells[Vector2i(x, y)] = CellType.EMPTY

	for b in boost_tiles:
		if _cells.has(b):
			_cells[b] = CellType.BOOST
			_boost_set[b] = true
	for w in walls:
		if _cells.has(w):
			_cells[w] = CellType.WALL
	for p in fixed_paths:
		for c: Vector2i in p:
			if _cells.has(c):
				_cells[c] = CellType.PATH
	for s in spawns:
		if _cells.has(s):
			_cells[s] = CellType.SPAWN
	if _cells.has(core_cell):
		_cells[core_cell] = CellType.CORE

	_rebuild_path_lines()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return

	if event is InputEventMouseMotion:
		var cell := world_to_cell(get_local_mouse_position())
		if cell != _hover_cell:
			_hover_cell = cell
			_can_place_hover = _is_buildable_cell(_hover_cell)
			queue_redraw()

	elif event is InputEventMouseButton and event.pressed:
		var cell := world_to_cell(get_local_mouse_position())
		if not _cells.has(cell):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(cell)


func _is_buildable_cell(cell: Vector2i) -> bool:
	var t: int = _cells.get(cell, -1)
	return t == CellType.EMPTY or t == CellType.BOOST


func _handle_left_click(cell: Vector2i) -> void:
	var t: int = _cells.get(cell, -1)
	if t == CellType.PATH or t == CellType.SPAWN or t == CellType.CORE:
		placement_rejected.emit(cell, "msg_on_road")
		return
	if not _is_buildable_cell(cell):
		placement_rejected.emit(cell, "msg_occupied")
		return
	tower_place_requested.emit(cell, _boost_set.has(cell))


func _handle_right_click(cell: Vector2i) -> void:
	if _cells.get(cell, -1) != CellType.TOWER:
		return
	var cfg: Dictionary = _placed_towers.get(cell, {})
	tower_remove_requested.emit(cell, str(cfg.get("id", "pulse")))


func commit_place_tower(cell: Vector2i, tower_cfg: Dictionary) -> void:
	_cells[cell] = CellType.TOWER
	_placed_towers[cell] = tower_cfg.duplicate()
	_can_place_hover = false
	queue_redraw()


func commit_remove_tower(cell: Vector2i) -> void:
	_cells[cell] = CellType.BOOST if _boost_set.has(cell) else CellType.EMPTY
	_placed_towers.erase(cell)
	_can_place_hover = _is_buildable_cell(_hover_cell)
	queue_redraw()


func world_to_cell(local_pos: Vector2) -> Vector2i:
	return Vector2i(floori(local_pos.x / cell_size.x), floori(local_pos.y / cell_size.y))


func cell_to_world_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * cell_size + cell_size * 0.5


func _rebuild_path_lines() -> void:
	for line in _path_lines:
		if is_instance_valid(line):
			line.queue_free()
	_path_lines.clear()

	for i in fixed_paths.size():
		var pts := PackedVector2Array()
		for c: Vector2i in fixed_paths[i]:
			pts.append(cell_to_world_center(c))

		var line := Line2D.new()
		line.name = "FixedRouteLine_%d" % i
		line.points = pts
		line.width = 4.0
		line.default_color = path_color
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.visible = SettingsManager.show_path_preview
		add_child(line)
		_path_lines.append(line)


func _draw() -> void:
	var total_size := Vector2(grid_size) * cell_size
	draw_rect(Rect2(Vector2.ZERO, total_size), bg_color)

	for cell: Vector2i in _cells:
		var rect := Rect2(Vector2(cell) * cell_size, cell_size)
		var inner := rect.grow(-2.0)
		match _cells[cell]:
			CellType.PATH:
				draw_rect(rect, road_color)
				draw_rect(rect.grow(-1.0), road_border_color, false, 1.0)
			CellType.WALL:
				draw_rect(inner, wall_color)
				draw_rect(inner.grow(-6.0), Color("#334155"), false, 1.5)
			CellType.BOOST:
				draw_rect(inner, boost_color)
				draw_rect(inner.grow(-8.0), Color("#10B981", 0.65), false, 2.0)
			CellType.SPAWN:
				draw_rect(inner, Color("#F97316", 0.85))
			CellType.CORE:
				var center := cell_to_world_center(cell)
				draw_rect(inner, Color("#00E5FF", 0.25))
				draw_circle(center, minf(cell_size.x, cell_size.y) * 0.38, Color("#00E5FF", 0.9))
				draw_arc(center, minf(cell_size.x, cell_size.y) * 0.46, 0, TAU, 24, Color("#00E5FF", 0.6), 2.0)
			CellType.TOWER:
				_draw_tower_cell(cell, inner)

	if SettingsManager.show_grid_lines:
		for x in grid_size.x + 1:
			var px := x * cell_size.x
			draw_line(Vector2(px, 0.0), Vector2(px, total_size.y), grid_line_color, 1.0)
		for y in grid_size.y + 1:
			var py := y * cell_size.y
			draw_line(Vector2(0.0, py), Vector2(total_size.x, py), grid_line_color, 1.0)

	# Подсветка клетки и радиуса атаки выбранной башни при наведении
	if input_enabled and _cells.has(_hover_cell):
		var hover_rect := Rect2(Vector2(_hover_cell) * cell_size, cell_size).grow(-2.0)
		var color := valid_hover_color if _can_place_hover else invalid_hover_color
		draw_rect(hover_rect, color)
		if _can_place_hover and not selected_tower_config.is_empty():
			var rng := float(selected_tower_config.get("range", 180.0))
			var t_col := Color(str(selected_tower_config.get("color", "#00E5FF")))
			var center := cell_to_world_center(_hover_cell)
			draw_circle(center, rng, Color(t_col.r, t_col.g, t_col.b, 0.10))
			draw_arc(center, rng, 0, TAU, 48, Color(t_col.r, t_col.g, t_col.b, 0.65), 1.8)


func _draw_tower_cell(cell: Vector2i, rect: Rect2) -> void:
	var cfg: Dictionary = _placed_towers.get(cell, {})
	var col := Color(str(cfg.get("color", "#3B82F6")))
	var center := cell_to_world_center(cell)
	var r := minf(cell_size.x, cell_size.y) * 0.34

	# Пьедестал
	draw_rect(rect, Color("#111827"))
	draw_rect(rect, Color("#10B981") if _boost_set.has(cell) else col.darkened(0.25), false, 2.0)

	# Отличительная геометрическая форма по типу башни
	match str(cfg.get("id", "pulse")):
		"pulse":
			draw_circle(center, r * 0.75, col)
			draw_line(center, center + Vector2(r * 1.1, 0), Color.WHITE, 3.0)
		"cannon":
			draw_rect(Rect2(center - Vector2(r * 0.75, r * 0.75), Vector2(r * 1.5, r * 1.5)), col)
			draw_circle(center, r * 0.35, Color("#0B0F17"))
		"cryo":
			var pts := PackedVector2Array([
				center + Vector2(0, -r),
				center + Vector2(r, 0),
				center + Vector2(0, r),
				center + Vector2(-r, 0)
			])
			draw_colored_polygon(pts, col)
		"tesla":
			draw_circle(center, r * 0.55, col)
			draw_arc(center, r * 0.9, 0, TAU, 16, col.lightened(0.35), 2.0)
		"laser":
			var tri := PackedVector2Array([
				center + Vector2(r, 0),
				center + Vector2(-r * 0.8, -r * 0.8),
				center + Vector2(-r * 0.8, r * 0.8)
			])
			draw_colored_polygon(tri, col)
		"railgun":
			draw_rect(Rect2(center - Vector2(r, r * 0.35), Vector2(r * 2.0, r * 0.7)), col)
			draw_line(center - Vector2(r * 0.8, 0), center + Vector2(r * 1.15, 0), Color.WHITE, 2.0)
		_:
			draw_circle(center, r * 0.75, col)
