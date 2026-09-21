extends Node
## Focused headless smoke for the first-person coffee path.  It checks the
## camera-safe path and attached grip without claiming human visual/audio QA.

var failures: Array[String] = []

func _assert(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _ready() -> void:
	var player := preload("res://scripts/player.gd").new()
	add_child(player)
	await get_tree().process_frame
	player.set_coffee_visible(true)
	var carry := player.coffee_cup.position
	var grip := player.coffee_grip.position
	var tween: Tween = player.animate_coffee_drink()
	_assert(tween != null, "drink tween created")
	await get_tree().create_timer(1.05).timeout
	_assert(player.coffee_cup.position.distance_to(carry) < 0.001, "cup remains attached to grip while raised")
	_assert(player.coffee_grip.position.distance_to(grip) < 0.001, "grip local offset is stable")
	_assert(player.coffee_grip.rotation.x > 0.30, "sip uses a forward lip tilt")
	_assert(player.coffee_cup.global_position.z > -0.48, "sip lip stays camera-safe")
	await tween.finished
	_assert(player.coffee_rig.position.length() < 0.01, "hand returns to carry position")
	_assert(player.coffee_cup.position.distance_to(carry) < 0.001, "cup returns with the hand")
	# Exercise the office-owned sip accounting as three separate actions.  This
	# is deliberately a narrow behavior check; visual/audio acceptance remains
	# a GPU and human review concern.
	var office := preload("res://scripts/office.gd").new()
	add_child(office)
	await get_tree().process_frame
	if is_instance_valid(office.ui):
		office.ui.current_kind = ""
		if office.ui.controls.has("menu"): office.ui.controls.menu.hide()
	office.started = true
	office.player.enabled = true
	office.coffee_phase = "carried"
	office.coffee_volume = 1.0
	office.player.set_coffee_visible(true)
	await get_tree().process_frame
	_snapshot(office, "coffee-held")
	for sip_index in 3:
		office._drink_coffee()
		if sip_index == 0:
			await get_tree().create_timer(0.45).timeout
			var paused_elapsed := office.coffee_drink_elapsed
			var paused_position: Vector3 = office.player.coffee_rig.position
			office.ui.current_kind = "settings"
			await get_tree().create_timer(0.60).timeout
			_assert(absf(office.coffee_drink_elapsed - paused_elapsed) < 0.02, "coffee timer pauses in settings elapsed=%f before=%f" % [office.coffee_drink_elapsed, paused_elapsed])
			_assert(office.player.coffee_rig.position.distance_to(paused_position) < 0.04, "coffee hand pauses in settings pos=%s before=%s" % [office.player.coffee_rig.position, paused_position])
			office.ui.current_kind = ""
			await get_tree().create_timer(0.65).timeout
			_snapshot(office, "coffee-sip")
			await get_tree().create_timer(1.30).timeout
		else:
			await get_tree().create_timer(2.6).timeout
		if sip_index < 2:
			_assert(absf(office.coffee_volume - (2.0 - float(sip_index)) / 3.0) < 0.04, "sip %d leaves one third less liquid" % (sip_index + 1))
		else:
			_assert(office.coffee_volume < 0.04 and office.coffee_phase == "carried_empty", "third sip empties cup")
		if sip_index == 0: _snapshot(office, "coffee-lowered")
	_export_audio_preview()
	print("COFFEE_PREVIEW failures=", failures.size(), " grip_attached=true camera_safe=true")
	for failure in failures: print("FAIL: ", failure)
	get_tree().quit(1 if not failures.is_empty() else 0)

func _export_audio_preview() -> void:
	var pcm := PackedByteArray()
	for key in ["__coffee_pour", "__coffee_sip", "__coffee_setdown", "__ambient_keyboard", "__ambient_exterior"]:
		var stream: AudioStreamWAV = get_node("/root/Soundscape")._get_stream(key)
		if stream == null: continue
		pcm.append_array(stream.data)
		var gap := PackedByteArray()
		gap.resize(22050)
		pcm.append_array(gap)
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952) # RIFF
	header.encode_u32(4, 36 + pcm.size())
	header.encode_u32(8, 0x45564157) # WAVE
	header.encode_u32(12, 0x20746d66) # fmt 
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)
	header.encode_u16(22, 1)
	header.encode_u32(24, 22050)
	header.encode_u32(28, 44100)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164) # data
	header.encode_u32(40, pcm.size())
	var path := "res://../artifacts/simulator/v18/sound-preview.wav"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/simulator/v18"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert(file != null, "audio preview file opened")
	if file != null:
		file.store_buffer(header)
		file.store_buffer(pcm)
		file.close()
	var peak := 0
	var nonzero := 0
	for i in range(0, pcm.size(), 2):
		var sample := absi(pcm.decode_s16(i))
		peak = maxi(peak, sample)
		if sample > 0: nonzero += 1
	_assert(nonzero > 0, "generated audio preview contains samples")
	_assert(peak > 0 and peak < 32767, "generated audio preview is bounded")
	print("COFFEE_AUDIO_PREVIEW path=", path, " peak=", peak, " nonzero=", nonzero)

func _snapshot(office: Node, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	print("COFFEE_SNAPSHOT ", label, " visible=", office.player.coffee_rig.visible, " pos=", office.player.coffee_rig.position, " grip=", office.player.coffee_grip.rotation, " kind=", office.ui.current_kind)
	var texture := get_viewport().get_texture()
	if texture == null: return
	var image := texture.get_image()
	if image == null or image.is_empty(): return
	var folder := "res://../artifacts/simulator/v18"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	image.save_png(folder + "/" + label + ".png")
