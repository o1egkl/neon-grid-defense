extends Node

## Autoload-синглтон SettingsManager:
## - Загружает и хранит 7 языков из res://data/localization.json
## - Сохраняет настройки (язык, громкость, визуальные флаги) в user://settings.json
## - Применяет громкость к AudioServer и рассылает сигналы обновления UI

signal language_changed(lang_code: String)
signal difficulty_changed(diff_id: String)
signal settings_changed()

const SAVE_PATH := "user://settings.json"
const LOC_PATH := "res://data/localization.json"

var languages: Array = []
var _strings: Dictionary = {}

var language: String = "en"
var master_volume: float = 0.8
var sfx_volume: float = 0.85
var music_volume: float = 0.65
var muted: bool = false
var show_path_preview: bool = true
var show_grid_lines: bool = true
var default_speed: int = 1
var difficulty: String = "easy"
var completed_levels: Array = []


func _ready() -> void:
	_load_localization()
	_load_settings()
	_apply_audio()


func _load_localization() -> void:
	if not FileAccess.file_exists(LOC_PATH):
		push_error("Localization file missing: " + LOC_PATH)
		return
	var file := FileAccess.open(LOC_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		languages = parsed.get("languages", [])
		_strings = parsed.get("strings", {})


func tr_key(key: String) -> String:
	var lang_dict: Dictionary = _strings.get(language, {})
	if lang_dict.has(key):
		return str(lang_dict[key])
	var fallback: Dictionary = _strings.get("en", {})
	if fallback.has(key):
		return str(fallback[key])
	return key


func set_language(code: String) -> void:
	if not _strings.has(code):
		return
	if language != code:
		language = code
		save_settings()
		language_changed.emit(language)
		settings_changed.emit()


func set_master_volume(val: float) -> void:
	master_volume = clampf(val, 0.0, 1.0)
	_apply_audio()
	save_settings()
	settings_changed.emit()


func set_sfx_volume(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)
	_apply_audio()
	save_settings()
	settings_changed.emit()


func set_music_volume(val: float) -> void:
	music_volume = clampf(val, 0.0, 1.0)
	_apply_audio()
	save_settings()
	settings_changed.emit()


func set_muted(val: bool) -> void:
	muted = val
	_apply_audio()
	save_settings()
	settings_changed.emit()


func set_show_path_preview(val: bool) -> void:
	show_path_preview = val
	save_settings()
	settings_changed.emit()


func set_show_grid_lines(val: bool) -> void:
	show_grid_lines = val
	save_settings()
	settings_changed.emit()


func is_fast_speed_unlocked() -> bool:
	return completed_levels.size() >= 20


func get_completed_count() -> int:
	return completed_levels.size()


func is_level_completed(level_id: int) -> bool:
	return level_id in completed_levels


func is_level_unlocked(level_id: int) -> bool:
	if level_id <= 1:
		return true
	return is_level_completed(level_id) or is_level_completed(level_id - 1)


func mark_level_completed(level_id: int) -> void:
	if level_id < 1 or level_id > 20:
		return
	if not (level_id in completed_levels):
		completed_levels.append(level_id)
		completed_levels.sort()
		save_settings()
		settings_changed.emit()


func reset_progress() -> void:
	completed_levels.clear()
	default_speed = 1
	save_settings()
	settings_changed.emit()


func set_default_speed(val: int) -> void:
	if not is_fast_speed_unlocked():
		default_speed = 1
	else:
		default_speed = clampi(val, 1, 3)
	save_settings()
	settings_changed.emit()


func set_difficulty(diff_id: String) -> void:
	if diff_id != "easy" and diff_id != "hard" and diff_id != "nightmare":
		return
	if difficulty != diff_id:
		difficulty = diff_id
		save_settings()
		difficulty_changed.emit(difficulty)
		settings_changed.emit()


func get_difficulty_mods() -> Dictionary:
	match difficulty:
		"hard":
			return {"id": "hard", "hp_mult": 1.85, "speed_mult": 1.12, "spawn_int_mult": 0.85, "gold_mult": 0.80, "bounty_mult": 0.85, "interest_rate": 0.02, "cores": 10, "color": "#F59E0B"}
		"nightmare":
			return {"id": "nightmare", "hp_mult": 2.75, "speed_mult": 1.25, "spawn_int_mult": 0.72, "gold_mult": 0.70, "bounty_mult": 0.75, "interest_rate": 0.00, "cores": 5, "color": "#EF4444"}
		_:
			return {"id": "easy", "hp_mult": 0.95, "speed_mult": 0.95, "spawn_int_mult": 1.00, "gold_mult": 1.00, "bounty_mult": 1.00, "interest_rate": 0.05, "cores": 15, "color": "#10B981"}


func _apply_audio() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, muted or master_volume <= 0.001)
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(master_volume, 0.0001)))


func save_settings() -> void:
	var data := {
		"language": language,
		"master_volume": master_volume,
		"sfx_volume": sfx_volume,
		"music_volume": music_volume,
		"muted": muted,
		"show_path_preview": show_path_preview,
		"show_grid_lines": show_grid_lines,
		"default_speed": default_speed,
		"difficulty": difficulty,
		"completed_levels": completed_levels
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func _load_settings() -> void:
	# Автоопределение языка системы при первом запуске
	var os_locale := OS.get_locale_language().to_lower()
	if _strings.has(os_locale):
		language = os_locale

	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var saved_lang := str(parsed.get("language", language))
	if _strings.has(saved_lang):
		language = saved_lang
	master_volume = float(parsed.get("master_volume", master_volume))
	sfx_volume = float(parsed.get("sfx_volume", sfx_volume))
	music_volume = float(parsed.get("music_volume", music_volume))
	muted = bool(parsed.get("muted", muted))
	show_path_preview = bool(parsed.get("show_path_preview", show_path_preview))
	show_grid_lines = bool(parsed.get("show_grid_lines", show_grid_lines))
	default_speed = int(parsed.get("default_speed", default_speed))
	var saved_diff := str(parsed.get("difficulty", difficulty))
	if saved_diff == "easy" or saved_diff == "hard" or saved_diff == "nightmare":
		difficulty = saved_diff
	var raw_comp: Variant = parsed.get("completed_levels", [])
	completed_levels.clear()
	if raw_comp is Array:
		for lid in raw_comp:
			var iv: int = int(lid)
			if iv >= 1 and iv <= 20 and not (iv in completed_levels):
				completed_levels.append(iv)
	if not is_fast_speed_unlocked():
		default_speed = 1
