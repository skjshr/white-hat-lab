extends "res://tests/test_specialist_workspaces.gd"

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name()=="headless": return
	await frames(6); await RenderingServer.frame_post_draw
	var phase: String=OS.get_environment("RC_SPECIALIST_PHASE")
	if phase.is_empty(): phase="after"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--phase="): phase=str(arg).trim_prefix("--phase=")
	var folder: String=ProjectSettings.globalize_path("res://../../audit/release-candidate/specialists/"+phase)
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)
