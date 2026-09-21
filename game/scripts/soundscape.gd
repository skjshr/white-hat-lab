extends Node
## Local office sound layer. Room beds remain lightweight PCM; office music is
## a finite playlist of public-domain/CC0 classical recordings.

const AUDIO_ROOT := "res://assets/audio/studio/"
const MUSIC_TRACKS := [
	"res://assets/audio/classical/goldberg_aria.ogg",
	"res://assets/audio/classical/goldberg_variation_1.ogg",
	"res://assets/audio/classical/goldberg_variation_3.ogg",
	"res://assets/audio/classical/goldberg_variation_4.ogg",
	"res://assets/audio/classical/goldberg_variation_6.ogg",
	"res://assets/audio/classical/satie_gnossienne_1.ogg",
]
const MUSIC_TITLES := {
	"goldberg_aria": "Bach - Goldberg Variations: Aria",
	"goldberg_variation_1": "Bach - Goldberg Variations: Variation 1",
	"goldberg_variation_3": "Bach - Goldberg Variations: Variation 3",
	"goldberg_variation_4": "Bach - Goldberg Variations: Variation 4",
	"goldberg_variation_6": "Bach - Goldberg Variations: Variation 6",
	"satie_gnossienne_1": "Satie - Gnossienne No. 1",
}
## Source recordings have different mastering levels. These small per-track
## trims bring their measured integrated levels close together while leaving
## the original recordings untouched and preserving the existing music slider.
const MUSIC_GAIN_DB := {
	"goldberg_aria": 5.5,
	"goldberg_variation_1": -4.3,
	"goldberg_variation_3": -1.6,
	"goldberg_variation_4": -3.2,
	"goldberg_variation_6": 2.1,
	"satie_gnossienne_1": -1.9,
}
const EVENTS := {
	"click": "ui_click.wav",
	"hover": "ui_hover.wav",
	"typing": "typing.wav",
	"receipt_positive": "receipt_positive.wav",
	"receipt_negative": "receipt_negative.wav",
	"work_success": "receipt_positive.wav",
	"work_failure": "receipt_negative.wav",
	"footstep": "footstep.wav",
	"staff_arrival": "res://assets/audio/confirmation_001.ogg",
	"staff_departure": "res://assets/audio/close_001.ogg",
	"coffee_pour": "__coffee_pour",
	"coffee_sip": "__coffee_sip",
	"coffee_setdown": "__coffee_setdown",
}
const DEFAULT_EFFECTS := 65.0
const DEFAULT_AMBIENT := 12.0
const DEFAULT_MUSIC := 35.0
const TYPE_INTERVAL := 0.045
const EVENT_INTERVAL := 0.028
const PCM_RATE := 22050

var effects_volume := DEFAULT_EFFECTS
var ambient_volume := DEFAULT_AMBIENT
var music_volume := DEFAULT_MUSIC
var master_volume := 100.0
var workspace_active := false
var _streams: Dictionary = {}
var _generated_streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _ambient: AudioStreamPlayer
var _music: AudioStreamPlayer
var _spatial_sources: Array[AudioStreamPlayer3D] = []
var _last_event: Dictionary = {}
var _last_typing := -100.0
var _focused := true
var _working_colleagues := 0
var _world_parent: Node3D
var _title_active := false
var _paused := false
var _music_target_db := -80.0
var _music_position := 0.0
var _music_current_path := ""
var _music_bag: Array[String] = []

func _ready() -> void:
	for i in 6:
		var player := AudioStreamPlayer.new()
		player.name = "EffectPlayer%d" % i
		add_child(player)
		_players.append(player)
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "WorkspaceRoomtone"
	_ambient.finished.connect(_restart_ambient)
	add_child(_ambient)
	_music = AudioStreamPlayer.new()
	_music.name = "OfficeBGM"
	_music.finished.connect(_restart_music)
	add_child(_music)
	set_settings(Game.settings)
	Game.changed.connect(func(): set_settings(Game.settings))

func set_settings(settings: Dictionary) -> void:
	master_volume = clampf(float(settings.get("volume", 100)), 0.0, 100.0)
	effects_volume = clampf(float(settings.get("effects_volume", DEFAULT_EFFECTS)), 0.0, 100.0)
	ambient_volume = clampf(float(settings.get("ambient_volume", DEFAULT_AMBIENT)), 0.0, 100.0)
	music_volume = clampf(float(settings.get("music_volume", DEFAULT_MUSIC)), 0.0, 100.0)
	_update_volumes()
	if master_volume <= 0.0 or effects_volume <= 0.0:
		_stop_effects()
	_sync_ambient()
	_sync_music()

func set_workspace(active: bool) -> void:
	workspace_active = active
	if not active:
		_stop_effects()
		_stop_ambient()
	else:
		_sync_ambient()
	_sync_music()

func set_title_active(active: bool) -> void:
	_title_active = active
	_sync_music()

func set_paused(paused: bool) -> void:
	_paused = paused
	_sync_music()

func set_activity(working_count: int) -> void:
	# Keyboard activity is mixed into the spatial layer only when colleagues are
	# actually assigned.  The low idle value leaves a lived-in office without a
	# repetitive loop demanding attention.
	_working_colleagues = clampi(working_count, 0, 2)
	_update_spatial_volumes()

func mount_world(parent: Node3D) -> void:
	if not is_instance_valid(parent): return
	if _world_parent == parent and not _spatial_sources.is_empty(): return
	_stop_ambient()
	for source in _spatial_sources:
		if is_instance_valid(source): source.queue_free()
	_spatial_sources.clear()
	_world_parent = parent
	var keyboard := AudioStreamPlayer3D.new()
	keyboard.name = "ColleagueKeyboardAmbience"
	keyboard.position = Vector3(2.8, 1.05, -2.8)
	keyboard.max_distance = 15.0
	keyboard.unit_size = 5.0
	keyboard.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	keyboard.stream = _get_stream("__ambient_keyboard")
	parent.add_child(keyboard)
	_spatial_sources.append(keyboard)
	var exterior := AudioStreamPlayer3D.new()
	exterior.name = "WindowExteriorAmbience"
	exterior.position = Vector3(-6.4, 1.5, 0.0)
	exterior.max_distance = 18.0
	exterior.unit_size = 5.0
	exterior.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	exterior.stream = _get_stream("__ambient_exterior")
	parent.add_child(exterior)
	_spatial_sources.append(exterior)
	_update_spatial_volumes()
	_sync_ambient()

func unmount_world(parent: Node3D) -> void:
	if _world_parent != parent: return
	_stop_ambient()
	for source in _spatial_sources:
		if is_instance_valid(source): source.queue_free()
	_spatial_sources.clear()
	_world_parent = null

func play_ui(event: String) -> void:
	if master_volume <= 0.0 or effects_volume <= 0.0 or not _focused:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if event == "typing":
		if now - _last_typing < TYPE_INTERVAL:
			return
		_last_typing = now
	else:
		var last := float(_last_event.get(event, -100.0))
		if now - last < EVENT_INTERVAL:
			return
		_last_event[event] = now
	if not EVENTS.has(event):
		return
	var stream: AudioStream = _get_stream(EVENTS[event])
	if stream == null:
		return
	var player := _next_player()
	player.stream = stream
	player.volume_db = _effect_db() + _event_offset(event)
	player.play()

func _event_offset(event: String) -> float:
	if event == "coffee_pour": return -7.0
	if event == "coffee_sip": return -9.0
	if event == "coffee_setdown": return -5.0
	return 0.0

func _get_stream(filename: String) -> AudioStream:
	if _streams.has(filename):
		return _streams[filename]
	if _generated_streams.has(filename):
		return _generated_streams[filename]
	var stream: AudioStream
	if filename.begins_with("__"):
		stream = _make_generated_stream(filename)
		if stream != null: _generated_streams[filename] = stream
	else:
		var path := filename if filename.begins_with("res://") else AUDIO_ROOT + filename
		stream = load(path) as AudioStream
		if stream != null: _streams[filename] = stream
	return stream

func _next_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return _players[0]

func _play_ambient() -> void:
	var stream := _get_stream("roomtone.wav")
	if stream == null: return
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_ambient.stream = stream
	_ambient.volume_db = _ambient_db()
	_ambient.play()

func _restart_ambient() -> void:
	_sync_ambient()

func _restart_music() -> void:
	_music_position = 0.0
	_select_next_music()
	_sync_music()

func _sync_ambient() -> void:
	var enabled := workspace_active and _focused and master_volume > 0.0 and ambient_volume > 0.0
	if not enabled:
		_stop_ambient()
		return
	if _ambient != null and not _ambient.playing:
		_play_ambient()
	for source in _spatial_sources:
		if is_instance_valid(source):
			if source.stream != null and not source.playing: source.play()

func _sync_music() -> void:
	var enabled := workspace_active and _focused and not _title_active and not _paused and master_volume > 0.0 and music_volume > 0.0
	if enabled and _music_current_path.is_empty(): _select_next_music()
	_music_target_db = _music_db() + _music_gain_db() if enabled else -80.0
	if not enabled and _music != null and _music.playing and (_music.volume_db <= -78.0 or master_volume <= 0.0 or music_volume <= 0.0):
		_stop_music()
	if enabled and _music != null and not _music.playing:
		var stream := _get_stream(_music_current_path)
		if stream == null: return
		_music.stream = stream
		_music.volume_db = -80.0
		_music.play(_music_position)

func _select_next_music() -> void:
	if MUSIC_TRACKS.is_empty():
		_music_current_path = ""
		return
	if _music_current_path.is_empty() and _music_bag.is_empty():
		_music_current_path = str(MUSIC_TRACKS[0])
		for index in range(1, MUSIC_TRACKS.size()): _music_bag.append(str(MUSIC_TRACKS[index]))
		_music_bag.shuffle()
		return
	if _music_bag.is_empty():
		for track in MUSIC_TRACKS:
			if str(track) != _music_current_path: _music_bag.append(str(track))
		_music_bag.shuffle()
	if _music_bag.is_empty():
		_music_bag.append_array(MUSIC_TRACKS)
	_music_current_path = _music_bag.pop_back()

func next_music_track() -> void:
	# Selection is independent from mute/pause: the caller can preview the next
	# title without resuming playback or changing the saved music volume.
	if _music != null and _music.playing: _stop_music()
	_music_position = 0.0
	_select_next_music()
	if _music != null and _music_target_db > -79.0: _sync_music()

func current_music_title() -> String:
	if _music_current_path.is_empty(): return ""
	var key := _music_current_path.get_file().get_basename()
	return str(MUSIC_TITLES.get(key, key))

func _music_gain_db() -> float:
	if _music_current_path.is_empty(): return 0.0
	return float(MUSIC_GAIN_DB.get(_music_current_path.get_file().get_basename(), 0.0))

func _process(delta: float) -> void:
	if _music == null: return
	_music.volume_db = move_toward(_music.volume_db, _music_target_db, delta * 30.0)
	if _music_target_db <= -79.0 and _music.playing and _music.volume_db <= -79.0:
		_stop_music()

func _stop_music() -> void:
	if _music != null and _music.playing:
		_music_position = _music.get_playback_position()
		_music.stop()

func _update_volumes() -> void:
	for player in _players:
		player.volume_db = _effect_db()
	if _ambient != null:
		_ambient.volume_db = _ambient_db()
	_update_spatial_volumes()

func _update_spatial_volumes() -> void:
	if _spatial_sources.size() >= 1:
		# The generated keyboard stream is already normalized.  Apply the user's
		# ambient level once and add only a small colleague activity lift; the old
		# mix applied two extra attenuations and was effectively inaudible at the
		# default 50% master / 12% ambient settings.
		var keyboard_mix := 1.0 + 0.12 * float(_working_colleagues)
		if is_instance_valid(_spatial_sources[0]): _spatial_sources[0].volume_db = _ambient_db() + linear_to_db(keyboard_mix)
	if _spatial_sources.size() >= 2:
		if is_instance_valid(_spatial_sources[1]): _spatial_sources[1].volume_db = _ambient_db()

func _effect_db() -> float:
	return _percent_db(master_volume * effects_volume / 100.0)

func _ambient_db() -> float:
	return _percent_db(master_volume * ambient_volume / 100.0)

func _music_db() -> float:
	return _percent_db(master_volume * music_volume / 100.0)

func _percent_db(percent: float) -> float:
	if percent <= 0.01:
		return -80.0
	return linear_to_db(percent / 100.0)

func _stop_effects() -> void:
	for player in _players:
		player.stop()

func _stop_ambient() -> void:
	if _ambient != null: _ambient.stop()
	for source in _spatial_sources:
		if is_instance_valid(source): source.stop()

func _make_generated_stream(kind: String) -> AudioStreamWAV:
	if kind == "__ambient_keyboard":
		return _make_keyboard_loop()
	var seconds := 0.8
	var looped := false
	if kind == "__ambient_keyboard":
		seconds = 8.0; looped = true
	elif kind == "__ambient_exterior":
		seconds = 12.0; looped = true
	elif kind == "__coffee_pour":
		seconds = 0.92
	elif kind == "__coffee_sip":
		seconds = 0.68
	elif kind == "__coffee_setdown":
		seconds = 0.20
	else:
		return null
	var sample_count := int(seconds * PCM_RATE)
	var target_peak := 0.35 if kind.begins_with("__coffee_") else 0.25
	var raw_peak := 0.0
	for i in sample_count:
		# Measure first, then normalize the generated noise/transient as a whole
		# so each event has a known source peak without clipping at 100% volume.
		raw_peak = maxf(raw_peak, absf(_generated_sample(kind, float(i) / float(PCM_RATE), seconds)))
	var source_gain := target_peak / maxf(raw_peak, 0.000001)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(PCM_RATE)
		var sample := _generated_sample(kind, t, seconds) * source_gain
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = PCM_RATE
	stream.stereo = false
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = sample_count
	return stream

func _make_keyboard_loop() -> AudioStreamWAV:
	# Reuse the original procedural typing.wav recording as each key transient;
	# the sparse schedule keeps it recognizable as a coworker without a machine
	# gun loop or a synthetic pitched sequence.
	var source := _get_stream("typing.wav") as AudioStreamWAV
	var sample_count := int(8.0 * PCM_RATE)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	if source == null: return null
	var source_peak := 0
	for j in range(0, source.data.size(), 2):
		source_peak = maxi(source_peak, absi(source.data.decode_s16(j)))
	var source_gain := 0.25 * 32767.0 / float(maxi(source_peak, 1))
	for onset in [0.24, 0.81, 1.42, 2.05, 2.76, 3.30, 4.04, 4.73, 5.61, 6.18, 7.24]:
		var start := int(float(onset) * PCM_RATE)
		# Imported WAV data can differ between editor and exported builds.  Measure
		# the decoded peak rather than assuming the small source file is normalized.
		var gain := source_gain * (0.96 + 0.04 * sin(float(start) * 0.00017))
		var copy_count := mini(source.data.size(), bytes.size() - start * 2)
		for j in range(0, copy_count, 2):
			var sample := int(float(source.data.decode_s16(j)) * gain)
			var at := start * 2 + j
			var mixed := clampi(bytes.decode_s16(at) + sample, -32767, 32767)
			bytes.encode_s16(at, mixed)
	# Overlapping source slices can exceed the target by a small amount.  Apply a
	# final bounded pass so the stream remains below 0.25 peak in every build.
	var mixed_peak := 0
	for j in range(0, bytes.size(), 2): mixed_peak = maxi(mixed_peak, absi(bytes.decode_s16(j)))
	if mixed_peak > 0:
		var final_gain := (0.25 * 32767.0) / float(mixed_peak)
		for j in range(0, bytes.size(), 2):
			bytes.encode_s16(j, int(clampf(float(bytes.decode_s16(j)) * final_gain, -32767.0, 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = PCM_RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream

func _noise_at(cell: int, seed: int) -> float:
	var value := int(cell * 1103515245 + seed * 12345 + 1013904223)
	value = value ^ (value >> 13)
	value = value * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0x7fffffff) / 1073741824.0 - 1.0

func _smooth_noise(t: float, seed: int, step: float) -> float:
	var cell := floori(t / step)
	var fraction := clampf((t - float(cell) * step) / step, 0.0, 1.0)
	var fade := fraction * fraction * (3.0 - 2.0 * fraction)
	return lerpf(_noise_at(cell, seed), _noise_at(cell + 1, seed), fade)

func _generated_sample(kind: String, t: float, seconds: float) -> float:
	if kind == "__coffee_pour":
		var env := minf(1.0, t / 0.035) * minf(1.0, (seconds - t) / 0.16)
		var body := _smooth_noise(t, 41, 0.009) * 0.095 + _smooth_noise(t, 97, 0.0024) * 0.035
		var droplet_gate := maxf(0.0, sin(t * 31.0) * sin(t * 7.3))
		var droplets := _smooth_noise(t, 211, 0.0012) * droplet_gate * 0.050
		return (body + droplets) * env
	if kind == "__coffee_sip":
		var env := minf(1.0, t / 0.025) * minf(1.0, (seconds - t) / 0.12)
		var pulses := 0.55 + 0.45 * sin(t * 11.0)
		var sip := _smooth_noise(t, 307, 0.006) * 0.060 + _smooth_noise(t, 509, 0.0018) * 0.026
		return sip * env * pulses
	if kind == "__coffee_setdown":
		var env := exp(-24.0 * t)
		return (_smooth_noise(t, 617, 0.004) * 0.16 + _smooth_noise(t, 719, 0.0015) * 0.035) * env
	if kind == "__ambient_keyboard":
		# Sparse, rounded key taps: a stable loop without a constant hiss.
		var tap := 0.0
		for onset in [0.24, 0.81, 1.42, 2.05, 2.76, 3.30, 4.04, 4.73, 5.61, 6.18, 7.24]:
			var age := t - float(onset)
			if age >= 0.0 and age < 0.06:
				tap += sin(2.0 * PI * (150.0 + age * 210.0) * age) * exp(-42.0 * age) * 0.12
		return tap
	if kind == "__ambient_exterior":
		# Distant road wash and two occasional bird-like tones are intentionally
		# quiet; the window source provides localization without a harsh noise bed.
		var traffic_envelope := 0.55 + 0.45 * _smooth_noise(t, 811, 1.6)
		var traffic := (_smooth_noise(t, 823, 0.13) * 0.018 + _smooth_noise(t, 829, 0.035) * 0.009) * traffic_envelope
		var bird := 0.0
		for onset in [1.9, 7.4]:
			var age := t - float(onset)
			if age >= 0.0 and age < 0.32:
				bird += (_smooth_noise(age, 907, 0.004) * 0.016 + sin(2.0 * PI * (1200.0 + age * 420.0) * age) * 0.004) * exp(-8.0 * age)
		return traffic + bird
	return 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_stop_effects()
		_stop_ambient()
		_sync_music()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		_sync_ambient()
		_sync_music()
