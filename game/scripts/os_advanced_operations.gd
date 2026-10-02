class_name AdvancedOperationsWorkspace
extends RefCounted

const PENTEST_PORTAL = preload("res://scripts/os_pentest_portal.gd")
const HUNT = preload("res://scripts/os_hunt_workspace.gd")
const NETWORK = preload("res://scripts/os_network_pentest_workspace.gd")
const RECOVERY = preload("res://scripts/os_recovery_workspace.gd")
const SPECIALIST = preload("res://scripts/os_specialist_workspaces.gd")

static func _kind(d) -> String:
	return str(d.game.state.get("advanced",{}).get("kind",d.game.state.get("contract",{}).get("case_id","")))

static func build(d,parent: VBoxContainer) -> void:
	match _kind(d):
		"advanced-portal": PENTEST_PORTAL.build(d,parent)
		"advanced-hunt": HUNT.build(d,parent)
		"advanced-pentest": NETWORK.build(d,parent)
		"advanced-recovery": RECOVERY.build(d,parent)
		_: SPECIALIST.build(d,parent)

static func refresh(d) -> void:
	if not d.widgets.has("advanced"): return
	if d.widgets.advanced.get("pentest",false): PENTEST_PORTAL.refresh(d); return
	match str(d.widgets.advanced.get("family","")):
		"advanced-hunt": HUNT.refresh(d)
		"advanced-pentest": NETWORK.refresh(d)
		"advanced-recovery": RECOVERY.refresh(d)
		_: SPECIALIST.refresh(d)
