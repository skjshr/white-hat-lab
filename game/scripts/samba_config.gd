class_name SambaConfig
extends RefCounted
## Documented smb.conf subset. OS identities/permissions are fixed exercise fixtures.
const BOOL_PARAMS := ["available", "read only", "guest ok"]
const GLOBAL_PARAMS := ["guest account", "map to guest", "server role"]
const SHARE_PARAMS := ["path", "available", "read only", "guest ok", "valid users", "invalid users", "write list", "read list"]
const ALIASES := {"readonly":"read only","guestok":"guest ok","public":"guest ok","validusers":"valid users","invalidusers":"invalid users","writelist":"write list","readlist":"read list","guestaccount":"guest account","maptoguest":"map to guest","serverrole":"server role","writeable":"read only","writable":"read only"}

static func _boolean(value: String) -> Variant:
	if value.to_lower() in ["yes","true","1"]: return true
	if value.to_lower() in ["no","false","0"]: return false
	return null

static func _has(value: String, user: String) -> bool:
	for item in value.replace(","," ").replace("\t"," ").split(" ",false):
		if item == user or (item == "@staff" and user == "staff") or (item == "@nogroup" and user == "nobody"): return true
	return false

static func _mode(settings: Dictionary, user: String) -> String:
	if not bool(settings.get("available",true)): return "none"
	if user == "nobody" and not bool(settings.get("guest ok",false)): return "none"
	var valid := str(settings.get("valid users",""))
	if _has(str(settings.get("invalid users","")),user) or (not valid.is_empty() and not _has(valid,user)): return "none"
	# Samba gives write list priority when a user occurs in both lists.
	if _has(str(settings.get("write list","")),user): return "write"
	if _has(str(settings.get("read list","")),user): return "read"
	return "read" if bool(settings.get("read only",true)) else "write"

static func _error(message: String, sections: Dictionary) -> Dictionary:
	return {"error":message,"sections":sections,"values":{}}

static func parse(text: String) -> Dictionary:
	var sections: Dictionary = {}; var section := ""; var continued := ""
	for raw in text.split("\n"):
		var line := continued + raw.strip_edges(); continued=""
		if line.ends_with("\\"): continued=line.left(-1); continue
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"): continue
		if line.begins_with("[") and line.ends_with("]"):
			section=line.substr(1,line.length()-2).strip_edges().to_lower()
			if section.is_empty(): return _error("empty section name",sections)
			if not sections.has(section): sections[section]={}
			continue
		if section.is_empty(): return _error("parameter outside a section: "+line,sections)
		var cut := line.find("=")
		if cut < 1: return _error("expected parameter = value: "+line,sections)
		var raw_key := line.left(cut).to_lower().replace(" ","").replace("\t","")
		var key := str(ALIASES.get(raw_key,raw_key)); var value: Variant=line.substr(cut+1).strip_edges()
		if key not in SHARE_PARAMS and key not in GLOBAL_PARAMS: return _error("unsupported exercise parameter: "+key,sections)
		if key in GLOBAL_PARAMS and section != "global": return _error(key+" belongs in [global]",sections)
		if key in BOOL_PARAMS:
			value=_boolean(str(value))
			if value == null: return _error("invalid boolean for "+key,sections)
			if raw_key in ["writable","writeable"]: value=not bool(value)
		sections[section][key]=value
	if not continued.is_empty(): return _error("unfinished continuation",sections)
	var globals: Dictionary=sections.get("global",{})
	if str(globals.get("server role","standalone server")).to_lower() not in ["standalone server","auto"]: return _error("only standalone server is modeled in this exercise",sections)
	if str(globals.get("guest account","nobody")) != "nobody": return _error("the exercise guest account is nobody",sections)
	var mapping := str(globals.get("map to guest","Never"))
	if mapping.to_lower() not in ["never","bad user"]: return _error("supported exercise guest mapping: Never, Bad User",sections)
	var shares: Dictionary={}
	for name in sections:
		if name == "global": continue
		var effective := {"available":true,"read only":true,"guest ok":false,"path":"","valid users":"","invalid users":"","write list":"","read list":""}
		for key in SHARE_PARAMS:
			if globals.has(key): effective[key]=globals[key]
		for key in sections[name]: effective[key]=sections[name][key]
		shares[name]=effective
	var main: Dictionary=shares.get("share",{})
	var available: bool=shares.has("share") and bool(main.get("available",true))
	return {"error":"","sections":sections,"values":{"staff":_mode(main,"staff") if available else "none","guest":_mode(main,"nobody") if available else "none","samba":sections,"shares":shares,"share_name":"share","available":available,"path":str(main.get("path","")),"map_to_guest":mapping}}

static func configuration_text(values: Dictionary) -> String:
	var staff := str(values.get("staff","none")); var guest := str(values.get("guest","none"))
	var lines: Array[String]=["[global]","    server role = standalone server","    map to guest = Bad User","    guest account = nobody","","[share]","    path = /srv/share","    read only = yes","    guest ok = "+("yes" if guest != "none" else "no")]
	var valid: Array[String]=[]; var writes: Array[String]=[]
	if staff != "none": valid.append("staff")
	if guest != "none": valid.append("nobody")
	if staff == "none" and guest == "none": lines.append("    available = no")
	if not valid.is_empty(): lines.append("    valid users = "+" ".join(valid))
	if staff == "write": writes.append("staff")
	if guest == "write": writes.append("nobody")
	if not writes.is_empty(): lines.append("    write list = "+" ".join(writes))
	return "\n".join(lines)+"\n"

static func update_section(text: String, section_name: String, updates: Dictionary) -> Dictionary:
	# Edit only the selected section. Keep comments and all other sections, rather
	# than flattening an administrator's smb.conf into the exercise's defaults.
	var parsed := parse(text)
	var target := section_name.to_lower()
	if not str(parsed.error).is_empty(): return {"error":str(parsed.error),"text":text}
	if not parsed.sections.has(target): return {"error":"section not found: "+target,"text":text}
	var allowed: Array = GLOBAL_PARAMS if target == "global" else SHARE_PARAMS
	for key in updates:
		if key not in allowed or "\n" in str(updates[key]) or "\r" in str(updates[key]):
			return {"error":"invalid parameter: "+str(key),"text":text}
	var out: Array[String]=[]; var current:=""; var written: Array[String]=[]; var skipping:=false
	for raw in text.trim_suffix("\n").split("\n"):
		var line:=raw.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			if current == target:
				for key in updates:
					if key not in written: out.append(_parameter_text(str(key),updates[key])); written.append(str(key))
			current=line.substr(1,line.length()-2).strip_edges().to_lower()
		if current != target: out.append(raw); continue
		if skipping: skipping=line.ends_with("\\"); continue
		var cut:=line.find("=")
		if cut>0 and not line.begins_with("#") and not line.begins_with(";"):
			var raw_key:=line.left(cut).to_lower().replace(" ","").replace("\t","")
			var key:=str(ALIASES.get(raw_key,raw_key))
			if updates.has(key):
				if key not in written: out.append(_parameter_text(key,updates[key])); written.append(key)
				skipping=line.ends_with("\\"); continue
		out.append(raw)
	if current == target:
		for key in updates:
			if key not in written: out.append(_parameter_text(str(key),updates[key]))
	var result:="\n".join(out)+"\n"
	var checked:=parse(result)
	return {"error":str(checked.error),"text":result if str(checked.error).is_empty() else text}

static func _parameter_text(key: String, value: Variant) -> String:
	return "    "+key+" = "+(("yes" if value else "no") if value is bool else str(value))
