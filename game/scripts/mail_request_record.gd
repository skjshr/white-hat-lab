extends RefCounted
## Shared authored request data; delivery stores the text before it can change.
static var cache: Dictionary={}
static func entry(id: String) -> Dictionary:
	if cache.is_empty():
		var file:=FileAccess.open("res://content/mail.json",FileAccess.READ)
		if file!=null:
			var parsed: Variant=JSON.parse_string(file.get_as_text())
			if parsed is Dictionary and parsed.get("entries",{}) is Dictionary: cache=parsed.entries
	var value: Variant=cache.get(id,{})
	return value if value is Dictionary else {}
static func capture(mission: Dictionary, case_id: String, modern_endpoint: bool) -> Dictionary:
	var result: Dictionary={}
	for id in [case_id,str(mission.get("case_id","")),str(mission.get("id","")),str(mission.get("copy_id",""))]:
		result=entry(id).duplicate(true)
		if not result.is_empty(): break
	if result.is_empty(): result={"subject":str(mission.get("title","依頼")),"body":str(mission.get("brief","")),"sender":"担当者","company":str(mission.get("client",""))}
	var original_company:=str(result.get("company","")); var actual_company:=str(mission.get("client",original_company))
	if not original_company.is_empty() and original_company!=actual_company: result.body=str(result.get("body","" )).replace(original_company,actual_company)
	result.company=actual_company
	if modern_endpoint: result.subject=str(mission.get("title","")); result.body=str(mission.get("brief",""))
	return result
