class_name GridManager
extends Node2D

## Управляет игровой сеткой, загрузкой уровней из JSON, размещением башен,
## зонами запрета строительства (no_build), площадками усиления (boost) и Path Preview.

signal tower_placed(cell: Vector2i, on_boost: bool)
signal tower_removed(cell: Vector2i)
signal paths_updated(paths: Array[PackedVector2Array])
signal placement_rejected(cell: Vector2i, reason: String)
signal level_loaded(level_data: Dictionary)

enum CellType { EMPTY, WALL, NO_BUILD, BOOST, SPAWN, CORE, TOWER }

@export var grid_size := Vector2i(24, 14)
@export var cell_size := Vector2(64.0, 64.0)
@export var spawns: Array[Vector2i] = [Vector2i(0, 6)]
@export var core_cell := Vector2i(23, 6)
@export var walls: Array[Vector2i] = []
@export var no_build_zones: Array[Vector2i] = []
@export var boost_tiles: Array[Vector2i] = []

@export_group("Colors")
@export var bg_color := Color("#0B0F17")
@export var grid_line_color := Color("#1C2538")
@export var wall_color := Color("#1E293B")
@export var no_build_color := Color(0.96, 0.62, 0.04, 0.16)
@export var boost_color := Color(0.06, 0.72, 0.51, 0.25)
@export var path_color := Color("#00E5FF")
@export var valid_hover_color := Color(0.0, 0.898, 1.0, 0.28)
@export var invalid_hover_color := Color(1.0, 0.231, 0.361, 0.40)

var pathfinding := PathfindingService.new()
var current_level_data: Dictionary = {}
var _cells: Dictionary = {} # Vector2i -> CellType
var _boost_set: Dictionary = {} # Vector2i -> bool
var _hover_cell := Vector2i(-1, -1)
var _can_place_hover := false
var _build_mode := true
var _path_lines: Array[Line2D] = []


func _ready() -> void:
	if FileAccess.file_exists("res://data/levels/level_01.json"):
		load_level_from_file("res://data/levels/level_01.json")
	else:
		_init_grid()
		_refresh_main_paths()


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
	no_build_zones = _parse_vec2i_array(parsed.get("no_build_zones", []))
	boost_tiles = _parse_vec2i_array(parsed.get("boost_tiles", []))

	_hover_cell = Vector2i(-1, -1)
	_init_grid()
	_refresh_main_paths()
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
	for nb in no_build_zones:
		if _cells.has(nb):
			_cells[nb] = CellType.NO_BUILD
	for w in walls:
		if _cells.has(w):
			_cells[w] = CellType.WALL
	for s in spawns:
		if _cells.has(s):
			_cells[s] = CellType.SPAWN
	if _cells.has(core_cell):
		_cells[core_cell] = CellType.CORE

	pathfinding.setup(grid_size, cell_size, walls)
	_rebuild_path_lines()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _build_mode:
		return

	if event is InputEventMouseMotion:
		var cell := world_to_cell(get_local_mouse_position())
		if cell != _hover_cell:
			_hover_cell = cell
			_update_hover_preview()
			queue_redraw()

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var cell := world_to_cell(get_local_mouse_position())
			try_place_tower(cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var cell := world_to_cell(get_local_mouse_position())
			try_remove_tower(cell)


func _is_buildable_cell(cell: Vector2i) -> bool:
	var t: int = _cells.get(cell, -1)
	return t == CellType.EMPTY or t == CellType.BOOST


func try_place_tower(cell: Vector2i, active_enemy_cells: Array[Vector2i] = []) -> bool:
	if not _cells.has(cell):
		return false
	if _cells[cell] == CellType.NO_BUILD:
		placement_rejected.emit(cell, "Зона запрета строительства!")
		return false
	if not _is_buildable_cell(cell):
		placement_rejected.emit(cell, "Клетка занята")
		return false

	if not pathfinding.can_place_tower(cell, spawns, core_cell, active_enemy_cells):
		placement_rejected.emit(cell, "Нельзя полностью заблокировать путь!")
		return false

	_cells[cell] = CellType.TOWER
	pathfinding.set_cell_solid(cell, true)
	var on_boost := _boost_set.has(cell)
	tower_placed.emit(cell, on_boost)
	_refresh_main_paths()
	_update_hover_preview()
	queue_redraw()
	return true


func try_remove_tower(cell: Vector2i) -> bool:
	if _cells.get(cell, -1) != CellType.TOWER:
		return false

	_cells[cell] = CellType.BOOST if _boost_set.has(cell) else CellType.EMPTY
	pathfinding.set_cell_solid(cell, false)
	tower_removed.emit(cell)
	_refresh_main_paths()
	_update_hover_preview()
	queue_redraw()
	return true


func world_to_cell(local_pos: Vector2) -> Vector2i:
	return Vector2i(floori(local_pos.x / cell_size.x), floori(local_pos.y / cell_size.y))


func cell_to_world_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * cell_size + cell_size * 0.5


func _update_hover_preview() -> void:
	if not _cells.has(_hover_cell):
		_can_place_hover = false
		_refresh_main_paths()
		return

	_can_place_hover = (
		_is_buildable_cell(_hover_cell)
		and pathfinding.can_place_tower(_hover_cell, spawns, core_cell)
	)

	if _can_place_hover:
		for i in spawns.size():
			_path_lines[i].points = pathfinding.preview_world_path(_hover_cell, spawns[i], core_cell)
			_path_lines[i].default_color = path_color
	elif _is_buildable_cell(_hover_cell) and not _can_place_hover:
		for line in _path_lines:
			line.default_color = invalid_hover_color
	else:
		_refresh_main_paths()


func _refresh_main_paths() -> void:
	var all_paths: Array[PackedVector2Array] = []
	for i in spawns.size():
		var p := pathfinding.get_world_path(spawns[i], core_cell)
		all_paths.append(p)
		if i < _path_lines.size():
			_path_lines[i].points = p
			_path_lines[i].default_color = path_color
	paths_updated.emit(all_paths)


func _rebuild_path_lines() -> void:
	for line in _path_lines:
		if is_instance_valid(line):
			line.queue_free()
	_path_lines.clear()

	for i in spawns.size():
		var line := Line2D.new()
		line.name = "PathPreviewLine_%d" % i
		line.width = 4.0
		line.default_color = path_color
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(line)
		_path_lines.append(line)


func _draw() -> void:
	var total_size := Vector2(grid_size) * cell_size
	draw_rect(Rect2(Vector2.ZERO, total_size), bg_color)

	for cell: Vector2i in _cells:
		var rect := Rect2(Vector2(cell) * cell_size, cell_size).grow(-2.0)
		match _cells[cell]:
			CellType.WALL:
				draw_rect(rect, wall_color)
			CellType.NO_BUILD:
				draw_rect(rect, no_build_color)
			CellType.BOOST:
				draw_rect(rect, boost_color)
				draw_rect(rect.grow(-10.0), Color("#10B981", 0.55), false, 2.0)
			CellType.SPAWN:
				draw_rect(rect, Color("#F97316", 0.78))
			CellType.CORE:
				draw_rect(rect, Color("#00E5FF", 0.85))
			CellType.TOWER:
				var tower_col := Color("#10B981") if _boost_set.has(cell) else Color("#3B82F6")
				draw_rect(rect, tower_col)

	for x in grid_size.x + 1:
		var px := x * cell_size.x
		draw_line(Vector2(px, 0.0), Vector2(px, total_size.y), grid_line_color, 1.0)
	for y in grid_size.y + 1:
		var py := y * cell_size.y
		draw_line(Vector2(0.0, py), Vector2(total_size.x, py), grid_line_color, 1.0)

	if _cells.has(_hover_cell):
		var hover_rect := Rect2(Vector2(_hover_cell) * cell_size, cell_size).grow(-2.0)
		var color := valid_hover_color if _can_place_hover else invalid_hover_color
		draw_rect(hover_rect, color)
