extends Node3D

## 2.5D/3D Изометрический движок Neon Grid Defense (Godot 4.3 GL Compatibility):
## - Объёмная тёмно-металлическая 3D-доска с Glow/Bloom, оранжевыми 3D-порталами и неоновой трассой
## - Детализированные 2.5D изометрические спрайты (Sprite3D) для всех 6 башен, 7 врагов и Energy Core
## - Анимация отдачи башен при выстреле, зеркалирование по направлению цели/движения, 3D-лучи, молнии и урон

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

const TILE_SIZE: float = 1.0
const PX_TO_WORLD: float = 1.0 / 54.0

var grid_size := Vector2i(24, 14)
var current_level_data: Dictionary = {}
var spawns: Array[Vector2i] = []
var core_cell := Vector2i(23, 6)
var fixed_paths: Array = []
var walls: Array[Vector2i] = []
var boost_tiles: Array[Vector2i] = []

var input_enabled: bool = false
var selected_tower_config: Dictionary = {}
var game_speed: float = 1.0
var cores_remaining: int = 10

var _enemy_catalog: Dictionary = {}
var _tower_textures: Dictionary = {} # id -> Texture2D
var _enemy_textures: Dictionary = {} # id -> Texture2D
var _core_texture: Texture2D = null

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
var _core_sprite: Sprite3D
var _core_ring_a: MeshInstance3D
var _core_ring_b: MeshInstance3D
var _core_light: OmniLight3D

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


func _ready() -> void:
	_load_enemy_catalog()
	_preload_sprites()
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


func _preload_sprites() -> void:
	for tid in ["pulse", "cannon", "cryo", "tesla", "laser", "railgun"]:
		var p: String = "res://assets/sprites/towers/%s.png" % tid
		if ResourceLoader.exists(p):
			_tower_textures[tid] = load(p)
	for eid in ["swarm", "trooper", "armored", "shielded", "medic", "splitter", "drone"]:
		var p: String = "res://assets/sprites/enemies/%s.png" % eid
		if ResourceLoader.exists(p):
			_enemy_textures[eid] = load(p)
	if ResourceLoader.exists("res://assets/sprites/core.png"):
		_core_texture = load("res://assets/sprites/core.png")


func _setup_environment_and_camera() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#050810")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#1E3350")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.25
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#E0F0FF")
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-50.0, 38.0, 0.0)
	add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#00A8CC")
	rim.light_energy = 0.45
	rim.rotation_degrees = Vector3(-28.0, -140.0, 0.0)
	add_child(rim)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.1
	_camera.far = 160.0
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
	_hover_box.visible = false
	add_child(_hover_box)

	_range_ring = MeshInstance3D.new()
	var rmesh := TorusMesh.new()
	rmesh.inner_radius = 0.95
	rmesh.outer_radius = 1.0
	rmesh.rings = 48
	rmesh.ring_segments = 8
	_range_ring.mesh = rmesh
	_range_mat = _make_mat(Color("#00E5FF"), 2.0, 0.72)
	_range_ring.material_override = _range_mat
	_range_ring.visible = false
	add_child(_range_ring)


func _update_camera_fit() -> void:
	if not _camera:
		return
	var center := Vector3(float(grid_size.x) * 0.5, 0.0, float(grid_size.y) * 0.5)
	var offset := Vector3(0.0, 26.0, 21.0).rotated(Vector3.UP, deg_to_rad(30.0))
	_camera.look_at_from_position(center + offset, center + Vector3(0.0, -0.3, 0.6), Vector3.UP)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = maxf(vp.x / maxf(vp.y, 1.0), 0.5)
	var base_size: float = 22.8
	if aspect < 1.65:
		base_size = 22.8 * (1.65 / aspect)
	_camera.size = base_size


func _on_settings_changed() -> void:
	if _route_root:
		_route_root.visible = SettingsManager.show_path_preview


func set_selected_tower(tower_cfg: Dictionary) -> void:
	selected_tower_config = tower_cfg
	_update_hover_visuals()


func is_wave_active() -> bool:
	return _wave_active


func _make_mat(col: Color, emission_strength: float = 0.0, alpha: float = 1.0, metallic: float = 0.45, roughness: float = 0.40) -> StandardMaterial3D:
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
	cores_remaining = int(parsed.get("cores_count", 10))
	_waves_data = parsed.get("waves", [])

	fixed_paths.clear()
	for raw_p in parsed.get("paths", []):
		fixed_paths.append(_parse_vec2i_array(raw_p))

	_hover_cell = Vector2i(-1, -1)
	_hover_box.visible = false
	_range_ring.visible = false
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

	_init_grid_state()
	_build_3d_board()
	_build_3d_routes()
	_update_camera_fit()

	level_loaded.emit(current_level_data)
	wave_state_changed.emit(0, _waves_data.size(), false)
	return true


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
	_core_sprite = null
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

	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(0.90, 0.16, 0.90)
	var road_mesh := BoxMesh.new()
	road_mesh.size = Vector3(0.96, 0.09, 0.96)
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(0.88, 0.58, 0.88)

	var mat_empty := _make_mat(Color("#1A263A"), 0.0, 1.0, 0.62, 0.36)
	var mat_road := _make_mat(Color("#0D1C2E"), 0.10, 1.0, 0.45, 0.45)
	var mat_wall := _make_mat(Color("#2B3D56"), 0.05, 1.0, 0.70, 0.32)
	var mat_boost := _make_mat(Color("#103B34"), 0.45, 1.0, 0.50, 0.32)
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
	var ring_mat := _make_mat(Color("#00E5FF"), 2.6, 0.88, 0.1, 0.2)
	_core_ring_a = MeshInstance3D.new()
	var r1 := TorusMesh.new()
	r1.inner_radius = 0.80
	r1.outer_radius = 0.86
	r1.rings = 32
	_core_ring_a.mesh = r1
	_core_ring_a.position = Vector3(pos.x, 0.08, pos.z)
	_core_ring_a.material_override = ring_mat
	_board_root.add_child(_core_ring_a)

	_core_ring_b = MeshInstance3D.new()
	var r2 := TorusMesh.new()
	r2.inner_radius = 1.18
	r2.outer_radius = 1.24
	r2.rings = 36
	_core_ring_b.mesh = r2
	_core_ring_b.position = Vector3(pos.x, 0.04, pos.z)
	_core_ring_b.material_override = ring_mat
	_board_root.add_child(_core_ring_b)

	if _core_texture:
		_core_sprite = _make_billboard_sprite(_core_texture, 0.0085)
		_core_sprite.position = Vector3(pos.x, 0.95, pos.z)
		_board_root.add_child(_core_sprite)

	_core_light = OmniLight3D.new()
	_core_light.light_color = Color("#00E5FF")
	_core_light.light_energy = 3.0
	_core_light.omni_range = 7.0
	_core_light.position = Vector3(pos.x, 1.35, pos.z)
	_board_root.add_child(_core_light)


func _make_billboard_sprite(tex: Texture2D, px_size: float = 0.0062) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.pixel_size = px_size
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.transparent = true
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return sp


func _build_3d_routes() -> void:
	_clear_node_children(_route_root)
	var line_mat := _make_mat(Color("#00E5FF"), 3.0, 0.95, 0.1, 0.15)
	var joint_mesh := SphereMesh.new()
	joint_mesh.radius = 0.06
	joint_mesh.height = 0.12

	for path in fixed_paths:
		for i in range(path.size() - 1):
			var a: Vector3 = cell_to_world_3d(path[i]) + Vector3(0.0, -0.02, 0.0)
			var b: Vector3 = cell_to_world_3d(path[i + 1]) + Vector3(0.0, -0.02, 0.0)
			var seg := _create_beam_mesh(a, b, 0.10, line_mat)
			_route_root.add_child(seg)
			var cap := MeshInstance3D.new()
			cap.mesh = joint_mesh
			cap.position = b
			cap.material_override = line_mat
			_route_root.add_child(cap)
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

	if event is InputEventMouseMotion:
		var me: InputEventMouseMotion = event
		var cell: Vector2i = _raycast_mouse_to_cell(me.position)
		if cell != _hover_cell:
			_hover_cell = cell
			_can_place_hover = _is_buildable_cell(_hover_cell)
			_update_hover_visuals()

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		var cell: Vector2i = _raycast_mouse_to_cell(mb.position)
		if not _cells.has(cell):
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(cell)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(cell)


func _update_hover_visuals() -> void:
	if not input_enabled or not _cells.has(_hover_cell):
		_hover_box.visible = false
		_range_ring.visible = false
		return

	var pos: Vector3 = cell_to_world_3d(_hover_cell)
	_hover_box.visible = true
	_hover_box.position = Vector3(pos.x, 0.06, pos.z)
	var hcol := Color("#00E5FF") if _can_place_hover else Color("#FF3B5C")
	_hover_mat.albedo_color = Color(hcol.r, hcol.g, hcol.b, 0.35)
	_hover_mat.emission = hcol

	if _can_place_hover and not selected_tower_config.is_empty():
		var rng: float = float(selected_tower_config.get("range", 180.0)) * PX_TO_WORLD
		var tcol := Color(str(selected_tower_config.get("color", "#00E5FF")))
		_range_ring.visible = true
		_range_ring.position = Vector3(pos.x, 0.08, pos.z)
		_range_ring.scale = Vector3(rng, 1.0, rng)
		_range_mat.albedo_color = Color(tcol.r, tcol.g, tcol.b, 0.65)
		_range_mat.emission = tcol
	else:
		_range_ring.visible = false


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
	var tid: String = str(tower_cfg.get("id", "pulse"))
	var root_node := Node3D.new()
	root_node.position = cell_to_world_3d(cell)

	var sp: Sprite3D = null
	if _tower_textures.has(tid):
		sp = _make_billboard_sprite(_tower_textures[tid], 0.0064)
		sp.position = Vector3(0.0, 0.72, 0.0)
		root_node.add_child(sp)

	_towers_root.add_child(root_node)

	var runtime_cfg: Dictionary = tower_cfg.duplicate()
	runtime_cfg["cooldown"] = 0.0
	runtime_cfg["recoil"] = 0.0
	runtime_cfg["node"] = root_node
	runtime_cfg["sprite"] = sp
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
	_cells[cell] = CellType.BOOST if _boost_set.has(cell) else CellType.EMPTY
	_can_place_hover = _is_buildable_cell(_hover_cell)
	_update_hover_visuals()
	sfx_requested.emit("sell")


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
	_anim_time += delta
	if is_instance_valid(_core_sprite):
		_core_sprite.position.y = 0.95 + sin(_anim_time * 2.5) * 0.07
	if is_instance_valid(_core_ring_a):
		_core_ring_a.rotation.y = _anim_time * 1.1
	if is_instance_valid(_core_ring_b):
		_core_ring_b.rotation.y = -_anim_time * 0.7

	if _core_flash > 0.0:
		_core_flash = maxf(0.0, _core_flash - delta * 2.5)
		var c := Color("#FF3B5C") if _core_flash > 0.2 else Color.WHITE
		if is_instance_valid(_core_sprite):
			_core_sprite.modulate = c
		if is_instance_valid(_core_light):
			_core_light.light_color = Color("#FF3B5C") if _core_flash > 0.2 else Color("#00E5FF")

	var dt: float = delta * game_speed
	if _wave_active and not _ended:
		_wave_time += dt
		_process_spawns()
		_process_enemies(dt)
		_process_towers(dt)
		_process_projectiles(dt)
		_check_wave_completion()

	_process_vfx(delta)
	_process_float_texts(delta)


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
	var is_flying: bool = bool(base.get("is_flying", false))
	var start_pos: Vector3 = cell_to_world_3d(path_cells[0]) + Vector3(0.0, 1.15 if is_flying else 0.02, 0.0)
	var max_hp: float = float(base.get("hp", 80)) * hp_mult
	var max_shield: float = float(base.get("shield", 0)) * hp_mult
	var elite: bool = bool(item.get("elite", false))

	var visual: Dictionary = _build_enemy_sprite_node(eid, elite)
	var node: Node3D = visual["root"]
	node.position = start_pos
	_enemies_root.add_child(node)

	_enemies.append({
		"id": eid, "pos": start_pos, "path_idx": pidx, "wp_idx": 1, "progress": 0.0,
		"hp": max_hp, "max_hp": max_hp, "shield": max_shield, "max_shield": max_shield,
		"armor": float(base.get("armor", 0)), "speed": float(base.get("speed", 90)) * PX_TO_WORLD,
		"bounty": int(base.get("bounty", 8)), "is_flying": is_flying, "elite": elite,
		"slow_timer": 0.0, "slow_factor": 1.0, "medic_cd": 2.0, "shield_regen_cd": 0.0,
		"node": node, "sprite": visual["sprite"], "hp_bar": visual["hp_bar"]
	})


func _build_enemy_sprite_node(eid: String, elite: bool) -> Dictionary:
	var root := Node3D.new()
	var sc: float = 1.25 if elite else 1.0
	var px: float = 0.0056 * sc
	if eid == "swarm":
		px = 0.0042 * sc
	elif eid == "armored" or eid == "shielded":
		px = 0.0066 * sc

	var sp: Sprite3D = null
	if _enemy_textures.has(eid):
		sp = _make_billboard_sprite(_enemy_textures[eid], px)
		sp.position = Vector3(0.0, 0.62 * sc, 0.0)
		root.add_child(sp)

	var hp_bar := MeshInstance3D.new()
	var hbm := BoxMesh.new()
	hbm.size = Vector3(0.68, 0.07, 0.07)
	hp_bar.mesh = hbm
	hp_bar.position = Vector3(0.0, 1.25 * sc, 0.0)
	hp_bar.material_override = _make_mat(Color("#22C55E"), 1.8, 1.0, 0.0, 0.5)
	hp_bar.visible = false
	root.add_child(hp_bar)

	return {"root": root, "sprite": sp, "hp_bar": hp_bar}


func _process_enemies(dt: float) -> void:
	var core_pos: Vector3 = cell_to_world_3d(core_cell)
	var i: int = _enemies.size() - 1
	while i >= 0:
		var e: Dictionary = _enemies[i]
		var sp: Sprite3D = e["sprite"]
		if float(e["slow_timer"]) > 0.0:
			e["slow_timer"] = float(e["slow_timer"]) - dt
			if float(e["slow_timer"]) <= 0.0:
				e["slow_factor"] = 1.0
			if is_instance_valid(sp):
				sp.modulate = Color("#7DD3FC")
		elif is_instance_valid(sp):
			sp.modulate = Color.WHITE

		if float(e["max_shield"]) > 0.0:
			e["shield_regen_cd"] = maxf(0.0, float(e["shield_regen_cd"]) - dt)
			if float(e["shield_regen_cd"]) <= 0.0 and float(e["shield"]) < float(e["max_shield"]):
				e["shield"] = minf(float(e["max_shield"]), float(e["shield"]) + float(e["max_shield"]) * 0.12 * dt)

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
		var target_pos: Vector3 = core_pos

		if bool(e["is_flying"]):
			target_pos = core_pos + Vector3(0.0, 1.15, 0.0)
			var dir: Vector3 = target_pos - cur_pos
			var dist: float = dir.length()
			if dist <= spd * dt + 0.15:
				reached_core = true
			else:
				cur_pos += dir.normalized() * spd * dt
				e["progress"] = float(e["progress"]) + spd * dt
		else:
			var path_cells: Array = fixed_paths[int(e["path_idx"])]
			var wp_idx: int = int(e["wp_idx"])
			if wp_idx >= path_cells.size():
				reached_core = true
			else:
				target_pos = cell_to_world_3d(path_cells[wp_idx]) + Vector3(0.0, 0.02, 0.0)
				var dir: Vector3 = target_pos - cur_pos
				var dist: float = dir.length()
				if dist <= spd * dt:
					cur_pos = target_pos
					e["wp_idx"] = wp_idx + 1
					e["progress"] = float(e["progress"]) + dist
					if int(e["wp_idx"]) >= path_cells.size():
						reached_core = true
				else:
					cur_pos += dir.normalized() * spd * dt
					e["progress"] = float(e["progress"]) + spd * dt

		e["pos"] = cur_pos
		var node: Node3D = e["node"]
		if is_instance_valid(node):
			node.position = cur_pos
			if bool(e["is_flying"]):
				node.position.y = 1.15 + sin(_anim_time * 4.0 + float(i)) * 0.10
		if is_instance_valid(sp):
			var move_dx: float = target_pos.x - cur_pos.x
			if absf(move_dx) > 0.05:
				sp.flip_h = move_dx < 0.0

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
		var sp: Sprite3D = t.get("sprite", null)
		if float(t["recoil"]) > 0.0:
			t["recoil"] = maxf(0.0, float(t["recoil"]) - dt * 5.0)
			if is_instance_valid(sp):
				var s: float = 1.0 + float(t["recoil"]) * 0.14
				sp.scale = Vector3(s, s, s)

		t["cooldown"] = maxf(0.0, float(t["cooldown"]) - dt)
		if float(t["cooldown"]) > 0.0:
			continue

		var t_pos: Vector3 = cell_to_world_3d(cell) + Vector3(0.0, 0.55, 0.0)
		var rng: float = float(t.get("range", 180.0)) * PX_TO_WORLD
		var target_idx: int = _find_target_index(t_pos, rng)
		if target_idx < 0:
			continue

		var fire_rate: float = maxf(0.1, float(t.get("fire_rate", 1.0)))
		t["cooldown"] = 1.0 / fire_rate
		t["recoil"] = 1.0
		var dmg: float = float(t.get("damage", 12.0)) * (1.2 if _boost_set.has(cell) else 1.0)
		var tid: String = str(t.get("id", "pulse"))
		var target: Dictionary = _enemies[target_idx]
		var e_pos: Vector3 = target["pos"]

		if is_instance_valid(sp) and tid != "cryo" and tid != "tesla":
			sp.flip_h = (e_pos.x < t_pos.x)

		_fire_tower(tid, t, t_pos, target_idx, dmg)


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


func _fire_tower(tid: String, cfg: Dictionary, origin: Vector3, target_idx: int, dmg: float) -> void:
	var target: Dictionary = _enemies[target_idx]
	var t_pos: Vector3 = (target["pos"] as Vector3) + Vector3(0.0, 0.35, 0.0)
	var col := Color(str(cfg.get("color", "#00E5FF")))

	match tid:
		"pulse":
			sfx_requested.emit("pulse")
			_spawn_projectile(origin, t_pos, 11.5, dmg, "kinetic", 0.0, col)
		"cannon":
			sfx_requested.emit("cannon")
			_spawn_projectile(origin, t_pos, 7.2, dmg, "explosive", float(cfg.get("aoe_radius", 72.0)) * PX_TO_WORLD, col)
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
					e["slow_timer"] = 2.6
					_damage_enemy_at(i, dmg, "cryo")
				i -= 1
		"tesla":
			sfx_requested.emit("tesla")
			var max_chains: int = int(cfg.get("chain_count", 3))
			var hit_indices: Array[int] = [target_idx]
			var last_pos: Vector3 = t_pos
			_spawn_beam_vfx(origin + Vector3(0.0, 0.55, 0.0), t_pos, 0.08, col, 0.16)
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
					var next_pos: Vector3 = (_enemies[next_i]["pos"] as Vector3) + Vector3(0.0, 0.35, 0.0)
					_spawn_beam_vfx(last_pos, next_pos, 0.07, col, 0.16)
					last_pos = next_pos
				else:
					break
			hit_indices.sort()
			hit_indices.reverse()
			for hi in hit_indices:
				if hi < _enemies.size():
					_damage_enemy_at(hi, dmg, "electric")
		"laser":
			sfx_requested.emit("laser")
			_spawn_beam_vfx(origin, t_pos, 0.07, col, 0.12)
			_damage_enemy_at(target_idx, dmg, "thermal")
		"railgun":
			sfx_requested.emit("railgun")
			_spawn_beam_vfx(origin, t_pos, 0.11, col, 0.24)
			_damage_enemy_at(target_idx, dmg, "pierce")


func _spawn_projectile(origin: Vector3, dest: Vector3, spd: float, dmg: float, dtype: String, aoe: float, col: Color) -> void:
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
		"damage": dmg, "damage_type": dtype, "aoe": aoe, "color": col
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


func _spawn_damage_label(pos: Vector3, dmg_val: int, col: Color) -> void:
	if _float_texts.size() > 28:
		return
	var lbl := Label3D.new()
	lbl.text = "-%d" % dmg_val
	lbl.font_size = 28
	lbl.pixel_size = 0.012
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = col
	lbl.outline_size = 4
	lbl.position = pos + Vector3(0.0, 1.15, 0.0)
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
			if aoe > 0.0:
				_spawn_ring_vfx(dest, aoe, p["color"], 0.24)
				var j: int = _enemies.size() - 1
				while j >= 0:
					if (_enemies[j]["pos"] as Vector3).distance_to(dest) <= aoe:
						_damage_enemy_at(j, float(p["damage"]), str(p["damage_type"]))
					j -= 1
			else:
				var hit_i: int = _find_closest_enemy(dest, 0.95)
				if hit_i >= 0:
					_damage_enemy_at(hit_i, float(p["damage"]), str(p["damage_type"]))
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


func _damage_enemy_at(idx: int, raw_dmg: float, dmg_type: String) -> void:
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
			_spawn_damage_label(e["pos"], int(roundf(shield_dmg)), Color("#38BDF8"))
			return
		else:
			remaining -= float(e["shield"]) / shield_mult
			e["shield"] = 0.0

	var armor: float = float(e["armor"])
	if dmg_type == "pierce" or dmg_type == "thermal":
		armor = 0.0
	var final_dmg: float = maxf(1.0, remaining - armor * 0.6)
	e["hp"] = float(e["hp"]) - final_dmg
	_spawn_damage_label(e["pos"], int(roundf(final_dmg)), Color("#FCA5A5"))

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
				var vis: Dictionary = _build_enemy_sprite_node("swarm", false)
				var snode: Node3D = vis["root"]
				var spos: Vector3 = death_pos + Vector3(off_x, 0.0, 0.0)
				snode.position = spos
				_enemies_root.add_child(snode)
				_enemies.append({
					"id": "swarm", "pos": spos, "path_idx": pidx, "wp_idx": wp_idx, "progress": prog,
					"hp": float(sw.get("hp", 35)), "max_hp": float(sw.get("hp", 35)),
					"shield": 0.0, "max_shield": 0.0, "armor": 0.0,
					"speed": float(sw.get("speed", 140)) * PX_TO_WORLD,
					"bounty": int(sw.get("bounty", 4)), "is_flying": false, "elite": false,
					"slow_timer": 0.0, "slow_factor": 1.0, "medic_cd": 99.0, "shield_regen_cd": 0.0,
					"node": snode, "sprite": vis["sprite"], "hp_bar": vis["hp_bar"]
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
