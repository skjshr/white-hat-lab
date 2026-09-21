extends SceneTree
var preset:="medium"
func _init():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf-preset="):preset=arg.trim_prefix("--perf-preset=")
	create_timer(30).timeout.connect(func():quit(2))
	call_deferred("run")
func run():
	var game=root.get_node("Game")
	game.new_game()
	var settings:Dictionary=root.get_node("Graphics").preset_values("medium" if preset=="title" else preset)
	settings.merge({"resolution":"1280x720","window_mode":"windowed","volume":0},true)
	game.set_settings(settings,true)
	var office=load("res://scripts/office.gd").new();root.add_child(office)
	if preset!="title":
		office.ui.controls.menu.hide();office.ui.current_kind="";office.started=true
	await create_timer(3).timeout
	var ms:Array[float]=[];var cpu:Array[float]=[];var draw:Array[float]=[]
	var last:=Time.get_ticks_usec();var until:=last+5000000
	while Time.get_ticks_usec()<until:
		await process_frame
		var now:=Time.get_ticks_usec();ms.append(float(now-last)/1000);last=now
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		draw.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	ms.sort();cpu.sort();draw.sort()
	var result:Dictionary={"preset":preset,"settings":game.settings,"title_visible":office.ui.controls.menu.visible,"player_enabled":office.player.enabled,"frames":ms.size(),"median_ms":ms[ms.size()/2],"p99_ms":ms[int(ms.size()*.99)],"median_cpu_ms":cpu[cpu.size()/2],"median_draw_calls":draw[draw.size()/2],"renderer":RenderingServer.get_video_adapter_name()}
	print("PERFORMANCE_V19 ",JSON.stringify(result))
	FileAccess.open("res://../artifacts/simulator/v19/performance-"+preset+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	quit()
