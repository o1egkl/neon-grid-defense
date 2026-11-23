class_name GridManager
extends Node2D

## Управляет игровой сеткой с фиксированными маршрутами, адаптивным масштабированием
## под любое окно, а также полной боевой симуляцией (волны, 7 типов врагов, 6 типов башен, VFX).

signal tower_place_requested(cell: Vector2i, on_boost: bool)
signal tower_remove_requested(cell: Vector2i, tower_id: String)
signal placement_rejected(cell: Vector2i, reason_key: String)
signal level_loaded(level_data: Dictionary)
signal enemy_killed(bounty: int)
signal core_damaged(remaining_cores: int)
signal wave_state_changed(wave_num: int, total_waves: int, active: bool)
signal wave_cleared(bonus_gold: int)
signal level_victory()
signal level_defeat()
signal sfx_requested(sfx_name: String)

enum CellType { EMPTY, WALL, PATH, BOOST, SPAWN, CORE, TOWER }

@export var grid_size := Vector2i(24, 14)
var cell_size := Vector2(48.0, 48.0)

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

var input_enabled: bool = false
var selected_tower_config: Dictionary = {}
var game_speed: float = 1.0
var cores_remaining: int = 10

var _enemy_catalog: Dictionary = {} # id -> Dictionary
var _cells: Dictionary = {}         # Vector2i -> CellType
var _placed_towers: Dictionary = {} # Vector2i -> Dictionary (runtime tower state)
var _boost_set: Dictionary = {}     # Vector2i -> bool
var _hover_cell := Vector2i(-1, -1)
var _can_place_hover: bool = false
var _path_lines: Array[Line2D] = []

# Combat runtime state
var _waves_data: Array = []
var _current_wave_idx: int = -1
var _wave_active: bool = false
var _wave_time: float = 0.0
var _spawn_queue: Array = [] # Array of {time, enemy_id, hp_mult, path_idx, elite}
var _enemies: Array = []     # Active enemy Dictionaries
var _projectiles: Array = [] # Active kinetic/cannon projectiles
var _vfx: Array = []         # Active beams, lightning, rings {type, ... , ttl, max_ttl}
var _core_flash: float = 0.0
var _ended: bool = false
var _round_robin_spawn: int = 0


func _ready() -> void:
	_load_enemy_catalog()
	SettingsManager.settings_changed.connect(_on_settings_changed)
	get_viewport().size_changed.connect(_fit_grid_to_viewport)
	_fit_grid_to_viewport()


func _load_enemy_catalog() -> void:
	var path := "res://data/enemies.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		for e in parsed.get("enemies", []):
			_enemy_catalog[str(e.get("id", ""))] = e


func _fit_grid_to_viewport() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	var top_bar_h: float = 52.0
	var bottom_bar_h: float = 132.0
	var margin_x: float = 24.0
	var avail_w: float = maxf(320.0, vp_size.x - margin_x * 2.0)
	var avail_h: float = maxf(240.0, vp_size.y - top_bar_h - bottom_bar_h)
	var side: float = floorf(minf(avail_w / float(grid_size.x), avail_h / float(grid_size.y)))
	side = clampf(side, 24.0, 60.0)
	cell_size = Vector2(side, side)

	var total: Vector2 = Vector2(grid_size) * cell_size
	position = Vector2(
		floorf((vp_size.x - total.x) * 0.5),
		floorf(top_bar_h + (avail_h - total.y) * 0.5)
	)
	_rebuild_path_lines()
	queue_redraw()


func _on_settings_changed() -> void:
	for line in _path_lines:
		if is_instance_valid(line):
			line.visible = SettingsManager.show_path_preview
	queue_redraw()


func set_selected_tower(tower_cfg: Dictionary) -> void:
	selected_tower_config = tower_cfg
	queue_redraw()


func is_wave_active() -> bool:
	return _wave_active


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
	cores_remaining = int(parsed.get("cores_count", 10))
	_waves_data = parsed.get("waves", [])

	fixed_paths.clear()
	for raw_p in parsed.get("paths", []):
		fixed_paths.append(_parse_vec2i_array(raw_p))

	_hover_cell = Vector2i(-1, -1)
	_placed_towers.clear()
	_enemies.clear()
	_projectiles.clear()
	_vfx.clear()
	_spawn_queue.clear()
	_current_wave_idx = -1
	_wave_active = false
	_ended = false
	_core_flash = 0.0

	_init_grid()
	_fit_grid_to_viewport()
	level_loaded.emit(current_level_data)
	wave_state_changed.emit(0, _waves_data.size(), false)
	return true


func start_next_wave() -> bool:
	if _wave_active or _ended:
		return false
	if _current_wave_idx + 1 >= _waves_data.size():
		return false

	_current_wave_idx += 1
	var w_data: Dictionary = _waves_data[_current_wave_idx]
	var hp_mult: float = float(w_data.get("hp_multiplier", 1.0))
	_spawn_queue.clear()
	_wave_time = 0.0

	for grp in w_data.get("groups", []):
		var eid: String = str(grp.get("enemy", "trooper"))
		var cnt: int = int(grp.get("count", 5))
		var interval: float = float(grp.get("interval", 0.8))
		var delay: float = float(grp.get("delay", 0.0))
		var elite: bool = bool(grp.get("elite", false))
		for i in cnt:
			var pidx: int = _round_robin_spawn % max(fixed_paths.size(), 1)
			_round_robin_spawn += 1
			_spawn_queue.append({
				"time": delay + float(i) * interval,
				"enemy_id": eid,
				"hp_mult": hp_mult * (1.8 if elite else 1.0),
				"path_idx": pidx,
				"elite": elite
			})

	_spawn_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["time"]) < float(b["time"])
	)
	_wave_active = true
	sfx_requested.emit("wave")
	wave_state_changed.emit(_current_wave_idx + 1, _waves_data.size(), true)
	return true


func _process(delta: float) -> void:
	if _core_flash > 0.0:
		_core_flash = maxf(0.0, _core_flash - delta * 2.5)

	var dt: float = delta * game_speed
	var need_redraw: bool = (_core_flash > 0.0) or not _vfx.is_empty() or not _projectiles.is_empty() or not _enemies.is_empty()

	if _wave_active and not _ended:
		_wave_time += dt
		_process_spawns()
		_process_enemies(dt)
		_process_towers(dt)
		_process_projectiles(dt)
		_check_wave_completion()
		need_redraw = true

	_process_vfx(delta)

	if need_redraw:
		queue_redraw()


func _process_spawns() -> void:
	while not _spawn_queue.is_empty() and float(_spawn_queue[0]["time"]) <= _wave_time:
		var item: Dictionary = _spawn_queue.pop_front()
		_spawn_enemy(item)


func _spawn_enemy(item: Dictionary) -> void:
	var eid: String = str(item["enemy_id"])
	var base: Dictionary = _enemy_catalog.get(eid, {"hp": 80, "shield": 0, "armor": 0, "speed": 90, "bounty": 8, "is_flying": false})
	var hp_mult: float = float(item["hp_mult"])
	var pidx: int = int(item["path_idx"])
	var path_cells: Array = fixed_paths[pidx] if pidx < fixed_paths.size() else [core_cell]
	var start_pos: Vector2 = cell_to_world_center(path_cells[0])
	var max_hp: float = float(base.get("hp", 80)) * hp_mult
	var max_shield: float = float(base.get("shield", 0)) * hp_mult

	_enemies.append({
		"id": eid,
		"pos": start_pos,
		"path_idx": pidx,
		"wp_idx": 1,
		"progress": 0.0,
		"hp": max_hp,
		"max_hp": max_hp,
		"shield": max_shield,
		"max_shield": max_shield,
		"armor": float(base.get("armor", 0)),
		"speed": float(base.get("speed", 90)) * (cell_size.x / 54.0),
		"bounty": int(base.get("bounty", 8)),
		"is_flying": bool(base.get("is_flying", false)),
		"elite": bool(item.get("elite", false)),
		"slow_timer": 0.0,
		"slow_factor": 1.0,
		"medic_cd": 2.0,
		"shield_regen_cd": 0.0
	})


func _process_enemies(dt: float) -> void:
	var core_pos: Vector2 = cell_to_world_center(core_cell)
	var i: int = _enemies.size() - 1
	while i >= 0:
		var e: Dictionary = _enemies[i]

		# Slow debuff timer
		if float(e["slow_timer"]) > 0.0:
			e["slow_timer"] = float(e["slow_timer"]) - dt
			if float(e["slow_timer"]) <= 0.0:
				e["slow_factor"] = 1.0

		# Shield regen out of combat
		if float(e["max_shield"]) > 0.0:
			e["shield_regen_cd"] = maxf(0.0, float(e["shield_regen_cd"]) - dt)
			if float(e["shield_regen_cd"]) <= 0.0 and float(e["shield"]) < float(e["max_shield"]):
				e["shield"] = minf(float(e["max_shield"]), float(e["shield"]) + float(e["max_shield"]) * 0.12 * dt)

		# Medic aura heal
		if str(e["id"]) == "medic":
			e["medic_cd"] = float(e["medic_cd"]) - dt
			if float(e["medic_cd"]) <= 0.0:
				e["medic_cd"] = 2.5
				for ally in _enemies:
					if (ally["pos"] as Vector2).distance_to(e["pos"]) <= cell_size.x * 2.2:
						ally["hp"] = minf(float(ally["max_hp"]), float(ally["hp"]) + float(ally["max_hp"]) * 0.10)

		var spd: float = float(e["speed"]) * float(e["slow_factor"])
		var reached_core: bool = false

		if bool(e["is_flying"]):
			var dir: Vector2 = core_pos - (e["pos"] as Vector2)
			var dist: float = dir.length()
			if dist <= spd * dt + 4.0:
				reached_core = true
			else:
				e["pos"] = (e["pos"] as Vector2) + dir.normalized() * spd * dt
				e["progress"] = float(e["progress"]) + spd * dt
		else:
			var path_cells: Array = fixed_paths[int(e["path_idx"])]
			var wp_idx: int = int(e["wp_idx"])
			if wp_idx >= path_cells.size():
				reached_core = true
			else:
				var target: Vector2 = cell_to_world_center(path_cells[wp_idx])
				var dir: Vector2 = target - (e["pos"] as Vector2)
				var dist: float = dir.length()
				if dist <= spd * dt:
					e["pos"] = target
					e["wp_idx"] = wp_idx + 1
					e["progress"] = float(e["progress"]) + dist
					if int(e["wp_idx"]) >= path_cells.size():
						reached_core = true
				else:
					e["pos"] = (e["pos"] as Vector2) + dir.normalized() * spd * dt
					e["progress"] = float(e["progress"]) + spd * dt

		if reached_core:
			_enemies.remove_at(i)
			cores_remaining = max(0, cores_remaining - 1)
			_core_flash = 1.0
			sfx_requested.emit("core_hit")
			core_damaged.emit(cores_remaining)
			if cores_remaining <= 0 and not _ended:
				_ended = true
				_wave_active = false
				level_defeat.emit()
				return
		i -= 1


func _process_towers(dt: float) -> void:
	var scale_factor: float = cell_size.x / 54.0
	for cell: Vector2i in _placed_towers:
		var t: Dictionary = _placed_towers[cell]
		t["cooldown"] = maxf(0.0, float(t["cooldown"]) - dt)
		if float(t["cooldown"]) > 0.0:
			continue

		var t_pos: Vector2 = cell_to_world_center(cell)
		var rng: float = float(t.get("range", 180.0)) * scale_factor
		var target_idx: int = _find_target_index(t_pos, rng)
		if target_idx < 0:
			continue

		var fire_rate: float = maxf(0.1, float(t.get("fire_rate", 1.0)))
		t["cooldown"] = 1.0 / fire_rate
		var dmg: float = float(t.get("damage", 12.0)) * (1.2 if _boost_set.has(cell) else 1.0)
		var tid: String = str(t.get("id", "pulse"))
		var target: Dictionary = _enemies[target_idx]
		t["aim_angle"] = (target["pos"] as Vector2 - t_pos).angle()

		_fire_tower(tid, t, t_pos, target_idx, dmg, scale_factor)


func _find_target_index(origin: Vector2, rng: float) -> int:
	var best_idx: int = -1
	var best_prog: float = -1.0
	for i in _enemies.size():
		var e: Dictionary = _enemies[i]
		if (e["pos"] as Vector2).distance_to(origin) <= rng:
			if float(e["progress"]) > best_prog:
				best_prog = float(e["progress"])
				best_idx = i
	return best_idx


func _fire_tower(tid: String, cfg: Dictionary, origin: Vector2, target_idx: int, dmg: float, scale_factor: float) -> void:
	var target: Dictionary = _enemies[target_idx]
	var t_pos: Vector2 = target["pos"]
	var col := Color(str(cfg.get("color", "#00E5FF")))

	match tid:
		"pulse":
			sfx_requested.emit("pulse")
			_projectiles.append({
				"pos": origin, "target_pos": t_pos, "speed": 560.0 * scale_factor,
				"damage": dmg, "damage_type": "kinetic", "aoe": 0.0, "color": col
			})
		"cannon":
			sfx_requested.emit("cannon")
			_projectiles.append({
				"pos": origin, "target_pos": t_pos, "speed": 360.0 * scale_factor,
				"damage": dmg, "damage_type": "explosive",
				"aoe": float(cfg.get("aoe_radius", 72.0)) * scale_factor, "color": col
			})
		"cryo":
			sfx_requested.emit("cryo")
			var rng: float = float(cfg.get("range", 170.0)) * scale_factor
			var slow_f: float = 1.0 - float(cfg.get("slow_factor", 0.4))
			_vfx.append({"type": "ring", "pos": origin, "radius": rng, "color": col, "ttl": 0.25, "max_ttl": 0.25})
			var i: int = _enemies.size() - 1
			while i >= 0:
				var e: Dictionary = _enemies[i]
				if (e["pos"] as Vector2).distance_to(origin) <= rng:
					e["slow_factor"] = minf(float(e["slow_factor"]), slow_f)
					e["slow_timer"] = 2.6
					_damage_enemy_at(i, dmg, "cryo")
				i -= 1
		"tesla":
			sfx_requested.emit("tesla")
			var max_chains: int = int(cfg.get("chain_count", 3))
			var hit_indices: Array[int] = [target_idx]
			var last_pos: Vector2 = t_pos
			var chain_pts := PackedVector2Array([origin, t_pos])
			for _c in range(max_chains - 1):
				var next_i: int = -1
				var best_d: float = cell_size.x * 3.0
				for j in _enemies.size():
					if j in hit_indices:
						continue
					var d: float = (_enemies[j]["pos"] as Vector2).distance_to(last_pos)
					if d < best_d:
						best_d = d
						next_i = j
				if next_i >= 0:
					hit_indices.append(next_i)
					last_pos = _enemies[next_i]["pos"]
					chain_pts.append(last_pos)
				else:
					break
			_vfx.append({"type": "chain", "points": chain_pts, "color": col, "ttl": 0.16, "max_ttl": 0.16})
			hit_indices.sort()
			hit_indices.reverse()
			for hi in hit_indices:
				if hi < _enemies.size():
					_damage_enemy_at(hi, dmg, "electric")
		"laser":
			sfx_requested.emit("laser")
			_vfx.append({"type": "beam", "from": origin, "to": t_pos, "width": 3.5, "color": col, "ttl": 0.11, "max_ttl": 0.11})
			_damage_enemy_at(target_idx, dmg, "thermal")
		"railgun":
			sfx_requested.emit("railgun")
			_vfx.append({"type": "beam", "from": origin, "to": t_pos, "width": 5.0, "color": col, "ttl": 0.22, "max_ttl": 0.22})
			_damage_enemy_at(target_idx, dmg, "pierce")


func _process_projectiles(dt: float) -> void:
	var i: int = _projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = _projectiles[i]
		var pos: Vector2 = p["pos"]
		var dest: Vector2 = p["target_pos"]
		var dir: Vector2 = dest - pos
		var dist: float = dir.length()
		var step: float = float(p["speed"]) * dt
		if dist <= step + 6.0:
			var aoe: float = float(p["aoe"])
			if aoe > 0.0:
				_vfx.append({"type": "ring", "pos": dest, "radius": aoe, "color": p["color"], "ttl": 0.22, "max_ttl": 0.22})
				var j: int = _enemies.size() - 1
				while j >= 0:
					if (_enemies[j]["pos"] as Vector2).distance_to(dest) <= aoe:
						_damage_enemy_at(j, float(p["damage"]), str(p["damage_type"]))
					j -= 1
			else:
				var hit_i: int = _find_closest_enemy(dest, cell_size.x * 0.9)
				if hit_i >= 0:
					_damage_enemy_at(hit_i, float(p["damage"]), str(p["damage_type"]))
			_projectiles.remove_at(i)
		else:
			p["pos"] = pos + dir.normalized() * step
		i -= 1


func _find_closest_enemy(pos: Vector2, max_dist: float) -> int:
	var best_i: int = -1
	var best_d: float = max_dist
	for i in _enemies.size():
		var d: float = (_enemies[i]["pos"] as Vector2).distance_to(pos)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func _damage_enemy_at(idx: int, raw_dmg: float, dmg_type: String) -> void:
	if idx < 0 or idx >= _enemies.size():
		return
	var e: Dictionary = _enemies[idx]
	e["shield_regen_cd"] = 3.0
	var remaining: float = raw_dmg

	# Shield absorbs first (electric deals 2x to shields)
	if float(e["shield"]) > 0.0:
		var shield_mult: float = 2.0 if dmg_type == "electric" else 1.0
		var shield_dmg: float = remaining * shield_mult
		if float(e["shield"]) >= shield_dmg:
			e["shield"] = float(e["shield"]) - shield_dmg
			return
		else:
			remaining -= float(e["shield"]) / shield_mult
			e["shield"] = 0.0

	# Armor mitigation (pierce and thermal ignore armor)
	var armor: float = float(e["armor"])
	if dmg_type == "pierce" or dmg_type == "thermal":
		armor = 0.0
	var final_dmg: float = maxf(1.0, remaining - armor * 0.6)
	e["hp"] = float(e["hp"]) - final_dmg

	if float(e["hp"]) <= 0.0:
		var bounty: int = int(e["bounty"])
		var death_pos: Vector2 = e["pos"]
		var eid: String = str(e["id"])
		var pidx: int = int(e["path_idx"])
		var wp_idx: int = int(e["wp_idx"])
		var prog: float = float(e["progress"])
		_enemies.remove_at(idx)
		_vfx.append({"type": "ring", "pos": death_pos, "radius": cell_size.x * 0.55, "color": Color("#F97316"), "ttl": 0.18, "max_ttl": 0.18})
		enemy_killed.emit(bounty)

		# Splitter spawns 2 swarm units on death
		if eid == "splitter":
			for offset_x in [-8.0, 8.0]:
				var sw: Dictionary = _enemy_catalog.get("swarm", {"hp": 35, "speed": 140, "bounty": 4})
				_enemies.append({
					"id": "swarm",
					"pos": death_pos + Vector2(offset_x, 0.0),
					"path_idx": pidx,
					"wp_idx": wp_idx,
					"progress": prog,
					"hp": float(sw.get("hp", 35)),
					"max_hp": float(sw.get("hp", 35)),
					"shield": 0.0,
					"max_shield": 0.0,
					"armor": 0.0,
					"speed": float(sw.get("speed", 140)) * (cell_size.x / 54.0),
					"bounty": int(sw.get("bounty", 4)),
					"is_flying": false,
					"elite": false,
					"slow_timer": 0.0,
					"slow_factor": 1.0,
					"medic_cd": 99.0,
					"shield_regen_cd": 0.0
				})


func _process_vfx(delta: float) -> void:
	var i: int = _vfx.size() - 1
	while i >= 0:
		_vfx[i]["ttl"] = float(_vfx[i]["ttl"]) - delta
		if float(_vfx[i]["ttl"]) <= 0.0:
			_vfx.remove_at(i)
		i -= 1


func _check_wave_completion() -> void:
	if _spawn_queue.is_empty() and _enemies.is_empty() and _wave_active:
		_wave_active = false
		var w_data: Dictionary = _waves_data[_current_wave_idx]
		var bonus: int = int(w_data.get("bonus_gold", 20))
		wave_cleared.emit(bonus)
		wave_state_changed.emit(_current_wave_idx + 1, _waves_data.size(), false)
		if _current_wave_idx + 1 >= _waves_data.size():
			_ended = true
			level_victory.emit()


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
		var cell: Vector2i = world_to_cell(get_local_mouse_position())
		if cell != _hover_cell:
			_hover_cell = cell
			_can_place_hover = _is_buildable_cell(_hover_cell)
			queue_redraw()

	elif event is InputEventMouseButton and event.pressed:
		var cell: Vector2i = world_to_cell(get_local_mouse_position())
		if not _cells.has(cell):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(cell)


func _is_buildable_cell(cell: Vector2i) -> bool:
	var t: int = int(_cells.get(cell, -1))
	return t == CellType.EMPTY or t == CellType.BOOST


func _handle_left_click(cell: Vector2i) -> void:
	var t: int = int(_cells.get(cell, -1))
	if t == CellType.PATH or t == CellType.SPAWN or t == CellType.CORE:
		placement_rejected.emit(cell, "msg_on_road")
		return
	if not _is_buildable_cell(cell):
		placement_rejected.emit(cell, "msg_occupied")
		return
	tower_place_requested.emit(cell, _boost_set.has(cell))


func _handle_right_click(cell: Vector2i) -> void:
	if int(_cells.get(cell, -1)) != CellType.TOWER:
		return
	var cfg: Dictionary = _placed_towers.get(cell, {})
	tower_remove_requested.emit(cell, str(cfg.get("id", "pulse")))


func commit_place_tower(cell: Vector2i, tower_cfg: Dictionary) -> void:
	_cells[cell] = CellType.TOWER
	var runtime_cfg: Dictionary = tower_cfg.duplicate()
	runtime_cfg["cooldown"] = 0.0
	runtime_cfg["aim_angle"] = 0.0
	_placed_towers[cell] = runtime_cfg
	_can_place_hover = false
	sfx_requested.emit("place")
	queue_redraw()


func commit_remove_tower(cell: Vector2i) -> void:
	_cells[cell] = CellType.BOOST if _boost_set.has(cell) else CellType.EMPTY
	_placed_towers.erase(cell)
	_can_place_hover = _is_buildable_cell(_hover_cell)
	sfx_requested.emit("sell")
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
		line.width = maxf(2.5, cell_size.x * 0.07)
		line.default_color = path_color
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.visible = SettingsManager.show_path_preview
		add_child(line)
		_path_lines.append(line)


func _draw() -> void:
	var total_size: Vector2 = Vector2(grid_size) * cell_size
	draw_rect(Rect2(Vector2.ZERO, total_size), bg_color)

	for cell: Vector2i in _cells:
		var rect := Rect2(Vector2(cell) * cell_size, cell_size)
		var inner: Rect2 = rect.grow(-2.0)
		match int(_cells[cell]):
			CellType.PATH:
				draw_rect(rect, road_color)
				draw_rect(rect.grow(-1.0), road_border_color, false, 1.0)
			CellType.WALL:
				draw_rect(inner, wall_color)
				draw_rect(inner.grow(-5.0), Color("#334155"), false, 1.5)
			CellType.BOOST:
				draw_rect(inner, boost_color)
				draw_rect(inner.grow(-7.0), Color("#10B981", 0.65), false, 2.0)
			CellType.SPAWN:
				draw_rect(inner, Color("#F97316", 0.85))
			CellType.CORE:
				var center: Vector2 = cell_to_world_center(cell)
				var core_col: Color = Color("#FF3B5C") if _core_flash > 0.2 else Color("#00E5FF")
				draw_rect(inner, Color(core_col.r, core_col.g, core_col.b, 0.25))
				draw_circle(center, cell_size.x * 0.36, Color(core_col.r, core_col.g, core_col.b, 0.92))
				draw_arc(center, cell_size.x * 0.45, 0.0, TAU, 24, Color(core_col.r, core_col.g, core_col.b, 0.65), 2.0)
			CellType.TOWER:
				_draw_tower_cell(cell, inner)

	if SettingsManager.show_grid_lines:
		for x in grid_size.x + 1:
			var px: float = float(x) * cell_size.x
			draw_line(Vector2(px, 0.0), Vector2(px, total_size.y), grid_line_color, 1.0)
		for y in grid_size.y + 1:
			var py: float = float(y) * cell_size.y
			draw_line(Vector2(0.0, py), Vector2(total_size.x, py), grid_line_color, 1.0)

	# Enemies
	for e in _enemies:
		_draw_enemy(e)

	# Projectiles
	for p in _projectiles:
		draw_circle(p["pos"], maxf(3.0, cell_size.x * 0.09), p["color"])

	# VFX
	for v in _vfx:
		var alpha: float = clampf(float(v["ttl"]) / maxf(float(v["max_ttl"]), 0.01), 0.0, 1.0)
		var col: Color = v["color"]
		var c_fade := Color(col.r, col.g, col.b, alpha)
		match str(v["type"]):
			"beam":
				draw_line(v["from"], v["to"], c_fade, float(v["width"]))
				draw_line(v["from"], v["to"], Color(1, 1, 1, alpha * 0.8), float(v["width"]) * 0.4)
			"chain":
				var pts: PackedVector2Array = v["points"]
				for k in range(pts.size() - 1):
					draw_line(pts[k], pts[k + 1], c_fade, 3.0)
			"ring":
				var r_now: float = float(v["radius"]) * (1.0 - alpha * 0.35)
				draw_arc(v["pos"], r_now, 0.0, TAU, 32, c_fade, 2.2)

	# Hover preview + range circle
	if input_enabled and _cells.has(_hover_cell):
		var hover_rect := Rect2(Vector2(_hover_cell) * cell_size, cell_size).grow(-2.0)
		var hcol: Color = valid_hover_color if _can_place_hover else invalid_hover_color
		draw_rect(hover_rect, hcol)
		if _can_place_hover and not selected_tower_config.is_empty():
			var rng: float = float(selected_tower_config.get("range", 180.0)) * (cell_size.x / 54.0)
			var t_col := Color(str(selected_tower_config.get("color", "#00E5FF")))
			var center: Vector2 = cell_to_world_center(_hover_cell)
			draw_circle(center, rng, Color(t_col.r, t_col.g, t_col.b, 0.10))
			draw_arc(center, rng, 0.0, TAU, 48, Color(t_col.r, t_col.g, t_col.b, 0.65), 1.8)


func _draw_tower_cell(cell: Vector2i, rect: Rect2) -> void:
	var cfg: Dictionary = _placed_towers.get(cell, {})
	var col := Color(str(cfg.get("color", "#3B82F6")))
	var center: Vector2 = cell_to_world_center(cell)
	var r: float = cell_size.x * 0.33
	var ang: float = float(cfg.get("aim_angle", 0.0))
	var dir := Vector2(cos(ang), sin(ang))

	draw_rect(rect, Color("#111827"))
	draw_rect(rect, Color("#10B981") if _boost_set.has(cell) else col.darkened(0.25), false, 2.0)

	match str(cfg.get("id", "pulse")):
		"pulse":
			draw_circle(center, r * 0.72, col)
			draw_line(center, center + dir * r * 1.15, Color.WHITE, 3.0)
		"cannon":
			draw_rect(Rect2(center - Vector2(r * 0.72, r * 0.72), Vector2(r * 1.44, r * 1.44)), col)
			draw_line(center, center + dir * r * 1.1, Color("#0B0F17"), 4.0)
		"cryo":
			var pts := PackedVector2Array([
				center + Vector2(0, -r), center + Vector2(r, 0),
				center + Vector2(0, r), center + Vector2(-r, 0)
			])
			draw_colored_polygon(pts, col)
		"tesla":
			draw_circle(center, r * 0.52, col)
			draw_arc(center, r * 0.88, 0.0, TAU, 16, col.lightened(0.35), 2.0)
		"laser":
			draw_circle(center, r * 0.62, col)
			draw_line(center, center + dir * r * 1.2, Color("#FCA5A5"), 2.5)
		"railgun":
			draw_circle(center, r * 0.58, col.darkened(0.2))
			draw_line(center - dir * r * 0.5, center + dir * r * 1.35, col, 4.0)
			draw_line(center, center + dir * r * 1.35, Color.WHITE, 1.5)
		_:
			draw_circle(center, r * 0.7, col)


func _draw_enemy(e: Dictionary) -> void:
	var pos: Vector2 = e["pos"]
	var eid: String = str(e["id"])
	var r: float = cell_size.x * (0.28 if bool(e["elite"]) else 0.22)
	var col := Color("#EF4444")
	match eid:
		"swarm":
			r *= 0.78
			col = Color("#FB7185")
		"armored":
			r *= 1.22
			col = Color("#94A3B8")
		"shielded":
			col = Color("#A855F7")
		"medic":
			col = Color("#22C55E")
		"splitter":
			col = Color("#F59E0B")
		"drone":
			col = Color("#38BDF8")

	if float(e["slow_timer"]) > 0.0:
		col = col.lerp(Color("#67E8F9"), 0.55)

	if eid == "armored":
		draw_rect(Rect2(pos - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), col)
	elif eid == "drone":
		var tri := PackedVector2Array([
			pos + Vector2(r * 1.2, 0), pos + Vector2(-r, -r), pos + Vector2(-r, r)
		])
		draw_colored_polygon(tri, col)
	else:
		draw_circle(pos, r, col)

	if float(e["shield"]) > 0.0:
		draw_arc(pos, r + 3.0, 0.0, TAU, 20, Color("#38BDF8", 0.85), 2.0)

	# Health bar above enemy
	var hp_ratio: float = clampf(float(e["hp"]) / maxf(float(e["max_hp"]), 1.0), 0.0, 1.0)
	if hp_ratio < 0.999 or float(e["max_shield"]) > 0.0:
		var bw: float = r * 2.4
		var bh: float = 4.0
		var bp := pos + Vector2(-bw * 0.5, -r - 8.0)
		draw_rect(Rect2(bp, Vector2(bw, bh)), Color("#0F172A"))
		draw_rect(Rect2(bp, Vector2(bw * hp_ratio, bh)), Color("#22C55E") if hp_ratio > 0.4 else Color("#EF4444"))
