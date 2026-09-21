extends SceneTree

var failures: Array[String] = []
var sound
var game
var capture: AudioEffectCapture

func _init() -> void:
	call_deferred("run")
	create_timer(55).timeout.connect(func(): push_error("audio timeout"); quit(2))

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); print("FAIL ", message)

func samples() -> float:
	var buffer := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for value in buffer: peak = maxf(peak, maxf(absf(value.x), absf(value.y)))
	return peak

func wait_for_audio_peak(limit_seconds: float = 8.0) -> float:
	# Some licensed performances intentionally open with several seconds of
	# near-silence. Keep sampling the real mixer until a frame is audible rather
	# than treating that musical intro as a broken audio device.
	var peak := 0.0
	var elapsed := 0.0
	while elapsed < limit_seconds:
		peak = maxf(peak, samples())
		if peak > 0.0001: return peak
		await create_timer(0.25).timeout
		elapsed += 0.25
	return peak

func run() -> void:
	await process_frame
	game = root.get_node("Game")
	sound = root.get_node("Soundscape")
	check(game.settings_path.begins_with("user://qa-"), "isolated settings")
	game.set_process(false)
	game.set_settings({"volume": 50, "music_volume": 35, "effects_volume": 0, "ambient_volume": 0}, true)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(game.settings_path))
	check(int(saved.get("music_volume", -1)) == 35, "music volume persists")
	capture = AudioEffectCapture.new()
	# Keep the full startup window; the untouched recording begins with 1.5 s
	# of silence, which otherwise fills a one-second capture before the read.
	capture.buffer_length = 8.0
	AudioServer.add_bus_effect(0, capture)
	sound.set_workspace(true)
	sound.set_title_active(false)
	sound.set_paused(false)
	await create_timer(3).timeout
	check(sound._music.stream is AudioStreamOggVorbis and sound._music.stream.get_length() > 240, "bundled full-length music loads")
	check(sound._music.playing and sound._music.get_playback_position() > 1, "music advances")
	var peak: float = await wait_for_audio_peak()
	check(peak > 0.0001 and peak < 1, "music produces unclipped mixed samples")
	var before: float = sound._music.get_playback_position()
	game.changed.emit()
	await create_timer(0.3).timeout
	check(sound._music.get_playback_position() > before, "state refresh never restarts track")
	game.set_settings({"music_volume": 0}, false)
	check(not sound._music.playing, "music mute stops immediately")
	await create_timer(0.15).timeout
	capture.clear_buffer()
	await create_timer(0.2).timeout
	check(samples() < 0.000001, "mute produces silence")
	game.set_settings({"music_volume": 35}, false)
	check(sound._music.get_playback_position() >= before, "unmute resumes track")
	sound._music.seek(sound._music.stream.get_length() - 0.2)
	await create_timer(0.6).timeout
	check(sound._music.playing and sound._music.get_playback_position() < 2, "music loops at end")
	sound.set_paused(true)
	await create_timer(3).timeout
	check(not sound._music.playing, "pause fades and stops")
	sound.set_paused(false)
	sound._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(3).timeout
	check(not sound._music.playing, "focus loss fades and stops")
	sound._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(sound._music.playing, "focus restore resumes")
	game.set_settings({"volume": 0}, false)
	check(not sound._music.playing, "master mute stops immediately")
	game.set_settings({"volume": 50, "music_volume": 0, "effects_volume": 65}, false)
	capture.clear_buffer()
	sound.play_ui("work_success")
	var cue_peak: float = await wait_for_audio_peak(2.0)
	check(cue_peak > 0.0001, "result cue reaches mixer")
	var office = load("res://main.tscn").instantiate()
	root.add_child(office)
	await process_frame
	check(office.ui._new_game(), "actual office starts with isolated save")
	game.set_process(false)
	game.set_settings({"music_volume":35,"ambient_volume":0,"effects_volume":0},false)
	await create_timer(0.4).timeout
	check(sound.workspace_active and sound._music.playing, "actual office starts BGM without manual playback hook")
	office.ui.open_panel("pause")
	await create_timer(3).timeout
	check(not sound._music.playing, "actual pause screen stops music")
	office.ui.close_panel()
	await create_timer(0.4).timeout
	check(sound._music.playing, "return to office resumes music")
	office.ui.open_panel("settings")
	office.ui._settings_tab("audio")
	await create_timer(0.4).timeout
	check(sound._music.playing, "audio settings allow hearing volume changes")
	if DisplayServer.get_name()!="headless" and "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/simulator/experience/ui/audio-settings.png"))
	office.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0)-1)
	capture = null
	await process_frame
	await process_frame
	print("AUDIO_RUNTIME failures=", failures.size(), " music_peak=", peak, " driver=", AudioServer.get_driver_name())
	quit(0 if failures.is_empty() else 1)
