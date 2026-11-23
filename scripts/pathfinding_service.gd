class_name PathfindingService
extends RefCounted

## Сервис поиска пути на сетке для Tower Defense с механикой Mazing.
## Использует нативный AStarGrid2D (C++ под капотом) без срезки углов.

var _astar := AStarGrid2D.new()
var _grid_size: Vector2i
var _cell_size: Vector2


func setup(grid_size: Vector2i, cell_size: Vector2, walls: Array[Vector2i] = []) -> void:
	_grid_size = grid_size
	_cell_size = cell_size

	_astar.region = Rect2i(Vector2i.ZERO, _grid_size)
	_astar.cell_size = _cell_size
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()

	for wall in walls:
		if _is_in_bounds(wall):
			_astar.set_point_solid(wall, true)


func set_cell_solid(cell: Vector2i, solid: bool) -> void:
	if _is_in_bounds(cell):
		_astar.set_point_solid(cell, solid)


func is_cell_solid(cell: Vector2i) -> bool:
	if not _is_in_bounds(cell):
		return true
	return _astar.is_point_solid(cell)


## Проверяет, можно ли поставить башню в клетку без полного перекрытия пути
## для всех точек спавна и уже заспавненных врагов.
func can_place_tower(
	cell: Vector2i,
	spawns: Array[Vector2i],
	core: Vector2i,
	active_enemy_cells: Array[Vector2i] = []
) -> bool:
	if not _is_in_bounds(cell) or _astar.is_point_solid(cell):
		return false
	if cell == core or cell in spawns or cell in active_enemy_cells:
		return false

	_astar.set_point_solid(cell, true)

	var valid := true
	for spawn in spawns:
		if _astar.get_id_path(spawn, core).is_empty():
			valid = false
			break

	if valid:
		for enemy_cell in active_enemy_cells:
			if _astar.get_id_path(enemy_cell, core).is_empty():
				valid = false
				break

	_astar.set_point_solid(cell, false)
	return valid


func get_world_path(from_cell: Vector2i, to_cell: Vector2i) -> PackedVector2Array:
	if not _is_in_bounds(from_cell) or not _is_in_bounds(to_cell):
		return PackedVector2Array()

	var id_path: Array[Vector2i] = _astar.get_id_path(from_cell, to_cell)
	var world_points := PackedVector2Array()
	world_points.resize(id_path.size())

	var half_cell := _cell_size * 0.5
	for i in id_path.size():
		world_points[i] = Vector2(id_path[i]) * _cell_size + half_cell

	return world_points


func preview_world_path(
	hover_cell: Vector2i,
	spawn: Vector2i,
	core: Vector2i
) -> PackedVector2Array:
	if not _is_in_bounds(hover_cell) or _astar.is_point_solid(hover_cell):
		return get_world_path(spawn, core)

	_astar.set_point_solid(hover_cell, true)
	var preview := get_world_path(spawn, core)
	_astar.set_point_solid(hover_cell, false)
	return preview


func _is_in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= 0 and cell.x < _grid_size.x
		and cell.y >= 0 and cell.y < _grid_size.y
	)
