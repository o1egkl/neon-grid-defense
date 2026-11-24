extends Node3D

## 3D Изометрический движок Neon Grid Defense v15 (Godot 4.3 GL Compatibility):
## - 5 уровней апгрейда башен (линейно +20% за уровень: x1.0 / x1.2 / x1.4 / x1.6 / x1.8 + Overdrive на ур. 5)
## - 3D-эволюция башни (кольца, энерго-стабилизаторы, золотой ореол на ур. 5) + двойное кольцо радиуса при инспекции
## - 6 поворотных 3D-башен на 360°, скруглённые Bezier-траектории и 7 анимированных 3D-врагов

signal tower_place_requested(cell: Vector2i, on_boost: bool)
signal tower_remove_requested(cell: Vector2i, refund: int)
signal tower_inspected(cell: Vector2i, info: Dictionary)
signal tower_inspection_cleared()
signal build_preview_changed(cell: Vector2i, on_boost: bool)
signal build_preview_cleared()
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

const TILE_SIZE: float = 1.0
const PX_TO_WORLD: float = 1.0 / 54.0
const MAX_TOWER_LEVEL: int = 5
const UPGRADE_COST_MULTS: Array[float] = [0.0, 0.75, 1.10, 1.60, 2.20]

var grid_size := Vector2i(24, 14)
var current_level_data: Dictionary = {}
var spawns: Array[Vector2i] = []
var core_cell := Vector2i(23, 6)
var fixed_paths: Array = []
var smooth_paths: Array = []
var walls: Array[Vector2i] = []
var boost_tiles: Array[Vector2i] = []

var input_enabled: bool = false
var selected_tower_config: Dictionary = {}
var inspected_cell := Vector2i(-1, -1)
var pending_build_cell := Vector2i(-1, -1)
var _ghost_root: Node3D = null
var game_speed: float = 1.0
var cores_remaining: int = 10

var _enemy_catalog: Dictionary = {}
var _cells: Dictionary = {}
var _placed_towers: Dictionary = {}
var _boost_set: Dictionary = {}
var _hover_cell := Vector2i(-1, -1)
var _can_place_hover: bool = false

# 3D scene containers
var _camera: Camera3D
var _board_root: Node3D
var _route_root: Node3D
var _towers_root: Node3D
var _enemies_root: Node3D
var _fx_root: Node3D
var _hover_box: MeshInstance3D
var _hover_mat: StandardMaterial3D
var _range_ring: MeshInstance3D
var _range_mat: StandardMaterial3D
var _next_range_ring: Node3D
var _next_range_mat: StandardMaterial3D
var _last_ring_r: float = -1.0
var _last_next_ring_r: float = -1.0
var _core_sphere: MeshInstance3D
var _core_ring_a: MeshInstance3D
var _core_ring_b: MeshInstance3D
var _core_light: OmniLight3D
var _core_mat: StandardMaterial3D
var _outline_mat: StandardMaterial3D

# Combat runtime
var _waves_data: Array = []
var _current_wave_idx: int = -1
var _wave_active: bool = false
var _wave_time: float = 0.0
var _spawn_queue: Array = []
var _enemies: Array = []
var _projectiles: Array = []
var _vfx: Array = []
var _float_texts: Array = []
var _core_flash: float = 0.0
var _ended: bool = false
var _round_robin_spawn: int = 0
var _anim_time: float = 0.0

# Camera Zoom & Pan (Desktop Wheel + MMB/WASD + Android 2-Finger Pinch)
var _base_cam_dist: float = 25.0
var _zoom_factor: float = 1.0
var _target_zoom: float = 1.0
var _pan_offset := Vector3.ZERO
var _mmb_dragging: bool = false
var _lmb_down: bool = false
var _lmb_dragging: bool = false
var _lmb_down_pos := Vector2.ZERO
var _touches: Dictionary = {} # finger_idx -> Vector2
var _prev_pinch_dist: float = 0.0
var _prev_pinch_center := Vector2.ZERO
var _pinch_lock_timer: float = 0.0


func _ready() -> void:
	_load_enemy_catalog()
	_setup_environment_and_camera()
	_setup_containers()
	SettingsManager.settings_changed.connect(_on_settings_changed)
	get_viewport().size_changed.connect(_update_camera_fit)


func _load_enemy_catalog() -> void:
	var path := "res://data/enemies.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		for e in parsed.get("enemies", []):
			_enemy_catalog[str(e.get("id", ""))] = e


func _setup_environment_and_camera() -> void:
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.albedo_color = Color("#04070E")
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_mat.grow = true
	_outline_mat.grow_amount = 0.026

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#050911")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#273D5C")
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.20
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#EAF4FF")
	sun.light_energy = 1.55
	sun.rotation_degrees = Vector3(-54.0, 32.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#00C8EA")
	rim.light_energy = 0.65
	rim.rotation_degrees = Vector3(-28.0, -145.0, 0.0)
	add_child(rim)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 34.0
	_camera.near = 0.5
	_camera.far = 180.0
	add_child(_camera)
	_camera.current = true


func _setup_containers() -> void:
	_board_root = Node3D.new()
	add_child(_board_root)
	_route_root = Node3D.new()
	add_child(_route_root)
	_towers_root = Node3D.new()
	add_child(_towers_root)
	_enemies_root = Node3D.new()
	add_child(_enemies_root)
	_fx_root = Node3D.new()
	add_child(_fx_root)

	_hover_box = MeshInstance3D.new()
	var hmesh := BoxMesh.new()
	hmesh.size = Vector3(0.94, 0.08, 0.94)
	_hover_box.mesh = hmesh
	_hover_mat = _make_mat(Color("#00E5FF"), 1.6, 0.35)
	_hover_box.material_override = _hover_mat
	_hover_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover_box.visible = false
	add_child(_hover_box)

	_range_ring = MeshInstance3D.new()
	var rmesh := TorusMesh.new()
	rmesh.inner_radius = 0.96
	rmesh.outer_radius = 1.0
	rmesh.rings = 48
	rmesh.ring_segments = 8
	_range_ring.mesh = rmesh
	_range_mat = _make_mat(Color("#00E5FF"), 2.0, 0.75)
	_range_ring.material_override = _range_mat
	_range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_range_ring.visible = false
	add_child(_range_ring)

	_next_range_ring = Node3D.new()
	_next_range_mat = _make_mat(Color("#22C55E"), 2.2, 0.72)
	_next_range_ring.visible = false
	add_child(_next_range_ring)


func _update_camera_fit() -> void:
	if not _camera:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = maxf(vp.x / maxf(vp.y, 1.0), 0.5)
	var half_w: float = (float(grid_size.x) + 1.4) * 0.5
	var req_half_h_w: float = half_w / aspect
	var req_half_h_z: float = (float(grid_size.y) + 2.8) * 0.5 * 0.848
	var req_half_h: float = maxf(req_half_h_w, req_half_h_z)
	_base_cam_dist = req_half_h / maxf(tan(deg_to_rad(_camera.fov * 0.5)), 0.1)
	_apply_camera_transform()


func _apply_camera_transform() -> void:
	if not _camera:
		return
	var pan_mult: float = clampf(0.85 - _zoom_factor * 0.40, 0.35, 0.56)
	var max_px: float = float(grid_size.x) * pan_mult
	var max_pz: float = float(grid_size.y) * (pan_mult + 0.04)
	_pan_offset.x = clampf(_pan_offset.x, -max_px, max_px)
	_pan_offset.z = clampf(_pan_offset.z, -max_pz, max_pz)
	var dist: float = _base_cam_dist * _zoom_factor
	var pitch_rad: float = deg_to_rad(58.0)
	var offset := Vector3(0.0, sin(pitch_rad) * dist, cos(pitch_rad) * dist)
	var center := Vector3(float(grid_size.x) * 0.5, 0.0, float(grid_size.y) * 0.5 + 0.35) + _pan_offset
	_camera.look_at_from_position(center + offset, center, Vector3.UP)


func zoom_by(multiplier: float) -> void:
	_target_zoom = clampf(_target_zoom * multiplier, 0.36, 1.15)


func reset_camera() -> void:
	_target_zoom = 1.0
	_pan_offset = Vector3.ZERO


func _on_settings_changed() -> void:
	if _route_root:
		_route_root.visible = SettingsManager.show_path_preview


func set_selected_tower(tower_cfg: Dictionary) -> void:
	selected_tower_config = tower_cfg
	clear_inspection()
	if pending_build_cell != Vector2i(-1, -1):
		_spawn_build_ghost(pending_build_cell)
		build_preview_changed.emit(pending_build_cell, _boost_set.has(pending_build_cell))
	_update_hover_visuals()


func clear_build_preview() -> void:
	if is_instance_valid(_ghost_root):
		_ghost_root.queue_free()
	_ghost_root = null
	if pending_build_cell != Vector2i(-1, -1):
		pending_build_cell = Vector2i(-1, -1)
		_update_hover_visuals()
		build_preview_cleared.emit()


func confirm_pending_build() -> void:
	if pending_build_cell != Vector2i(-1, -1) and _is_buildable_cell(pending_build_cell):
		tower_place_requested.emit(pending_build_cell, _boost_set.has(pending_build_cell))


func _spawn_build_ghost(cell: Vector2i) -> void:
	if is_instance_valid(_ghost_root):
		_ghost_root.queue_free()
	_ghost_root = null
	if selected_tower_config.is_empty() or not _is_buildable_cell(cell):
		return
	var tid: String = str(selected_tower_config.get("id", "pulse"))
	var col := Color(str(selected_tower_config.get("color", "#00E5FF")))
	var built: Dictionary = _build_rotating_tower(tid, col, _boost_set.has(cell))
	_ghost_root = built["root"]
	var pos: Vector3 = cell_to_world_3d(cell)
	_ghost_root.position = pos
	var head_node: Node3D = built["head"]
	if is_instance_valid(head_node):
		head_node.rotation.y = _get_nearest_road_yaw(pos)
	_make_node_ghost(_ghost_root, col)
	_towers_root.add_child(_ghost_root)


func _make_node_ghost(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var gmat := _make_mat(tint, 1.35, 0.52, 0.2, 0.25)
		mi.material_override = gmat
	for c in node.get_children():
		_make_node_ghost(c, tint)


func clear_inspection() -> void:
	if inspected_cell != Vector2i(-1, -1):
		inspected_cell = Vector2i(-1, -1)
		_next_range_ring.visible = false
		_update_hover_visuals()
		tower_inspection_cleared.emit()


func is_wave_active() -> bool:
	return _wave_active


func get_stat_mult(lvl: int) -> float:
	# Линейная прогрессия: +20% от базы за каждый уровень (1.0, 1.2, 1.4, 1.6, 1.8)
	return 1.0 + float(clampi(lvl, 1, MAX_TOWER_LEVEL) - 1) * 0.20


func get_upgrade_cost(t: Dictionary) -> int:
	var lvl: int = int(t.get("level", 1))
	if lvl >= MAX_TOWER_LEVEL:
		return 0
	var base_cost: float = float(t.get("base_cost", 25))
	return int(roundf(base_cost * UPGRADE_COST_MULTS[lvl]))


func get_sell_refund(t: Dictionary) -> int:
	return int(roundf(float(t.get("total_invested", 25)) * 0.75))


func get_inspected_tower_info(cell: Vector2i) -> Dictionary:
	if not _placed_towers.has(cell):
		return {}
	var t: Dictionary = _placed_towers[cell]
	var lvl: int = int(t["level"])
	var boost_m: float = 1.2 if _boost_set.has(cell) else 1.0
	var cur_mult: float = get_stat_mult(lvl)
	var next_mult: float = get_stat_mult(min(lvl + 1, MAX_TOWER_LEVEL))
	return {
		"cell": cell,
		"id": str(t["id"]),
		"name": str(t["name"]),
		"color": str(t["color"]),
		"level": lvl,
		"max_level": MAX_TOWER_LEVEL,
		"upgrade_cost": get_upgrade_cost(t),
		"sell_refund": get_sell_refund(t),
		"cur_dmg": int(roundf(float(t["base_damage"]) * cur_mult * boost_m)),
		"next_dmg": int(roundf(float(t["base_damage"]) * next_mult * boost_m)),
		"cur_rng": int(roundf(float(t["base_range"]) * cur_mult)),
		"next_rng": int(roundf(float(t["base_range"]) * next_mult)),
		"cur_rof": float(t["base_fire_rate"]) * cur_mult,
		"next_rof": float(t["base_fire_rate"]) * next_mult
	}


func commit_upgrade_tower(cell: Vector2i) -> Dictionary:
	if not _placed_towers.has(cell):
		return {}
	var t: Dictionary = _placed_towers[cell]
	var lvl: int = int(t["level"])
	if lvl >= MAX_TOWER_LEVEL:
		return {}

	var cost: int = get_upgrade_cost(t)
	lvl += 1
	t["level"] = lvl
	t["total_invested"] = int(t["total_invested"]) + cost

	var mult: float = get_stat_mult(lvl)
	t["damage"] = float(t["base_damage"]) * mult
	t["range"] = float(t["base_range"]) * mult
	t["fire_rate"] = float(t["base_fire_rate"]) * mult
	t["aoe_radius"] = float(t["base_aoe_radius"]) * mult
	t["slow_factor"] = minf(0.65, float(t["base_slow_factor"]) + (0.15 if lvl == MAX_TOWER_LEVEL else float(lvl - 1) * 0.03))
	t["chain_count"] = int(t["base_chain_count"]) + (2 if lvl == MAX_TOWER_LEVEL else (1 if lvl >= 3 else 0))

	_apply_tower_upgrade_visuals(cell, t)
	var pos: Vector3 = cell_to_world_3d(cell)
	_spawn_ring_vfx(pos, 1.35, Color("#FACC15") if lvl == MAX_TOWER_LEVEL else Color("#00E5FF"), 0.32)
	sfx_requested.emit("upgrade")
	_update_hover_visuals()
	return get_inspected_tower_info(cell)


func _apply_tower_upgrade_visuals(cell: Vector2i, t: Dictionary) -> void:
	var lvl: int = int(t["level"])
	var head: Node3D = t.get("head", null)
	var rank_group: Node3D = t.get("rank_group", null)
	var badge: Sprite3D = t.get("level_badge", null)
	var col := Color(str(t.get("color", "#00E5FF")))
	var ring_col: Color = Color("#FACC15") if lvl == MAX_TOWER_LEVEL else col

	if is_instance_valid(head):
		var sc: float = 1.22 + float(lvl - 1) * 0.055
		head.scale = Vector3(sc, sc, sc)

	if is_instance_valid(rank_group):
		_clear_node_children(rank_group)
		var rmat := _make_mat(ring_col, 2.8 if lvl == MAX_TOWER_LEVEL else 2.2, 1.0, 0.2, 0.2)
		# Кольца эволюции на пьедестале (уровень 2..5)
		if lvl >= 2:
			var r2 := MeshInstance3D.new()
			var tm2 := TorusMesh.new()
			tm2.inner_radius = 0.30
			tm2.outer_radius = 0.34
			tm2.rings = 16
			r2.mesh = tm2
			r2.position.y = 0.26
			r2.material_override = rmat
			rank_group.add_child(r2)
		if lvl >= 3:
			var r3 := MeshInstance3D.new()
			var tm3 := TorusMesh.new()
			tm3.inner_radius = 0.40
			tm3.outer_radius = 0.44
			tm3.rings = 16
			r3.mesh = tm3
			r3.position.y = 0.06
			r3.material_override = rmat
			rank_group.add_child(r3)
		if lvl >= 4:
			# 4 боковых неоновых стабилизатора вокруг пьедестала
			var fin_mat := _make_mat(ring_col, 2.4, 1.0, 0.4, 0.2)
			for ang_deg in [45.0, 135.0, 225.0, 315.0]:
				var rad: float = deg_to_rad(ang_deg)
				var fin := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.08, 0.26, 0.08)
				fin.mesh = bm
				fin.position = Vector3(cos(rad) * 0.38, 0.22, sin(rad) * 0.38)
				fin.material_override = fin_mat
				rank_group.add_child(fin)

	if is_instance_valid(badge):
		badge.visible = lvl >= 2
		if lvl >= 2:
			var b_name: String = "badge_max" if lvl >= MAX_TOWER_LEVEL else ("badge_l%d" % lvl)
			var b_tex := _load_tex("res://assets/sprites/badges/%s.png" % b_name)
			if b_tex:
				badge.texture = b_tex


func _make_mat(col: Color, emission_strength: float = 0.0, alpha: float = 1.0, metallic: float = 0.50, roughness: float = 0.36) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.metallic = metallic
	m.roughness = roughness
	if alpha < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission_strength > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emission_strength
	return m


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _make_pbr_mat(col: Color, albedo_tex: Texture2D, normal_tex: Texture2D = null, rough_tex: Texture2D = null, metallic: float = 0.60, roughness: float = 0.42, emission_str: float = 0.0) -> StandardMaterial3D:
	var m := _make_mat(col, emission_str, 1.0, metallic, roughness)
	if albedo_tex:
		m.albedo_texture = albedo_tex
		m.albedo_color = Color(1.0, 1.0, 1.0, 1.0) if col == Color.WHITE else col
	if normal_tex:
		m.normal_enabled = true
		m.normal_texture = normal_tex
		m.normal_scale = 0.55
	if rough_tex:
		m.roughness_texture = rough_tex
	return m


func _make_unit_mat(col: Color, emission_strength: float = 0.0) -> StandardMaterial3D:
	var m := _make_mat(col, emission_strength, 1.0, 0.25, 0.48)
	var ntex := _load_tex("res://assets/textures/tile_normal.png")
	if ntex:
		m.normal_enabled = true
		m.normal_texture = ntex
		m.normal_scale = 0.55
		m.uv1_scale = Vector3(1.5, 1.5, 1.5)
	if _outline_mat:
		m.next_pass = _outline_mat
	return m


func _clear_node_children(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()


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
	var diff_mods: Dictionary = SettingsManager.get_difficulty_mods()
	cores_remaining = int(diff_mods.get("cores", 10))
	_waves_data = parsed.get("waves", [])

	fixed_paths.clear()
	smooth_paths.clear()
	for raw_p in parsed.get("paths", []):
		var cell_arr: Array[Vector2i] = _parse_vec2i_array(raw_p)
		fixed_paths.append(cell_arr)
		smooth_paths.append(_build_smooth_bezier_path(cell_arr))

	_hover_cell = Vector2i(-1, -1)
	inspected_cell = Vector2i(-1, -1)
	pending_build_cell = Vector2i(-1, -1)
	if is_instance_valid(_ghost_root):
		_ghost_root.queue_free()
	_ghost_root = null
	_hover_box.visible = false
	_range_ring.visible = false
	_next_range_ring.visible = false
	_placed_towers.clear()
	_enemies.clear()
	_projectiles.clear()
	_vfx.clear()
	_float_texts.clear()
	_spawn_queue.clear()
	_current_wave_idx = -1
	_wave_active = false
	_ended = false
	_core_flash = 0.0
	_zoom_factor = 1.0
	_target_zoom = 1.0
	_pan_offset = Vector3.ZERO

	_init_grid_state()
	_build_3d_board()
	_build_3d_routes()
	_update_camera_fit()

	level_loaded.emit(current_level_data)
	wave_state_changed.emit(0, _waves_data.size(), false)
	return true


func _build_smooth_bezier_path(cell_path: Array[Vector2i]) -> PackedVector3Array:
	var out := PackedVector3Array()
	if cell_path.size() < 2:
		for c in cell_path:
			out.append(cell_to_world_3d(c))
		return out

	var corners: Array[Vector3] = [cell_to_world_3d(cell_path[0])]
	for i in range(1, cell_path.size() - 1):
		var d1: Vector2i = cell_path[i] - cell_path[i - 1]
		var d2: Vector2i = cell_path[i + 1] - cell_path[i]
		if d1 != d2:
			corners.append(cell_to_world_3d(cell_path[i]))
	corners.append(cell_to_world_3d(cell_path[cell_path.size() - 1]))

	out.append(corners[0])
	var fillet: float = 0.44
	var steps: int = 6

	for i in range(1, corners.size() - 1):
		var prev_p: Vector3 = corners[i - 1]
		var cur_p: Vector3 = corners[i]
		var next_p: Vector3 = corners[i + 1]
		var dir_in: Vector3 = (cur_p - prev_p).normalized()
		var dir_out: Vector3 = (next_p - cur_p).normalized()
		var r_in: float = minf(fillet, prev_p.distance_to(cur_p) * 0.45)
		var r_out: float = minf(fillet, cur_p.distance_to(next_p) * 0.45)
		var p0: Vector3 = cur_p - dir_in * r_in
		var p2: Vector3 = cur_p + dir_out * r_out
		for s in range(steps + 1):
			var t: float = float(s) / float(steps)
			var u: float = 1.0 - t
			var pt: Vector3 = u * u * p0 + 2.0 * u * t * cur_p + t * t * p2
			out.append(pt)

	out.append(corners[corners.size() - 1])
	return out


func _parse_vec2i_array(raw: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for item in raw:
		if item is Array and item.size() >= 2:
			result.append(Vector2i(int(item[0]), int(item[1])))
	return result


func _init_grid_state() -> void:
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


func _build_3d_board() -> void:
	_clear_node_children(_board_root)
	_clear_node_children(_towers_root)
	_clear_node_children(_enemies_root)
	_clear_node_children(_fx_root)
	_core_sphere = null
	_core_ring_a = null
	_core_ring_b = null
	_core_light = null

	var base_plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(float(grid_size.x) + 0.6, 0.36, float(grid_size.y) + 0.6)
	base_plate.mesh = plate_mesh
	base_plate.position = Vector3(float(grid_size.x) * 0.5, -0.34, float(grid_size.y) * 0.5)
	base_plate.material_override = _make_mat(Color("#070C15"), 0.0, 1.0, 0.65, 0.45)
	_board_root.add_child(base_plate)

	# Неоновая рамка по периметру всей 3D-доски (как на концепте)
	var gx: float = float(grid_size.x)
	var gz: float = float(grid_size.y)
	var rim_cyan := _make_mat(Color("#00E5FF"), 1.45, 0.85, 0.1, 0.2)
	var rim_viol := _make_mat(Color("#A855F7"), 1.35, 0.85, 0.1, 0.2)
	_board_root.add_child(_create_beam_mesh(Vector3(-0.25, -0.02, -0.25), Vector3(gx + 0.25, -0.02, -0.25), 0.09, rim_cyan))
	_board_root.add_child(_create_beam_mesh(Vector3(-0.25, -0.02, gz + 0.25), Vector3(gx + 0.25, -0.02, gz + 0.25), 0.09, rim_viol))
	_board_root.add_child(_create_beam_mesh(Vector3(-0.25, -0.02, -0.25), Vector3(-0.25, -0.02, gz + 0.25), 0.09, rim_cyan))
	_board_root.add_child(_create_beam_mesh(Vector3(gx + 0.25, -0.02, -0.25), Vector3(gx + 0.25, -0.02, gz + 0.25), 0.09, rim_viol))

	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(0.90, 0.16, 0.90)
	var road_mesh := BoxMesh.new()
	road_mesh.size = Vector3(0.96, 0.09, 0.96)
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(0.88, 0.56, 0.88)

	var t_alb := _load_tex("res://assets/textures/tile_albedo.png")
	var t_nrm := _load_tex("res://assets/textures/tile_normal.png")
	var t_rgh := _load_tex("res://assets/textures/tile_roughness.png")
	var r_alb := _load_tex("res://assets/textures/road_albedo.png")
	var r_nrm := _load_tex("res://assets/textures/road_normal.png")
	var w_alb := _load_tex("res://assets/textures/wall_albedo.png")
	var w_nrm := _load_tex("res://assets/textures/wall_normal.png")
	var b_alb := _load_tex("res://assets/textures/boost_albedo.png")

	var mat_empty := _make_pbr_mat(Color.WHITE if t_alb else Color("#1A263A"), t_alb, t_nrm, t_rgh, 0.48, 0.58)
	var mat_road := _make_pbr_mat(Color.WHITE if r_alb else Color("#0D1C2E"), r_alb, r_nrm, null, 0.35, 0.58, 0.05)
	var mat_wall := _make_pbr_mat(Color.WHITE if w_alb else Color("#2B3D56"), w_alb, w_nrm, t_rgh, 0.55, 0.48, 0.03)
	var mat_boost := _make_pbr_mat(Color.WHITE if b_alb else Color("#103B34"), b_alb, t_nrm, t_rgh, 0.52, 0.32, 0.22)
	var mat_boost_ring := _make_mat(Color("#10B981"), 2.4, 1.0, 0.2, 0.2)
	var mat_portal_ring := _make_mat(Color("#F97316"), 3.0, 1.0, 0.1, 0.15)
	var mat_portal_core := _make_mat(Color("#FB923C"), 2.2, 0.55, 0.0, 0.1)

	var boost_ring_mesh := TorusMesh.new()
	boost_ring_mesh.inner_radius = 0.28
	boost_ring_mesh.outer_radius = 0.35
	boost_ring_mesh.rings = 20
	boost_ring_mesh.ring_segments = 8

	for cell: Vector2i in _cells:
		var pos := cell_to_world_3d(cell)
		var ct: int = int(_cells[cell])
		var tile := MeshInstance3D.new()
		match ct:
			CellType.EMPTY:
				tile.mesh = tile_mesh
				tile.position = Vector3(pos.x, -0.08, pos.z)
				tile.material_override = mat_empty
				_board_root.add_child(tile)
			CellType.PATH:
				tile.mesh = road_mesh
				tile.position = Vector3(pos.x, -0.12, pos.z)
				tile.material_override = mat_road
				_board_root.add_child(tile)
			CellType.WALL:
				tile.mesh = wall_mesh
				tile.position = Vector3(pos.x, 0.14, pos.z)
				tile.material_override = mat_wall
				_board_root.add_child(tile)
			CellType.BOOST:
				tile.mesh = tile_mesh
				tile.position = Vector3(pos.x, -0.08, pos.z)
				tile.material_override = mat_boost
				_board_root.add_child(tile)
				var ring := MeshInstance3D.new()
				ring.mesh = boost_ring_mesh
				ring.position = Vector3(pos.x, 0.02, pos.z)
				ring.material_override = mat_boost_ring
				ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_board_root.add_child(ring)
			CellType.SPAWN:
				tile.mesh = road_mesh
				tile.position = Vector3(pos.x, -0.12, pos.z)
				tile.material_override = mat_road
				_board_root.add_child(tile)
				_build_spawn_portal(pos, mat_portal_ring, mat_portal_core)
			CellType.CORE:
				tile.mesh = road_mesh
				tile.position = Vector3(pos.x, -0.12, pos.z)
				tile.material_override = mat_road
				_board_root.add_child(tile)
				_build_energy_core(pos)


func _build_spawn_portal(pos: Vector3, ring_mat: Material, core_mat: Material) -> void:
	var gate := MeshInstance3D.new()
	var gmesh := TorusMesh.new()
	gmesh.inner_radius = 0.42
	gmesh.outer_radius = 0.54
	gmesh.rings = 24
	gate.mesh = gmesh
	gate.position = Vector3(pos.x, 0.56, pos.z)
	gate.rotation_degrees = Vector3(90.0, 90.0, 0.0)
	gate.material_override = ring_mat
	_board_root.add_child(gate)

	var disc := MeshInstance3D.new()
	var dmesh := CylinderMesh.new()
	dmesh.top_radius = 0.42
	dmesh.bottom_radius = 0.42
	dmesh.height = 0.04
	disc.mesh = dmesh
	disc.position = Vector3(pos.x, 0.56, pos.z)
	disc.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	disc.material_override = core_mat
	_board_root.add_child(disc)

	var light := OmniLight3D.new()
	light.light_color = Color("#F97316")
	light.light_energy = 2.0
	light.omni_range = 4.5
	light.position = Vector3(pos.x, 0.9, pos.z)
	_board_root.add_child(light)


func _build_energy_core(pos: Vector3) -> void:
	_core_mat = _make_mat(Color("#00E5FF"), 3.4, 1.0, 0.1, 0.12)
	_core_sphere = MeshInstance3D.new()
	var smesh := SphereMesh.new()
	smesh.radius = 0.46
	smesh.height = 0.92
	_core_sphere.mesh = smesh
	_core_sphere.position = Vector3(pos.x, 0.62, pos.z)
	_core_sphere.material_override = _core_mat
	_board_root.add_child(_core_sphere)

	var ring_mat := _make_mat(Color("#00E5FF"), 2.6, 0.88, 0.1, 0.2)
	_core_ring_a = MeshInstance3D.new()
	var r1 := TorusMesh.new()
	r1.inner_radius = 0.72
	r1.outer_radius = 0.78
	r1.rings = 32
	_core_ring_a.mesh = r1
	_core_ring_a.position = Vector3(pos.x, 0.14, pos.z)
	_core_ring_a.material_override = ring_mat
	_board_root.add_child(_core_ring_a)

	_core_ring_b = MeshInstance3D.new()
	var r2 := TorusMesh.new()
	r2.inner_radius = 1.08
	r2.outer_radius = 1.14
	r2.rings = 36
	_core_ring_b.mesh = r2
	_core_ring_b.position = Vector3(pos.x, 0.08, pos.z)
	_core_ring_b.material_override = ring_mat
	_board_root.add_child(_core_ring_b)

	_core_light = OmniLight3D.new()
	_core_light.light_color = Color("#00E5FF")
	_core_light.light_energy = 3.0
	_core_light.omni_range = 7.0
	_core_light.position = Vector3(pos.x, 1.35, pos.z)
	_board_root.add_child(_core_light)


func _build_3d_routes() -> void:
	_clear_node_children(_route_root)
	var line_mat := _make_mat(Color("#00D8F5"), 1.35, 0.85, 0.1, 0.25)
	var joint_mesh := SphereMesh.new()
	joint_mesh.radius = 0.042
	joint_mesh.height = 0.084

	var chev_tex := _load_tex("res://assets/textures/chevron.png")
	var chev_mesh := QuadMesh.new()
	chev_mesh.size = Vector2(0.54, 0.54)
	var chev_mat := StandardMaterial3D.new()
	chev_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chev_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	chev_mat.albedo_color = Color(0.25, 0.94, 1.0, 0.82)
	if chev_tex:
		chev_mat.albedo_texture = chev_tex

	for spath in smooth_paths:
		var pts: PackedVector3Array = spath
		var dist_accum: float = 0.75
		for i in range(pts.size() - 1):
			var a: Vector3 = pts[i] + Vector3(0.0, -0.02, 0.0)
			var b: Vector3 = pts[i + 1] + Vector3(0.0, -0.02, 0.0)
			var seg_len: float = a.distance_to(b)
			if seg_len < 0.01:
				continue
			var seg := _create_beam_mesh(a, b, 0.065, line_mat)
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_route_root.add_child(seg)
			var cap := MeshInstance3D.new()
			cap.mesh = joint_mesh
			cap.position = b
			cap.material_override = line_mat
			cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_route_root.add_child(cap)
			if chev_tex:
				dist_accum += seg_len
				if dist_accum >= 1.75:
					dist_accum = 0.0
					var dir: Vector3 = (b - a).normalized()
					var chev := MeshInstance3D.new()
					chev.mesh = chev_mesh
					chev.material_override = chev_mat
					chev.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					chev.position = (a + b) * 0.5 + Vector3(0.0, 0.015, 0.0)
					chev.rotation = Vector3(-PI * 0.5, atan2(-dir.x, -dir.z), 0.0)
					_route_root.add_child(chev)
	_route_root.visible = SettingsManager.show_path_preview


func _create_beam_mesh(a: Vector3, b: Vector3, thickness: float, mat: Material) -> MeshInstance3D:
	var dist: float = maxf(a.distance_to(b), 0.01)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thickness, thickness, dist)
	mi.mesh = bm
	mi.material_override = mat
	var up_vec: Vector3 = Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT
	mi.look_at_from_position((a + b) * 0.5, b, up_vec)
	return mi


func cell_to_world_3d(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * TILE_SIZE, 0.0, (float(cell.y) + 0.5) * TILE_SIZE)


func _raycast_mouse_to_cell(screen_pos: Vector2) -> Vector2i:
	if not _camera:
		return Vector2i(-1, -1)
	var origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
	if hit == null:
		return Vector2i(-1, -1)
	var p: Vector3 = hit
	return Vector2i(floori(p.x / TILE_SIZE), floori(p.z / TILE_SIZE))


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return

	# Android / Touch: 2-finger Pinch-to-Zoom & Pan (1-finger drag handled via LMB drag-to-pan)
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() >= 2:
				_lmb_down = false
				_lmb_dragging = false
				var ks: Array = _touches.keys()
				var p0: Vector2 = _touches[ks[0]]
				var p1: Vector2 = _touches[ks[1]]
				_prev_pinch_dist = maxf(p0.distance_to(p1), 1.0)
				_prev_pinch_center = (p0 + p1) * 0.5
				_pinch_lock_timer = 0.30
		else:
			_touches.erase(st.index)
			if _touches.size() < 2:
				_prev_pinch_dist = 0.0
		return

	if event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			_pinch_lock_timer = 0.30
			_lmb_down = false
			_lmb_dragging = false
			var ks: Array = _touches.keys()
			var p0: Vector2 = _touches[ks[0]]
			var p1: Vector2 = _touches[ks[1]]
			var dist: float = maxf(p0.distance_to(p1), 1.0)
			if _prev_pinch_dist > 1.0:
				var ratio: float = _prev_pinch_dist / dist
				_target_zoom = clampf(_target_zoom * ratio, 0.36, 1.15)
			var center_now: Vector2 = (p0 + p1) * 0.5
			var delta_c: Vector2 = center_now - _prev_pinch_center
			_pan_screen_delta(delta_c)
			_prev_pinch_dist = dist
			_prev_pinch_center = center_now
		return

	if event is InputEventMouseMotion:
		var me: InputEventMouseMotion = event
		if _mmb_dragging:
			_pan_screen_delta(me.relative)
			return
		if _lmb_down and _pinch_lock_timer <= 0.0:
			if not _lmb_dragging and me.position.distance_to(_lmb_down_pos) > 10.0:
				_lmb_dragging = true
			if _lmb_dragging:
				_pan_screen_delta(me.relative)
				return
		var cell: Vector2i = _raycast_mouse_to_cell(me.position)
		if cell != _hover_cell:
			_hover_cell = cell
			_can_place_hover = _is_buildable_cell(_hover_cell)
			_update_hover_visuals()

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mmb_dragging = mb.pressed
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(0.88)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(1.14)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_lmb_down = true
				_lmb_down_pos = mb.position
				_lmb_dragging = false
			else:
				var was_drag: bool = _lmb_dragging
				var was_down: bool = _lmb_down
				_lmb_down = false
				_lmb_dragging = false
				if was_down and not was_drag and _pinch_lock_timer <= 0.0:
					var cell_l: Vector2i = _raycast_mouse_to_cell(mb.position)
					if not _cells.has(cell_l):
						clear_inspection()
						clear_build_preview()
					else:
						_handle_left_click(cell_l)
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _pinch_lock_timer <= 0.0:
			var cell_r: Vector2i = _raycast_mouse_to_cell(mb.position)
			_handle_right_click(cell_r)


func _pan_screen_delta(delta_px: Vector2) -> void:
	if not _camera:
		return
	var vp_h: float = maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var dist: float = _base_cam_dist * _zoom_factor
	var half_h: float = dist * tan(deg_to_rad(_camera.fov * 0.5))
	var world_per_px: float = (half_h * 2.0) / vp_h
	var cam_right: Vector3 = _camera.global_transform.basis.x
	var cam_fwd: Vector3 = -_camera.global_transform.basis.z
	cam_right.y = 0.0
	cam_fwd.y = 0.0
	cam_right = cam_right.normalized()
	cam_fwd = cam_fwd.normalized()
	_pan_offset -= cam_right * (delta_px.x * world_per_px)
	_pan_offset += cam_fwd * (delta_px.y * world_per_px)
	_apply_camera_transform()


func _set_solid_ring_radius(r: float) -> void:
	if absf(r - _last_ring_r) < 0.02:
		return
	_last_ring_r = r
	var tm := TorusMesh.new()
	tm.inner_radius = maxf(0.1, r - 0.024)
	tm.outer_radius = r + 0.024
	tm.rings = 64
	tm.ring_segments = 6
	_range_ring.mesh = tm
	_range_ring.scale = Vector3.ONE


func _set_dashed_ring_radius(r: float) -> void:
	if absf(r - _last_next_ring_r) < 0.02:
		return
	_last_next_ring_r = r
	_clear_node_children(_next_range_ring)
	var seg_count: int = 44
	var step_ang: float = TAU / float(seg_count)
	var dash_len: float = maxf(0.12, r * step_ang * 0.56)
	var bm := BoxMesh.new()
	bm.size = Vector3(dash_len, 0.025, 0.045)
	for i in seg_count:
		var ang: float = float(i) * step_ang
		var seg := MeshInstance3D.new()
		seg.mesh = bm
		seg.material_override = _next_range_mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.position = Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		seg.rotation.y = -ang + PI * 0.5
		_next_range_ring.add_child(seg)


func _update_hover_visuals() -> void:
	if not input_enabled:
		_hover_box.visible = false
		_range_ring.visible = false
		_next_range_ring.visible = false
		return

	# Если выбрана уже стоящая башня для инспекции/апгрейда — показываем её радиус и будущий радиус (+20%)
	if _placed_towers.has(inspected_cell):
		var t: Dictionary = _placed_towers[inspected_cell]
		var ipos: Vector3 = cell_to_world_3d(inspected_cell)
		var cur_r: float = float(t["range"]) * PX_TO_WORLD
		var tcol := Color(str(t.get("color", "#00E5FF")))
		_hover_box.visible = true
		_hover_box.position = Vector3(ipos.x, 0.06, ipos.z)
		_hover_mat.albedo_color = Color(1.0, 0.85, 0.15, 0.35)
		_hover_mat.emission = Color("#FACC15")

		_set_solid_ring_radius(cur_r)
		_range_ring.visible = true
		_range_ring.position = Vector3(ipos.x, 0.08, ipos.z)
		var cur_col := Color("#00E5FF")
		_range_mat.albedo_color = Color(cur_col.r, cur_col.g, cur_col.b, 0.85)
		_range_mat.emission = cur_col

		var lvl: int = int(t["level"])
		if lvl < MAX_TOWER_LEVEL:
			var next_r: float = float(t["base_range"]) * get_stat_mult(lvl + 1) * PX_TO_WORLD
			_set_dashed_ring_radius(next_r)
			_next_range_ring.visible = true
			_next_range_ring.position = Vector3(ipos.x, 0.09, ipos.z)
		else:
			_next_range_ring.visible = false
		return

	_next_range_ring.visible = false
	if pending_build_cell != Vector2i(-1, -1) and _is_buildable_cell(pending_build_cell):
		var ppos: Vector3 = cell_to_world_3d(pending_build_cell)
		var pcol := Color("#10B981") if _boost_set.has(pending_build_cell) else Color(str(selected_tower_config.get("color", "#00E5FF")))
		_hover_box.visible = true
		_hover_box.position = Vector3(ppos.x, 0.06, ppos.z)
		_hover_mat.albedo_color = Color(pcol.r, pcol.g, pcol.b, 0.45)
		_hover_mat.emission = pcol
		if not selected_tower_config.is_empty():
			var prng: float = float(selected_tower_config.get("range", 180.0)) * PX_TO_WORLD
			_set_solid_ring_radius(prng)
			_range_ring.visible = true
			_range_ring.position = Vector3(ppos.x, 0.08, ppos.z)
			_range_mat.albedo_color = Color(pcol.r, pcol.g, pcol.b, 0.72)
			_range_mat.emission = pcol
		else:
			_range_ring.visible = false
		return

	if not _cells.has(_hover_cell):
		_hover_box.visible = false
		_range_ring.visible = false
		return

	var pos: Vector3 = cell_to_world_3d(_hover_cell)
	_hover_box.visible = true
	_hover_box.position = Vector3(pos.x, 0.06, pos.z)
	var is_tower: bool = int(_cells.get(_hover_cell, -1)) == CellType.TOWER
	var hcol := Color("#FACC15") if is_tower else (Color("#00E5FF") if _can_place_hover else Color("#FF3B5C"))
	_hover_mat.albedo_color = Color(hcol.r, hcol.g, hcol.b, 0.35)
	_hover_mat.emission = hcol

	if _can_place_hover and not selected_tower_config.is_empty():
		var rng: float = float(selected_tower_config.get("range", 180.0)) * PX_TO_WORLD
		var tcol := Color(str(selected_tower_config.get("color", "#00E5FF")))
		_set_solid_ring_radius(rng)
		_range_ring.visible = true
		_range_ring.position = Vector3(pos.x, 0.08, pos.z)
		_range_mat.albedo_color = Color(tcol.r, tcol.g, tcol.b, 0.65)
		_range_mat.emission = tcol
	else:
		_range_ring.visible = false


func _is_buildable_cell(cell: Vector2i) -> bool:
	var t: int = int(_cells.get(cell, -1))
	return t == CellType.EMPTY or t == CellType.BOOST


func _handle_left_click(cell: Vector2i) -> void:
	var t: int = int(_cells.get(cell, -1))
	# Клик по уже стоящей башне открывает инспектор (и убирает предпросмотр постройки)
	if t == CellType.TOWER and _placed_towers.has(cell):
		clear_build_preview()
		inspected_cell = cell
		_update_hover_visuals()
		tower_inspected.emit(cell, get_inspected_tower_info(cell))
		return

	if inspected_cell != Vector2i(-1, -1):
		clear_inspection()

	if t == CellType.PATH or t == CellType.SPAWN or t == CellType.CORE:
		clear_build_preview()
		placement_rejected.emit(cell, "msg_on_road")
		return
	if not _is_buildable_cell(cell):
		clear_build_preview()
		placement_rejected.emit(cell, "msg_occupied")
		return

	# Повторный клик по той же клетке подтверждает постройку башни
	if cell == pending_build_cell:
		tower_place_requested.emit(cell, _boost_set.has(cell))
	else:
		pending_build_cell = cell
		_spawn_build_ghost(cell)
		_update_hover_visuals()
		build_preview_changed.emit(cell, _boost_set.has(cell))


func _handle_right_click(_cell: Vector2i) -> void:
	# ПКМ больше не продаёт башню — только отменяет предпросмотр или закрывает инспектор
	if pending_build_cell != Vector2i(-1, -1):
		clear_build_preview()
	elif inspected_cell != Vector2i(-1, -1):
		clear_inspection()


func _get_nearest_road_yaw(world_pos: Vector3) -> float:
	var best_dist_sq: float = INF
	var best_pt: Vector3 = world_pos + Vector3.FORWARD
	for spath in smooth_paths:
		var pts: PackedVector3Array = spath
		for p in pts:
			var dx: float = p.x - world_pos.x
			var dz: float = p.z - world_pos.z
			var d_sq: float = dx * dx + dz * dz
			if d_sq < best_dist_sq and d_sq > 0.001:
				best_dist_sq = d_sq
				best_pt = p
	return atan2(best_pt.x - world_pos.x, best_pt.z - world_pos.z)


func commit_place_tower(cell: Vector2i, tower_cfg: Dictionary) -> void:
	clear_build_preview()
	_cells[cell] = CellType.TOWER
	var tid: String = str(tower_cfg.get("id", "pulse"))
	var col := Color(str(tower_cfg.get("color", "#3B82F6")))
	var built: Dictionary = _build_rotating_tower(tid, col, _boost_set.has(cell))
	var root_node: Node3D = built["root"]
	root_node.position = cell_to_world_3d(cell)
	_towers_root.add_child(root_node)

	var init_yaw: float = _get_nearest_road_yaw(root_node.position)
	var head_node: Node3D = built["head"]
	if is_instance_valid(head_node):
		head_node.rotation.y = init_yaw

	var base_cost: int = int(tower_cfg.get("cost", 25))
	var runtime_cfg: Dictionary = tower_cfg.duplicate()
	runtime_cfg["level"] = 1
	runtime_cfg["base_cost"] = base_cost
	runtime_cfg["total_invested"] = base_cost
	runtime_cfg["base_damage"] = float(tower_cfg.get("damage", 12.0))
	runtime_cfg["base_range"] = float(tower_cfg.get("range", 180.0))
	runtime_cfg["base_fire_rate"] = float(tower_cfg.get("fire_rate", 1.0))
	runtime_cfg["base_aoe_radius"] = float(tower_cfg.get("aoe_radius", 72.0))
	runtime_cfg["base_slow_factor"] = float(tower_cfg.get("slow_factor", 0.4))
	runtime_cfg["base_chain_count"] = int(tower_cfg.get("chain_count", 3))
	runtime_cfg["cooldown"] = 0.0
	runtime_cfg["recoil"] = 0.0
	runtime_cfg["yaw"] = init_yaw
	runtime_cfg["node"] = root_node
	runtime_cfg["head"] = built["head"]
	runtime_cfg["barrel_group"] = built["barrel_group"]
	runtime_cfg["muzzle"] = built["muzzle"]
	runtime_cfg["rank_group"] = built["rank_group"]
	runtime_cfg["level_badge"] = built["level_badge"]
	_placed_towers[cell] = runtime_cfg
	_can_place_hover = false
	_update_hover_visuals()
	sfx_requested.emit("place")


func commit_remove_tower(cell: Vector2i) -> void:
	if _placed_towers.has(cell):
		var n: Node3D = _placed_towers[cell].get("node", null)
		if is_instance_valid(n):
			n.queue_free()
		_placed_towers.erase(cell)
	if inspected_cell == cell:
		clear_inspection()
	_cells[cell] = CellType.BOOST if _boost_set.has(cell) else CellType.EMPTY
	_can_place_hover = _is_buildable_cell(_hover_cell)
	_update_hover_visuals()
	sfx_requested.emit("sell")


func _build_rotating_tower(tid: String, col: Color, on_boost: bool) -> Dictionary:
	var root := Node3D.new()
	var dark_mat := _make_unit_mat(Color("#18253A"), 0.0)
	var steel_mat := _make_unit_mat(Color("#64748B"), 0.0)
	var accent_mat := _make_unit_mat(col.lightened(0.08), 0.18)
	var glow_mat := _make_mat(col.lightened(0.15), 2.1, 1.0, 0.1, 0.2)

	var ped := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.38
	pm.bottom_radius = 0.44
	pm.height = 0.16
	pm.radial_segments = 8
	ped.mesh = pm
	ped.position.y = 0.08
	ped.material_override = dark_mat
	root.add_child(ped)

	var collar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.34
	cm.height = 0.14
	cm.radial_segments = 8
	collar.mesh = cm
	collar.position.y = 0.22
	collar.material_override = steel_mat
	root.add_child(collar)

	var base_ring := MeshInstance3D.new()
	var brm := TorusMesh.new()
	brm.inner_radius = 0.35
	brm.outer_radius = 0.39
	brm.rings = 16
	base_ring.mesh = brm
	base_ring.position.y = 0.16
	base_ring.material_override = _make_mat(Color("#10B981") if on_boost else col, 2.2, 1.0, 0.2, 0.2)
	root.add_child(base_ring)

	var rank_group := Node3D.new()
	root.add_child(rank_group)

	var level_badge := Sprite3D.new()
	level_badge.pixel_size = 0.0033
	level_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	level_badge.no_depth_test = true
	level_badge.render_priority = 12
	level_badge.shaded = false
	level_badge.position = Vector3(0.0, 1.38, 0.0)
	level_badge.visible = false
	root.add_child(level_badge)

	var head := Node3D.new()
	head.position.y = 0.36
	head.scale = Vector3(1.22, 1.22, 1.22)
	root.add_child(head)

	var barrel_group := Node3D.new()
	head.add_child(barrel_group)

	var muzzle := Node3D.new()
	muzzle.position = Vector3(0.0, 0.08, 0.56)
	barrel_group.add_child(muzzle)

	match tid:
		"pulse":
			var body := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.38, 0.24, 0.42)
			body.mesh = bm
			body.position = Vector3(0.0, 0.08, -0.02)
			body.material_override = accent_mat
			head.add_child(body)
			for sx in [-0.10, 0.10]:
				var bar := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.042
				cyl.bottom_radius = 0.052
				cyl.height = 0.50
				bar.mesh = cyl
				bar.rotation_degrees = Vector3(90.0, 0.0, 0.0)
				bar.position = Vector3(sx, 0.08, 0.34)
				bar.material_override = steel_mat
				barrel_group.add_child(bar)
				var tip := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.036
				tm.outer_radius = 0.056
				tip.mesh = tm
				tip.rotation_degrees = Vector3(90.0, 0.0, 0.0)
				tip.position = Vector3(sx, 0.08, 0.58)
				tip.material_override = glow_mat
				barrel_group.add_child(tip)
			muzzle.position = Vector3(0.0, 0.08, 0.62)

		"cannon":
			var cradle := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.46, 0.26, 0.44)
			cradle.mesh = bm
			cradle.position = Vector3(0.0, 0.08, -0.04)
			cradle.material_override = accent_mat
			head.add_child(cradle)
			var tube := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.12
			cyl.bottom_radius = 0.16
			cyl.height = 0.60
			tube.mesh = cyl
			tube.rotation_degrees = Vector3(62.0, 0.0, 0.0)
			tube.position = Vector3(0.0, 0.22, 0.20)
			tube.material_override = steel_mat
			barrel_group.add_child(tube)
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.10
			tm.outer_radius = 0.145
			ring.mesh = tm
			ring.rotation_degrees = Vector3(62.0, 0.0, 0.0)
			ring.position = Vector3(0.0, 0.34, 0.44)
			ring.material_override = glow_mat
			barrel_group.add_child(ring)
			muzzle.position = Vector3(0.0, 0.38, 0.50)

		"cryo":
			var crystal := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.01
			cyl.bottom_radius = 0.22
			cyl.height = 0.66
			cyl.radial_segments = 6
			crystal.mesh = cyl
			crystal.position = Vector3(0.0, 0.36, 0.0)
			crystal.material_override = _make_mat(col, 2.6, 0.92, 0.1, 0.1)
			head.add_child(crystal)
			var bot_c := MeshInstance3D.new()
			var cyl2 := CylinderMesh.new()
			cyl2.top_radius = 0.22
			cyl2.bottom_radius = 0.01
			cyl2.height = 0.22
			cyl2.radial_segments = 6
			bot_c.mesh = cyl2
			bot_c.position = Vector3(0.0, -0.06, 0.0)
			bot_c.material_override = _make_mat(col, 2.2, 0.90, 0.1, 0.1)
			head.add_child(bot_c)
			muzzle.position = Vector3(0.0, 0.35, 0.0)

		"tesla":
			var spire := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.top_radius = 0.06
			sm.bottom_radius = 0.14
			sm.height = 0.68
			spire.mesh = sm
			spire.position.y = 0.26
			spire.material_override = steel_mat
			head.add_child(spire)
			for idx in 3:
				var r := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.22 - float(idx) * 0.035
				tm.outer_radius = 0.26 - float(idx) * 0.035
				r.mesh = tm
				r.position.y = 0.14 + float(idx) * 0.16
				r.material_override = glow_mat
				head.add_child(r)
			var orb := MeshInstance3D.new()
			var om := SphereMesh.new()
			om.radius = 0.15
			om.height = 0.30
			orb.mesh = om
			orb.position.y = 0.68
			orb.material_override = _make_mat(col, 3.2, 1.0, 0.1, 0.1)
			head.add_child(orb)
			muzzle.position = Vector3(0.0, 0.68, 0.0)

		"laser":
			var housing := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.34, 0.30, 0.54)
			housing.mesh = bm
			housing.position = Vector3(0.0, 0.12, 0.0)
			housing.material_override = accent_mat
			barrel_group.add_child(housing)
			var lens := MeshInstance3D.new()
			var lm := SphereMesh.new()
			lm.radius = 0.13
			lm.height = 0.26
			lens.mesh = lm
			lens.position = Vector3(0.0, 0.12, 0.28)
			lens.material_override = glow_mat
			barrel_group.add_child(lens)
			muzzle.position = Vector3(0.0, 0.12, 0.38)

		"railgun":
			var core_box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.34, 0.22, 0.48)
			core_box.mesh = bm
			core_box.position = Vector3(0.0, 0.10, -0.06)
			core_box.material_override = steel_mat
			head.add_child(core_box)
			for sx in [-0.10, 0.10]:
				var rail := MeshInstance3D.new()
				var rm := BoxMesh.new()
				rm.size = Vector3(0.07, 0.12, 0.92)
				rail.mesh = rm
				rail.position = Vector3(sx, 0.12, 0.30)
				rail.material_override = accent_mat
				barrel_group.add_child(rail)
			var energy := MeshInstance3D.new()
			var em := BoxMesh.new()
			em.size = Vector3(0.06, 0.06, 0.78)
			energy.mesh = em
			energy.position = Vector3(0.0, 0.12, 0.28)
			energy.material_override = _make_mat(Color("#FEF08A"), 3.0, 1.0, 0.1, 0.1)
			barrel_group.add_child(energy)
			muzzle.position = Vector3(0.0, 0.12, 0.78)

	return {
		"root": root, "head": head, "barrel_group": barrel_group,
		"muzzle": muzzle, "rank_group": rank_group, "level_badge": level_badge
	}


func start_next_wave() -> bool:
	if _wave_active or _ended:
		return false
	if _current_wave_idx + 1 >= _waves_data.size():
		return false

	_current_wave_idx += 1
	var w_data: Dictionary = _waves_data[_current_wave_idx]
	var diff_mods: Dictionary = SettingsManager.get_difficulty_mods()
	var wave_scale: float = minf(1.80, 1.0 + float(_current_wave_idx) * 0.08)
	var hp_mult: float = float(w_data.get("hp_multiplier", 1.0)) * wave_scale
	var int_mult: float = float(diff_mods.get("spawn_int_mult", 1.0))
	_spawn_queue.clear()
	_wave_time = 0.0

	for grp in w_data.get("groups", []):
		var eid: String = str(grp.get("enemy", "trooper"))
		var cnt: int = int(grp.get("count", 5))
		var interval: float = maxf(0.18, float(grp.get("interval", 0.8)) * int_mult)
		var delay: float = float(grp.get("delay", 0.0)) * int_mult
		var elite: bool = bool(grp.get("elite", false))
		for i in cnt:
			var pidx: int = _round_robin_spawn % max(smooth_paths.size(), 1)
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
	_anim_time += delta
	if _pinch_lock_timer > 0.0:
		_pinch_lock_timer = maxf(0.0, _pinch_lock_timer - delta)
	var cam_dirty: bool = false
	if absf(_zoom_factor - _target_zoom) > 0.001:
		_zoom_factor = lerpf(_zoom_factor, _target_zoom, minf(1.0, delta * 12.0))
		cam_dirty = true
	if input_enabled:
		var pan_v := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			pan_v.x += 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			pan_v.x -= 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			pan_v.y += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			pan_v.y -= 1.0
		if pan_v.length_squared() > 0.01:
			_pan_screen_delta(pan_v.normalized() * 480.0 * delta)
			cam_dirty = false
	if cam_dirty:
		_apply_camera_transform()
	if is_instance_valid(_core_sphere):
		_core_sphere.position.y = 0.62 + sin(_anim_time * 2.6) * 0.08
	if is_instance_valid(_core_ring_a):
		_core_ring_a.rotation.y = _anim_time * 1.1
	if is_instance_valid(_core_ring_b):
		_core_ring_b.rotation.y = -_anim_time * 0.7
	if is_instance_valid(_next_range_ring) and _next_range_ring.visible:
		_next_range_ring.rotation.y = -_anim_time * 0.25

	if _core_flash > 0.0:
		_core_flash = maxf(0.0, _core_flash - delta * 2.5)
		if _core_mat:
			var c := Color("#FF3B5C") if _core_flash > 0.2 else Color("#00E5FF")
			_core_mat.albedo_color = c
			_core_mat.emission = c
			if is_instance_valid(_core_light):
				_core_light.light_color = c

	var dt: float = delta * game_speed
	_animate_idle_towers(dt)

	if _wave_active and not _ended:
		_wave_time += dt
		_process_spawns()
		_process_enemies(dt)
		_process_towers(dt)
		_process_projectiles(dt)
		_check_wave_completion()
	elif not _ended and not _projectiles.is_empty():
		_process_projectiles(dt)

	_process_vfx(delta)
	_process_float_texts(delta)


func _animate_idle_towers(dt: float) -> void:
	for cell: Vector2i in _placed_towers:
		var t: Dictionary = _placed_towers[cell]
		var tid: String = str(t.get("id", "pulse"))
		var head: Node3D = t.get("head", null)
		var bg: Node3D = t.get("barrel_group", null)
		if tid == "cryo" and is_instance_valid(head):
			head.rotation.y += dt * 1.5
			head.position.y = 0.36 + sin(_anim_time * 3.0 + float(cell.x)) * 0.05
		if float(t["recoil"]) > 0.0:
			t["recoil"] = maxf(0.0, float(t["recoil"]) - dt * 7.0)
			if is_instance_valid(bg):
				bg.position.z = -float(t["recoil"]) * 0.14


func _process_spawns() -> void:
	while not _spawn_queue.is_empty() and float(_spawn_queue[0]["time"]) <= _wave_time:
		var item: Dictionary = _spawn_queue.pop_front()
		_spawn_enemy(item)


func _spawn_enemy(item: Dictionary) -> void:
	var eid: String = str(item["enemy_id"])
	var base: Dictionary = _enemy_catalog.get(eid, {"hp": 80, "shield": 0, "armor": 0, "speed": 90, "bounty": 8, "is_flying": false})
	var hp_mult: float = float(item["hp_mult"])
	var pidx: int = int(item["path_idx"])
	var pts: PackedVector3Array = smooth_paths[pidx] if pidx < smooth_paths.size() else PackedVector3Array([cell_to_world_3d(core_cell)])
	var is_flying: bool = bool(base.get("is_flying", false))
	var start_pos: Vector3 = pts[0] + Vector3(0.0, 1.15 if is_flying else 0.02, 0.0)
	var diff_mods: Dictionary = SettingsManager.get_difficulty_mods()
	var d_hp: float = float(diff_mods.get("hp_mult", 1.0))
	var d_spd: float = float(diff_mods.get("speed_mult", 1.0))
	var max_hp: float = float(base.get("hp", 80)) * hp_mult * d_hp
	var max_shield: float = float(base.get("shield", 0)) * hp_mult * d_hp
	var elite: bool = bool(item.get("elite", false))

	var visual: Dictionary = _build_animated_enemy(eid, elite, max_shield > 0.0)
	var node: Node3D = visual["root"]
	node.position = start_pos
	_enemies_root.add_child(node)

	var init_yaw: float = 0.0
	if pts.size() >= 2:
		var d: Vector3 = pts[1] - pts[0]
		init_yaw = atan2(d.x, d.z)
	node.rotation.y = init_yaw

	_enemies.append({
		"id": eid, "pos": start_pos, "path_idx": pidx, "wp_idx": 1, "progress": 0.0,
		"yaw": init_yaw, "walk_phase": randf() * TAU,
		"hp": max_hp, "max_hp": max_hp, "shield": max_shield, "max_shield": max_shield,
		"armor": float(base.get("armor", 0)), "speed": float(base.get("speed", 90)) * PX_TO_WORLD * d_spd,
		"bounty": int(base.get("bounty", 8)), "is_flying": is_flying, "elite": elite,
		"slow_timer": 0.0, "slow_factor": 1.0, "medic_cd": 2.0, "shield_regen_cd": 0.0,
		"node": node, "parts": visual["parts"], "shield_mesh": visual["shield"], "hp_bar": visual["hp_bar"]
	})


func _build_animated_enemy(eid: String, elite: bool, has_shield: bool) -> Dictionary:
	var root := Node3D.new()
	var body_pivot := Node3D.new()
	root.add_child(body_pivot)
	var sc: float = 1.75 if elite else 1.45
	body_pivot.scale = Vector3(sc, sc, sc)

	# Тёмная контактная тень под каждым врагом — чётко отделяет силуэт от неоновой дороги
	if eid != "drone":
		var shadow := MeshInstance3D.new()
		var shm := CylinderMesh.new()
		shm.top_radius = 0.36 * sc
		shm.bottom_radius = 0.36 * sc
		shm.height = 0.02
		shm.radial_segments = 16
		shadow.mesh = shm
		shadow.position.y = 0.02
		var shmat := StandardMaterial3D.new()
		shmat.albedo_color = Color(0.01, 0.02, 0.05, 0.80)
		shmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shadow.material_override = shmat
		root.add_child(shadow)

	var parts: Dictionary = {"pivot": body_pivot}
	var steel := _make_unit_mat(Color("#94A3B8"), 0.0)
	var dark := _make_unit_mat(Color("#273549"), 0.0)

	match eid:
		"swarm":
			var hull := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.28, 0.14, 0.38)
			hull.mesh = bm
			hull.position.y = 0.22
			hull.material_override = _make_unit_mat(Color("#E11D48"), 0.15)
			body_pivot.add_child(hull)
			var thrust := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.09
			sm.height = 0.18
			thrust.mesh = sm
			thrust.position = Vector3(0.0, 0.22, -0.22)
			thrust.material_override = _make_mat(Color("#FB7185"), 2.8, 1.0, 0.1, 0.1)
			body_pivot.add_child(thrust)
			parts["thruster"] = thrust

		"trooper":
			var red := _make_unit_mat(Color("#EF4444"), 0.15)
			var visor := _make_mat(Color("#F97316"), 2.8, 1.0, 0.1, 0.1)
			var leg_l := _make_leg(steel, Vector3(-0.10, 0.24, 0.0), 0.24)
			var leg_r := _make_leg(steel, Vector3(0.10, 0.24, 0.0), 0.24)
			body_pivot.add_child(leg_l)
			body_pivot.add_child(leg_r)
			var torso := Node3D.new()
			torso.position.y = 0.36
			body_pivot.add_child(torso)
			var chest := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.28, 0.24, 0.20)
			chest.mesh = bm
			chest.material_override = red
			torso.add_child(chest)
			var head_m := MeshInstance3D.new()
			var hm := BoxMesh.new()
			hm.size = Vector3(0.17, 0.14, 0.17)
			head_m.mesh = hm
			head_m.position = Vector3(0.0, 0.19, 0.01)
			head_m.material_override = steel
			torso.add_child(head_m)
			var v := MeshInstance3D.new()
			var vm := BoxMesh.new()
			vm.size = Vector3(0.13, 0.05, 0.04)
			v.mesh = vm
			v.position = Vector3(0.0, 0.20, 0.09)
			v.material_override = visor
			torso.add_child(v)
			parts["leg_l"] = leg_l
			parts["leg_r"] = leg_r
			parts["torso"] = torso

		"armored":
			for sx in [-0.24, 0.24]:
				var tread := MeshInstance3D.new()
				var tm := BoxMesh.new()
				tm.size = Vector3(0.12, 0.18, 0.66)
				tread.mesh = tm
				tread.position = Vector3(sx, 0.09, 0.0)
				tread.material_override = dark
				body_pivot.add_child(tread)
			var hull := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.42, 0.18, 0.56)
			hull.mesh = bm
			hull.position.y = 0.18
			hull.material_override = steel
			body_pivot.add_child(hull)
			var turret := Node3D.new()
			turret.position.y = 0.33
			body_pivot.add_child(turret)
			var cap := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.30, 0.14, 0.32)
			cap.mesh = cm
			cap.material_override = steel
			turret.add_child(cap)
			var gun := MeshInstance3D.new()
			var gm := CylinderMesh.new()
			gm.top_radius = 0.04
			gm.bottom_radius = 0.05
			gm.height = 0.42
			gun.mesh = gm
			gun.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			gun.position = Vector3(0.0, 0.01, 0.30)
			gun.material_override = dark
			turret.add_child(gun)
			var slit := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.20, 0.04, 0.04)
			slit.mesh = sm
			slit.position = Vector3(0.0, 0.21, 0.28)
			slit.material_override = _make_mat(Color("#EF4444"), 2.4, 1.0, 0.1, 0.1)
			body_pivot.add_child(slit)
			parts["turret"] = turret

		"shielded":
			var purp := _make_unit_mat(Color("#A855F7"), 0.18)
			var leg_l := _make_leg(dark, Vector3(-0.13, 0.26, 0.0), 0.26)
			var leg_r := _make_leg(dark, Vector3(0.13, 0.26, 0.0), 0.26)
			body_pivot.add_child(leg_l)
			body_pivot.add_child(leg_r)
			var torso := Node3D.new()
			torso.position.y = 0.42
			body_pivot.add_child(torso)
			var chest := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.40, 0.30, 0.28)
			chest.mesh = bm
			chest.material_override = purp
			torso.add_child(chest)
			var eye := MeshInstance3D.new()
			var em := BoxMesh.new()
			em.size = Vector3(0.18, 0.07, 0.05)
			eye.mesh = em
			eye.position = Vector3(0.0, 0.04, 0.15)
			eye.material_override = _make_mat(Color("#38BDF8"), 2.8, 1.0, 0.1, 0.1)
			torso.add_child(eye)
			parts["leg_l"] = leg_l
			parts["leg_r"] = leg_r
			parts["torso"] = torso

		"medic":
			var van := MeshInstance3D.new()
			var vm := BoxMesh.new()
			vm.size = Vector3(0.42, 0.24, 0.56)
			van.mesh = vm
			van.position.y = 0.22
			van.material_override = steel
			body_pivot.add_child(van)
			var beacon := Node3D.new()
			beacon.position.y = 0.40
			body_pivot.add_child(beacon)
			var gmat := _make_mat(Color("#22C55E"), 2.8, 1.0, 0.1, 0.1)
			for sz in [Vector3(0.24, 0.06, 0.08), Vector3(0.08, 0.06, 0.24)]:
				var bar := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = sz
				bar.mesh = bm
				bar.material_override = gmat
				beacon.add_child(bar)
			parts["beacon"] = beacon

		"splitter":
			var gold_mat := _make_unit_mat(Color("#F59E0B"), 0.18)
			var core_m := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.24, 0.24, 0.24)
			core_m.mesh = cm
			core_m.position.y = 0.36
			core_m.material_override = _make_mat(Color("#FACC15"), 2.8, 1.0, 0.1, 0.1)
			body_pivot.add_child(core_m)
			for sx in [-0.22, 0.22]:
				var plate := MeshInstance3D.new()
				var pm := BoxMesh.new()
				pm.size = Vector3(0.12, 0.30, 0.26)
				plate.mesh = pm
				plate.position = Vector3(sx, 0.34, 0.0)
				plate.material_override = gold_mat
				body_pivot.add_child(plate)
			parts["core"] = core_m

		"drone":
			var hull := MeshInstance3D.new()
			var hm := BoxMesh.new()
			hm.size = Vector3(0.26, 0.12, 0.36)
			hull.mesh = hm
			hull.material_override = _make_unit_mat(Color("#38BDF8"), 0.20)
			body_pivot.add_child(hull)
			var rmat := _make_mat(Color("#38BDF8"), 2.8, 0.9, 0.1, 0.1)
			var rotors: Array[Node3D] = []
			for sx in [-0.26, 0.26]:
				for sz in [-0.22, 0.22]:
					var r := MeshInstance3D.new()
					var tm := TorusMesh.new()
					tm.inner_radius = 0.08
					tm.outer_radius = 0.115
					tm.rings = 12
					r.mesh = tm
					r.position = Vector3(sx, 0.05, sz)
					r.material_override = rmat
					body_pivot.add_child(r)
					rotors.append(r)
			parts["rotors"] = rotors

	var shield_mesh: MeshInstance3D = null
	if has_shield:
		shield_mesh = MeshInstance3D.new()
		var shm := SphereMesh.new()
		shm.radius = 0.48 * sc
		shm.height = 0.96 * sc
		shield_mesh.mesh = shm
		shield_mesh.position.y = 0.36 * sc
		shield_mesh.material_override = _make_mat(Color("#38BDF8"), 1.6, 0.28, 0.1, 0.1)
		root.add_child(shield_mesh)

	var hp_bar := MeshInstance3D.new()
	var hbm := BoxMesh.new()
	hbm.size = Vector3(0.62, 0.07, 0.07)
	hp_bar.mesh = hbm
	hp_bar.position = Vector3(0.0, 0.85 * sc, 0.0)
	hp_bar.material_override = _make_mat(Color("#22C55E"), 1.8, 1.0, 0.0, 0.5)
	hp_bar.visible = false
	root.add_child(hp_bar)

	return {"root": root, "parts": parts, "shield": shield_mesh, "hp_bar": hp_bar}


func _make_leg(mat: Material, hip_pos: Vector3, length: float) -> Node3D:
	var hip := Node3D.new()
	hip.position = hip_pos
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, length, 0.11)
	m.mesh = bm
	m.position.y = -length * 0.5
	m.material_override = mat
	hip.add_child(m)
	return hip


func _process_enemies(dt: float) -> void:
	var core_pos: Vector3 = cell_to_world_3d(core_cell)
	var i: int = _enemies.size() - 1
	while i >= 0:
		var e: Dictionary = _enemies[i]
		if float(e["slow_timer"]) > 0.0:
			e["slow_timer"] = float(e["slow_timer"]) - dt
			if float(e["slow_timer"]) <= 0.0:
				e["slow_factor"] = 1.0

		if float(e["max_shield"]) > 0.0:
			e["shield_regen_cd"] = maxf(0.0, float(e["shield_regen_cd"]) - dt)
			if float(e["shield_regen_cd"]) <= 0.0 and float(e["shield"]) < float(e["max_shield"]):
				e["shield"] = minf(float(e["max_shield"]), float(e["shield"]) + float(e["max_shield"]) * 0.12 * dt)
			var sm: MeshInstance3D = e["shield_mesh"]
			if is_instance_valid(sm):
				sm.visible = float(e["shield"]) > 0.5

		if str(e["id"]) == "medic":
			e["medic_cd"] = float(e["medic_cd"]) - dt
			if float(e["medic_cd"]) <= 0.0:
				e["medic_cd"] = 2.5
				for ally in _enemies:
					if (ally["pos"] as Vector3).distance_to(e["pos"]) <= 2.2:
						ally["hp"] = minf(float(ally["max_hp"]), float(ally["hp"]) + float(ally["max_hp"]) * 0.10)

		var spd: float = float(e["speed"]) * float(e["slow_factor"])
		var reached_core: bool = false
		var cur_pos: Vector3 = e["pos"]
		var move_dir := Vector3.FORWARD

		if bool(e["is_flying"]):
			var target_pos: Vector3 = core_pos + Vector3(0.0, 1.15, 0.0)
			var diff: Vector3 = target_pos - cur_pos
			var dist: float = diff.length()
			if dist <= spd * dt + 0.15:
				reached_core = true
			else:
				move_dir = diff.normalized()
				cur_pos += move_dir * spd * dt
				e["progress"] = float(e["progress"]) + spd * dt
		else:
			var pts: PackedVector3Array = smooth_paths[int(e["path_idx"])]
			var step_left: float = spd * dt
			while step_left > 0.0001:
				var wp_idx: int = int(e["wp_idx"])
				if wp_idx >= pts.size():
					reached_core = true
					break
				var target_pos: Vector3 = pts[wp_idx] + Vector3(0.0, 0.02, 0.0)
				var diff: Vector3 = target_pos - cur_pos
				var dist: float = diff.length()
				if dist <= step_left:
					if dist > 0.001:
						move_dir = diff / dist
					cur_pos = target_pos
					step_left -= dist
					e["progress"] = float(e["progress"]) + dist
					e["wp_idx"] = wp_idx + 1
					if int(e["wp_idx"]) >= pts.size():
						reached_core = true
						break
				else:
					move_dir = diff / dist
					cur_pos += move_dir * step_left
					e["progress"] = float(e["progress"]) + step_left
					step_left = 0.0

		e["pos"] = cur_pos
		var walk_phase: float = float(e["walk_phase"]) + dt * spd * 4.2
		e["walk_phase"] = walk_phase

		var node: Node3D = e["node"]
		if is_instance_valid(node):
			node.position = cur_pos
			var desired_yaw: float = atan2(move_dir.x, move_dir.z)
			var prev_yaw: float = float(e["yaw"])
			var new_yaw: float = lerp_angle(prev_yaw, desired_yaw, minf(1.0, dt * 10.0))
			var turn_delta: float = angle_difference(prev_yaw, new_yaw)
			e["yaw"] = new_yaw
			node.rotation.y = new_yaw

			var parts: Dictionary = e["parts"]
			var pivot: Node3D = parts["pivot"]
			pivot.rotation.z = clampf(-turn_delta * 2.5, -0.22, 0.22)
			var eid: String = str(e["id"])
			if eid == "trooper" or eid == "shielded":
				var leg_l: Node3D = parts["leg_l"]
				var leg_r: Node3D = parts["leg_r"]
				var torso: Node3D = parts["torso"]
				leg_l.rotation.x = sin(walk_phase) * 0.55
				leg_r.rotation.x = -sin(walk_phase) * 0.55
				torso.position.y = (0.36 if eid == "trooper" else 0.42) + absf(sin(walk_phase)) * 0.05
			elif eid == "armored":
				var turret: Node3D = parts["turret"]
				turret.rotation.y = sin(_anim_time * 1.4 + float(i)) * 0.45
			elif eid == "swarm":
				pivot.position.x = sin(walk_phase * 1.3) * 0.14
				pivot.position.y = 0.04 + sin(walk_phase * 2.0) * 0.04
			elif eid == "medic":
				pivot.position.y = 0.03 + sin(_anim_time * 3.5 + float(i)) * 0.03
				var beacon: Node3D = parts["beacon"]
				beacon.rotation.y += dt * 3.2
			elif eid == "splitter":
				var core_m: Node3D = parts["core"]
				core_m.rotation.y += dt * 2.8
				core_m.rotation.x += dt * 1.6
				pivot.position.y = 0.04 + sin(_anim_time * 3.2 + float(i)) * 0.05
			elif eid == "drone":
				pivot.position.y = sin(_anim_time * 4.5 + float(i)) * 0.09
				pivot.rotation.x = 0.12
				var rotors: Array = parts["rotors"]
				for r in rotors:
					(r as Node3D).rotation.y += dt * 14.0

		if reached_core:
			if is_instance_valid(node):
				node.queue_free()
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
	for cell: Vector2i in _placed_towers:
		var t: Dictionary = _placed_towers[cell]
		var tid: String = str(t.get("id", "pulse"))
		var head: Node3D = t.get("head", null)
		var muzzle: Node3D = t.get("muzzle", null)

		var t_pos: Vector3 = cell_to_world_3d(cell) + Vector3(0.0, 0.45, 0.0)
		var rng: float = float(t.get("range", 180.0)) * PX_TO_WORLD
		var target_idx: int = _find_target_index(t_pos, rng)

		var aimed: bool = true
		if target_idx >= 0 and is_instance_valid(head) and tid != "cryo" and tid != "tesla":
			var ep: Vector3 = _enemies[target_idx]["pos"]
			var desired_yaw: float = atan2(ep.x - t_pos.x, ep.z - t_pos.z)
			var cur_yaw: float = float(t["yaw"])
			var new_yaw: float = lerp_angle(cur_yaw, desired_yaw, minf(1.0, dt * 14.0))
			t["yaw"] = new_yaw
			head.rotation.y = new_yaw
			if absf(angle_difference(new_yaw, desired_yaw)) > 0.14:
				aimed = false

		t["cooldown"] = maxf(0.0, float(t["cooldown"]) - dt)
		if float(t["cooldown"]) > 0.0 or target_idx < 0 or not aimed:
			continue

		var fire_rate: float = maxf(0.1, float(t.get("fire_rate", 1.0)))
		t["cooldown"] = 1.0 / fire_rate
		t["recoil"] = 1.0
		var dmg: float = float(t.get("damage", 12.0)) * (1.2 if _boost_set.has(cell) else 1.0)
		var is_crit: bool = false
		# Бонус Overdrive на ур. 5: +25% шанс крита x1.6 для Pulse, Laser и Railgun
		if int(t["level"]) >= MAX_TOWER_LEVEL and (tid == "pulse" or tid == "laser" or tid == "railgun"):
			if randf() < 0.25:
				dmg *= 1.6
				is_crit = true
		var fire_origin: Vector3 = muzzle.global_position if is_instance_valid(muzzle) else t_pos

		_fire_tower(tid, t, fire_origin, target_idx, dmg, is_crit)


func _find_target_index(origin: Vector3, rng: float) -> int:
	var best_idx: int = -1
	var best_prog: float = -1.0
	for i in _enemies.size():
		var e: Dictionary = _enemies[i]
		var ep: Vector3 = e["pos"]
		var flat_d: float = Vector2(ep.x - origin.x, ep.z - origin.z).length()
		if flat_d <= rng:
			if float(e["progress"]) > best_prog:
				best_prog = float(e["progress"])
				best_idx = i
	return best_idx


func _fire_tower(tid: String, cfg: Dictionary, origin: Vector3, target_idx: int, dmg: float, is_crit: bool) -> void:
	var target: Dictionary = _enemies[target_idx]
	var t_pos: Vector3 = (target["pos"] as Vector3) + Vector3(0.0, 0.30, 0.0)
	var col := Color("#FACC15") if is_crit else Color(str(cfg.get("color", "#00E5FF")))

	_spawn_muzzle_flash(origin, col)

	match tid:
		"pulse":
			sfx_requested.emit("pulse")
			_spawn_projectile(origin, t_pos, 12.0, dmg, "kinetic", 0.0, col, is_crit)
		"cannon":
			sfx_requested.emit("cannon")
			_spawn_projectile(origin, t_pos, 7.5, dmg, "explosive", float(cfg.get("aoe_radius", 72.0)) * PX_TO_WORLD, col, is_crit)
		"cryo":
			sfx_requested.emit("cryo")
			var rng: float = float(cfg.get("range", 170.0)) * PX_TO_WORLD
			var slow_f: float = 1.0 - float(cfg.get("slow_factor", 0.4))
			_spawn_ring_vfx(origin, rng, col, 0.28)
			var i: int = _enemies.size() - 1
			while i >= 0:
				var e: Dictionary = _enemies[i]
				var ep: Vector3 = e["pos"]
				if Vector2(ep.x - origin.x, ep.z - origin.z).length() <= rng:
					e["slow_factor"] = minf(float(e["slow_factor"]), slow_f)
					e["slow_timer"] = 2.6 + float(int(cfg["level"]) - 1) * 0.4
					_damage_enemy_at(i, dmg, "cryo", false)
				i -= 1
		"tesla":
			sfx_requested.emit("tesla")
			var max_chains: int = int(cfg.get("chain_count", 3))
			var hit_indices: Array[int] = [target_idx]
			var last_pos: Vector3 = t_pos
			_spawn_beam_vfx(origin, t_pos, 0.075, col, 0.16)
			for _c in range(max_chains - 1):
				var next_i: int = -1
				var best_d: float = 3.2
				for j in _enemies.size():
					if j in hit_indices:
						continue
					var d: float = (_enemies[j]["pos"] as Vector3).distance_to(last_pos)
					if d < best_d:
						best_d = d
						next_i = j
				if next_i >= 0:
					hit_indices.append(next_i)
					var next_pos: Vector3 = (_enemies[next_i]["pos"] as Vector3) + Vector3(0.0, 0.30, 0.0)
					_spawn_beam_vfx(last_pos, next_pos, 0.065, col, 0.16)
					last_pos = next_pos
				else:
					break
			hit_indices.sort()
			hit_indices.reverse()
			for hi in hit_indices:
				if hi < _enemies.size():
					_damage_enemy_at(hi, dmg, "electric", false)
		"laser":
			sfx_requested.emit("laser")
			_spawn_beam_vfx(origin, t_pos, 0.075, col, 0.12)
			_damage_enemy_at(target_idx, dmg, "thermal", is_crit)
		"railgun":
			sfx_requested.emit("railgun")
			_spawn_beam_vfx(origin, t_pos, 0.11, col, 0.24)
			_damage_enemy_at(target_idx, dmg, "pierce", is_crit)


func _spawn_muzzle_flash(pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.30
	mi.mesh = sm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _make_mat(col.lightened(0.4), 3.8, 0.95, 0.0, 0.1)
	if _vfx.size() < 16:
		var fl := OmniLight3D.new()
		fl.light_color = col
		fl.light_energy = 2.4
		fl.omni_range = 3.2
		mi.add_child(fl)
	_fx_root.add_child(mi)
	_vfx.append({"node": mi, "type": "beam", "ttl": 0.08, "max_ttl": 0.08})


func _spawn_projectile(origin: Vector3, dest: Vector3, spd: float, dmg: float, dtype: String, aoe: float, col: Color, is_crit: bool) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12 if aoe > 0.0 else 0.08
	sm.height = sm.radius * 2.0
	mi.mesh = sm
	mi.position = origin
	mi.material_override = _make_mat(col, 2.8, 1.0, 0.1, 0.1)
	_fx_root.add_child(mi)
	_projectiles.append({
		"node": mi, "pos": origin, "target_pos": dest, "speed": spd,
		"damage": dmg, "damage_type": dtype, "aoe": aoe, "color": col, "crit": is_crit
	})


func _spawn_beam_vfx(a: Vector3, b: Vector3, thickness: float, col: Color, ttl: float) -> void:
	var mat := _make_mat(col, 3.2, 0.95, 0.0, 0.1)
	var mi := _create_beam_mesh(a, b, thickness, mat)
	_fx_root.add_child(mi)
	_vfx.append({"node": mi, "type": "beam", "ttl": ttl, "max_ttl": ttl})


func _spawn_ring_vfx(pos: Vector3, radius: float, col: Color, ttl: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 28
	mi.mesh = tm
	mi.position = Vector3(pos.x, 0.18, pos.z)
	mi.scale = Vector3(0.2, 1.0, 0.2)
	mi.material_override = _make_mat(col, 2.6, 0.82, 0.0, 0.1)
	_fx_root.add_child(mi)
	_vfx.append({"node": mi, "type": "ring", "target_r": radius, "ttl": ttl, "max_ttl": ttl})


func _spawn_damage_label(pos: Vector3, dmg_val: int, col: Color, is_crit: bool = false) -> void:
	if _float_texts.size() > 28:
		return
	var lbl := Label3D.new()
	lbl.text = ("-%d!" % dmg_val) if is_crit else ("-%d" % dmg_val)
	lbl.font_size = 34 if is_crit else 28
	lbl.pixel_size = 0.012
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color("#FACC15") if is_crit else col
	lbl.outline_size = 4
	lbl.position = pos + Vector3(0.0, 0.95, 0.0)
	_fx_root.add_child(lbl)
	_float_texts.append({"node": lbl, "ttl": 0.55})


func _process_projectiles(dt: float) -> void:
	var i: int = _projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = _projectiles[i]
		var pos: Vector3 = p["pos"]
		var dest: Vector3 = p["target_pos"]
		var dir: Vector3 = dest - pos
		var dist: float = dir.length()
		var step: float = float(p["speed"]) * dt
		if dist <= step + 0.16:
			var aoe: float = float(p["aoe"])
			var is_crit: bool = bool(p.get("crit", false))
			if aoe > 0.0:
				_spawn_ring_vfx(dest, aoe, p["color"], 0.24)
				var j: int = _enemies.size() - 1
				while j >= 0:
					if (_enemies[j]["pos"] as Vector3).distance_to(dest) <= aoe:
						_damage_enemy_at(j, float(p["damage"]), str(p["damage_type"]), is_crit)
					j -= 1
			else:
				var hit_i: int = _find_closest_enemy(dest, 0.95)
				if hit_i >= 0:
					_damage_enemy_at(hit_i, float(p["damage"]), str(p["damage_type"]), is_crit)
			var node: Node3D = p["node"]
			if is_instance_valid(node):
				node.queue_free()
			_projectiles.remove_at(i)
		else:
			pos += dir.normalized() * step
			p["pos"] = pos
			var node: Node3D = p["node"]
			if is_instance_valid(node):
				node.position = pos
		i -= 1


func _find_closest_enemy(pos: Vector3, max_dist: float) -> int:
	var best_i: int = -1
	var best_d: float = max_dist
	for i in _enemies.size():
		var d: float = (_enemies[i]["pos"] as Vector3).distance_to(pos)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func _damage_enemy_at(idx: int, raw_dmg: float, dmg_type: String, is_crit: bool) -> void:
	if idx < 0 or idx >= _enemies.size():
		return
	var e: Dictionary = _enemies[idx]
	e["shield_regen_cd"] = 3.0
	var remaining: float = raw_dmg

	if float(e["shield"]) > 0.0:
		var shield_mult: float = 2.0 if dmg_type == "electric" else 1.0
		var shield_dmg: float = remaining * shield_mult
		if float(e["shield"]) >= shield_dmg:
			e["shield"] = float(e["shield"]) - shield_dmg
			_spawn_damage_label(e["pos"], int(roundf(shield_dmg)), Color("#38BDF8"), is_crit)
			return
		else:
			remaining -= float(e["shield"]) / shield_mult
			e["shield"] = 0.0

	var armor: float = float(e["armor"])
	var final_dmg: float = remaining
	if armor > 0.0 and dmg_type != "pierce" and dmg_type != "thermal":
		var reduction: float = minf(0.45, armor * 0.0375)
		final_dmg = maxf(1.0, remaining * (1.0 - reduction))
	e["hp"] = float(e["hp"]) - final_dmg
	_spawn_damage_label(e["pos"], int(roundf(final_dmg)), Color("#FCA5A5"), is_crit)

	var hb: MeshInstance3D = e["hp_bar"]
	if is_instance_valid(hb):
		var ratio: float = clampf(float(e["hp"]) / maxf(float(e["max_hp"]), 1.0), 0.02, 1.0)
		hb.visible = true
		hb.scale.x = ratio

	if float(e["hp"]) <= 0.0:
		var bounty: int = int(e["bounty"])
		var death_pos: Vector3 = e["pos"]
		var eid: String = str(e["id"])
		var pidx: int = int(e["path_idx"])
		var wp_idx: int = int(e["wp_idx"])
		var prog: float = float(e["progress"])
		var node: Node3D = e["node"]
		if is_instance_valid(node):
			node.queue_free()
		_enemies.remove_at(idx)
		_spawn_ring_vfx(death_pos, 0.75, Color("#F97316"), 0.22)
		enemy_killed.emit(bounty)

		if eid == "splitter":
			for off_x in [-0.25, 0.25]:
				var sw: Dictionary = _enemy_catalog.get("swarm", {"hp": 35, "speed": 140, "bounty": 4})
				var vis: Dictionary = _build_animated_enemy("swarm", false, false)
				var snode: Node3D = vis["root"]
				var spos: Vector3 = death_pos + Vector3(off_x, 0.0, 0.0)
				snode.position = spos
				_enemies_root.add_child(snode)
				_enemies.append({
					"id": "swarm", "pos": spos, "path_idx": pidx, "wp_idx": wp_idx, "progress": prog,
					"yaw": float(e["yaw"]), "walk_phase": randf() * TAU,
					"hp": float(sw.get("hp", 35)) * float(SettingsManager.get_difficulty_mods().get("hp_mult", 1.0)),
					"max_hp": float(sw.get("hp", 35)) * float(SettingsManager.get_difficulty_mods().get("hp_mult", 1.0)),
					"shield": 0.0, "max_shield": 0.0, "armor": 0.0,
					"speed": float(sw.get("speed", 140)) * PX_TO_WORLD * float(SettingsManager.get_difficulty_mods().get("speed_mult", 1.0)),
					"bounty": int(sw.get("bounty", 4)), "is_flying": false, "elite": false,
					"slow_timer": 0.0, "slow_factor": 1.0, "medic_cd": 99.0, "shield_regen_cd": 0.0,
					"node": snode, "parts": vis["parts"], "shield_mesh": null, "hp_bar": vis["hp_bar"]
				})


func _process_vfx(delta: float) -> void:
	var i: int = _vfx.size() - 1
	while i >= 0:
		var v: Dictionary = _vfx[i]
		v["ttl"] = float(v["ttl"]) - delta
		var node: Node3D = v["node"]
		if float(v["ttl"]) <= 0.0:
			if is_instance_valid(node):
				node.queue_free()
			_vfx.remove_at(i)
		elif str(v["type"]) == "ring" and is_instance_valid(node):
			var p: float = 1.0 - (float(v["ttl"]) / maxf(float(v["max_ttl"]), 0.01))
			var r: float = lerpf(0.2, float(v["target_r"]), p)
			node.scale = Vector3(r, 1.0, r)
		i -= 1


func _process_float_texts(delta: float) -> void:
	var i: int = _float_texts.size() - 1
	while i >= 0:
		var ft: Dictionary = _float_texts[i]
		ft["ttl"] = float(ft["ttl"]) - delta
		var node: Label3D = ft["node"]
		if float(ft["ttl"]) <= 0.0:
			if is_instance_valid(node):
				node.queue_free()
			_float_texts.remove_at(i)
		elif is_instance_valid(node):
			node.position.y += delta * 1.1
		i -= 1


func _clear_projectiles() -> void:
	for p in _projectiles:
		var node: Node3D = p.get("node", null)
		if is_instance_valid(node):
			node.queue_free()
	_projectiles.clear()


func _check_wave_completion() -> void:
	if _spawn_queue.is_empty() and _enemies.is_empty() and _wave_active:
		_wave_active = false
		_clear_projectiles()
		var w_data: Dictionary = _waves_data[_current_wave_idx]
		var bonus: int = int(w_data.get("bonus_gold", 20))
		wave_cleared.emit(bonus)
		wave_state_changed.emit(_current_wave_idx + 1, _waves_data.size(), false)
		if _current_wave_idx + 1 >= _waves_data.size():
			_ended = true
			level_victory.emit()
