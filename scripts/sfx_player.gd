class_name SfxPlayer
extends Node

## Процедурный генератор звуковых эффектов (WAV в памяти) без внешних аудиофайлов.
## Работает на Web (HTML5), Windows, Linux, macOS и Android, учитывая SettingsManager.

const SAMPLE_RATE: int = 22050
const POOL_SIZE: int = 8

var _streams: Dictionary = {} # name -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

	_streams["pulse"] = _make_tone(640.0, 260.0, 0.07, 0.28, "square")
	_streams["cannon"] = _make_tone(170.0, 52.0, 0.18, 0.40, "noise_mix")
	_streams["cryo"] = _make_tone(920.0, 1280.0, 0.11, 0.22, "sine")
	_streams["tesla"] = _make_tone(1100.0, 420.0, 0.10, 0.25, "saw")
	_streams["laser"] = _make_tone(520.0, 500.0, 0.06, 0.18, "sine")
	_streams["railgun"] = _make_tone(960.0, 110.0, 0.22, 0.42, "saw")
	_streams["place"] = _make_tone(340.0, 560.0, 0.08, 0.30, "sine")
	_streams["upgrade"] = _make_tone(420.0, 980.0, 0.16, 0.34, "sine")
	_streams["sell"] = _make_tone(520.0, 780.0, 0.09, 0.25, "sine")
	_streams["wave"] = _make_tone(280.0, 560.0, 0.24, 0.32, "saw")
	_streams["core_hit"] = _make_tone(220.0, 120.0, 0.25, 0.45, "square")


func play(sfx_name: String) -> void:
	if SettingsManager.muted or SettingsManager.master_volume <= 0.01 or SettingsManager.sfx_volume <= 0.01:
		return
	if not _streams.has(sfx_name):
		return
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	p.stream = _streams[sfx_name]
	var gain: float = SettingsManager.sfx_volume
	p.volume_db = linear_to_db(maxf(gain, 0.001))
	p.play()


func _make_tone(freq_start: float, freq_end: float, duration: float, amp: float, mode: String) -> AudioStreamWAV:
	var count: int = int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq_start * 100.0)

	for i in count:
		var t: float = float(i) / float(max(count, 1))
		var freq: float = lerpf(freq_start, freq_end, t)
		phase += TAU * freq / float(SAMPLE_RATE)
		var env: float = (1.0 - t) * (1.0 - t)
		var s: float = 0.0
		match mode:
			"square":
				s = 1.0 if sin(phase) >= 0.0 else -1.0
			"saw":
				s = 2.0 * (fmod(phase / TAU, 1.0)) - 1.0
			"noise_mix":
				s = 0.55 * sin(phase) + 0.45 * rng.randf_range(-1.0, 1.0)
			_:
				s = sin(phase)
		var sample_i16: int = clampi(int(s * env * amp * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample_i16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav
