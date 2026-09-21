class_name ProfessionalContracts
extends RefCounted

const UI = preload("res://scripts/ui_theme.gd")

static func append_to(catalog: Array) -> void:
	var specs := [
		["firm-permission-review", "advisory", 2, 3, [{"id":"service-0-case-5"},{"id":"service-5-case-2"}]],
		["firm-remote-hardening", "advisory", 4, 6, [{"id":"service-2-case-2"},{"id":"service-3-case-2"},{"id":"service-5-case-5"}]],
		["firm-continuity", "operations", 2, 3, [{"id":"service-1-case-4"},{"id":"service-3-case-3"}]],
		["firm-recovery-drill", "operations", 4, 6, [{"id":"service-1-case-5"},{"id":"service-2-case-3"}]],
		["firm-account-containment", "response", 2, 3, [{"id":"service-3-case-4"},{"id":"service-5-case-4"}]],
		["firm-major-containment", "response", 4, 6, [{"id":"service-4-case-3"},{"id":"service-2-case-2"},{"id":"service-0-case-4"}]],
		["firm-partner-rollout", "advisory", 2, 4, [{"id":"service-3-case-2"},{"id":"service-5-case-3"},{"id":"service-2-case-0"}]],
		["firm-clean-recovery", "operations", 2, 4, [{"id":"endpoint-recovery"},{"id":"service-1-case-3"}]],
		["firm-leak-response", "response", 2, 4, [{"id":"service-4-case-1"},{"id":"service-0-case-4"},{"id":"service-5-case-4"}]]
	]
	for spec in specs:
		var id := str(spec[0]); var category := str(spec[1]); var rank := int(spec[2]); var level := int(spec[3]); var required_skills := {category: int(spec[2])}
		if id == "firm-partner-rollout": required_skills = {"advisory":2,"operations":1}
		elif id == "firm-clean-recovery": required_skills = {"operations":2,"response":1}
		elif id == "firm-leak-response": required_skills = {"response":2,"advisory":1}
		var targets: Array = []
		for target_spec in spec[4]:
			var source := _source(catalog, str(target_spec.id))
			if source.is_empty(): continue
			targets.append({"chapter":int(source.get("chapter", 0)), "case_id":str(source.get("id", target_spec.id)), "name":str(source.get("service", ""))})
		if targets.is_empty(): continue
		var primary: Dictionary = targets[0]
		var client_source := _source(catalog, str(primary.case_id))
		var slug := id.trim_prefix("firm-").replace("-", "_")
		catalog.append({"id":id,"title":UI.copy("firm_%s_title" % slug),"client":str(client_source.get("client", "")),"chapter":int(primary.chapter),"category":category,"tier":2 if targets.size() <= 2 else 3,"required_level":level,"required_rank":rank,"required_skills":required_skills,"work_family":id,"brief":UI.copy("firm_%s_brief" % slug),"service":UI.copy("firm_family_" + category),"evidence":[UI.copy("firm_checks")],"hints":[],"debrief":UI.copy("firm_debrief"),"checks":[UI.copy("firm_checks")],"targets":targets,"target_count":targets.size(),"desired":{},"initial":{},"required_files":[],"probes":[],"reward":8000 + (targets.size() * 2000) + rank * 500})

static func _source(catalog: Array, id: String) -> Dictionary:
	for item in catalog:
		if item is Dictionary and str(item.get("id", "")) == id: return item
	return {}
