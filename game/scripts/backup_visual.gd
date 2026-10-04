extends RefCounted
## Read-only projections of displayed bytes and the existing customer acceptance.
## Format, byte equality, and customer acceptance are deliberately separate facts.

static func document(content: String, exists := true) -> Dictionary:
	var out := {"kind":"text","fields":[],"lines":Array(content.strip_edges().split("\n")),"bytes":content.to_utf8_buffer().size()}
	if content.is_empty():out.lines=[]
	if not exists: out.kind="missing";out.lines=[];out.bytes=0;return out
	if content.strip_edges()=="CORRUPTED DATA": out.kind="damaged";return out
	var pattern := RegEx.new()
	pattern.compile("^(\\d{4}-\\d{2}-\\d{2})\\s+opening=(-?\\d+)\\s+closing=(-?\\d+)\\s*$")
	var found := pattern.search(content.strip_edges())
	if found!=null:
		out.kind="ledger"
		out.fields=[{"key":"date","label":"日付","value":found.get_string(1)},{"key":"opening","label":"開始","value":found.get_string(2)},{"key":"closing","label":"締め","value":found.get_string(3)}]
	return out

static func comparison(saved: String, current: String, exists: bool) -> Dictionary:
	var left := document(saved);var right := document(current,exists)
	var changed: Array[String]=[]
	var values := {}
	for field in right.fields:values[str(field.key)]=str(field.value)
	for field in left.fields:
		if not values.has(str(field.key)) or str(values[str(field.key)])!=str(field.value):changed.append(str(field.key))
	for field in right.fields:
		var matches: bool=left.fields.any(func(item):return str(item.key)==str(field.key) and str(item.value)==str(field.value))
		if not matches and str(field.key) not in changed:changed.append(str(field.key))
	return {"saved":left,"current":right,"equal":exists and saved==current,"changed_keys":changed}

static func acceptance(view: Dictionary) -> Dictionary:
	var out := {"restored":"unknown","original":"unknown","unrelated":"unknown","accepted":false}
	if not bool(view.get("available",false)) or not bool(view.get("enforced",false)) or bool(view.get("legacy",false)) or not str(view.get("error","")).is_empty():return out
	var records: Array=view.get("restored",[])
	var observed: bool=records.any(func(item):return not str(item.get("current_sha256","")).is_empty())
	out.restored="matched" if bool(view.get("restore_valid",false)) else "mismatch" if observed else "missing"
	out.original="preserved" if bool(view.get("original_preserved",false)) else "changed"
	out.unrelated="preserved" if bool(view.get("unrelated_preserved",false)) else "changed"
	out.accepted=bool(view.get("accepted",false))
	return out

static func number(value: String) -> String:
	var sign := "−" if value.begins_with("-") else ""
	var digits := value.trim_prefix("-");var out := ""
	for index in digits.length():
		if index>0 and (digits.length()-index)%3==0:out+=","
		out+=digits[index]
	return sign+out
