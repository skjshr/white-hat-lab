class_name AdvancedOperationsWorkspace
extends RefCounted

const PENTEST_PORTAL = preload("res://scripts/os_pentest_portal.gd")
const HUNT = preload("res://scripts/os_hunt_workspace.gd")
const NETWORK = preload("res://scripts/os_network_pentest_workspace.gd")
const RECOVERY = preload("res://scripts/os_recovery_workspace.gd")
const SPECIALIST = preload("res://scripts/os_specialist_workspaces.gd")
const SAAS = preload("res://scripts/os_saas_response.gd")
const AI_PREFLIGHT = preload("res://scripts/os_ai_preflight.gd")

static func _kind(d) -> String:
	return str(d.game.state.get("advanced",{}).get("kind",d.game.state.get("contract",{}).get("case_id","")))

static func build(d,parent: VBoxContainer) -> void:
	var model: Dictionary = d.game.state.get("advanced", {})
	if model.is_empty():
		d.widgets.advanced = {"unassigned":true}
		var state: Label = d._label("高度案件の作業対象なし",16); state.name="AdvancedUnassigned"; parent.add_child(state)
		var open: Button = d._button("案件を開く",d._contracts); open.name="AdvancedOpenContracts"; parent.add_child(open)
		return
	if str(model.get("model_version", "")) == "saas-ai-preflight-v1":
		AI_PREFLIGHT.build(d, parent); return
	match _kind(d):
		"advanced-portal": PENTEST_PORTAL.build(d,parent)
		"advanced-hunt": HUNT.build(d,parent)
		"advanced-pentest": NETWORK.build(d,parent)
		"advanced-recovery": RECOVERY.build(d,parent)
		"advanced-saas-response": SAAS.build(d,parent)
		_: SPECIALIST.build(d,parent)

static func refresh(d) -> void:
	if not d.widgets.has("advanced"): return
	if bool(d.widgets.advanced.get("unassigned",false)):
		var model: Dictionary = d.game.state.get("advanced", {})
		if not model.is_empty():
			var parent: VBoxContainer = d.windows.advanced.content
			d._clear(parent); build(d,parent); d._wire_focus(parent,"advanced")
		return
	if d.widgets.advanced.get("pentest",false): PENTEST_PORTAL.refresh(d); return
	match str(d.widgets.advanced.get("family","")):
		"advanced-saas-ai-preflight": AI_PREFLIGHT.refresh(d)
		"advanced-hunt": HUNT.refresh(d)
		"advanced-pentest": NETWORK.refresh(d)
		"advanced-recovery": RECOVERY.refresh(d)
		"advanced-saas-response": SAAS.refresh(d)
		_: SPECIALIST.refresh(d)
