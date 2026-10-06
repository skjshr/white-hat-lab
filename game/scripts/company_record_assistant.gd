extends RefCounted
## Company-owned, offline record organizer. Status never creates saved fields.

const VERSION := 1
const REQUIRED_LEVEL := 3
const REQUIRED_RESPONSE := 1
const PURCHASE_COST := 3000
const RUN_COST := 300
const MANUAL_MINUTES := 5
const ASSISTANT_MINUTES := 2

static func _whole(value: Variant, minimum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= 2147483647.0

static func _valid_saved(saved: Variant) -> bool:
	if not saved is Dictionary: return false
	if saved.is_empty(): return true
	return _whole(saved.get("version"), VERSION) and int(saved.version) == VERSION and _whole(saved.get("purchased_day"), 1) and _whole(saved.get("purchase_cost"), PURCHASE_COST) and int(saved.purchase_cost) == PURCHASE_COST

static func status(game) -> Dictionary:
	var state: Dictionary = game.state
	var level := int(game.company_level().get("level", 1))
	var response := int(state.get("skills", {}).get("response", 0))
	var tools: Variant = state.get("company_tools", {})
	var saved: Variant = tools.get("record_assistant", {}) if tools is Dictionary else null
	var valid := _valid_saved(saved)
	var owned: bool = valid and not saved.is_empty()
	var unlocked := level >= REQUIRED_LEVEL and response >= REQUIRED_RESPONSE
	var affordable := int(state.get("cash", 0)) >= PURCHASE_COST
	var reason := ""
	if not valid: reason = "保存された導入情報を確認できません。"
	elif owned: reason = "導入済み"
	elif not unlocked:
		var missing: Array[String] = []
		if level < REQUIRED_LEVEL: missing.append("会社Lv.%d / %d" % [level, REQUIRED_LEVEL])
		if response < REQUIRED_RESPONSE: missing.append("調査・復旧 %d / %d" % [response, REQUIRED_RESPONSE])
		reason = " · ".join(missing)
	elif not affordable: reason = "導入資金 あと¥%d" % (PURCHASE_COST - int(state.get("cash", 0)))
	return {"unlocked":unlocked,"owned":owned,"can_purchase":valid and unlocked and affordable and not owned,"reason":reason,"purchase_cost":PURCHASE_COST,"run_cost":RUN_COST,"manual_minutes":MANUAL_MINUTES,"assistant_minutes":ASSISTANT_MINUTES,"required_level":REQUIRED_LEVEL,"required_response":REQUIRED_RESPONSE,"company_level":level,"response_rank":response}

static func purchase(game) -> bool:
	var availability := status(game)
	if bool(availability.owned): return true
	if not bool(availability.can_purchase): return false
	var previous: Dictionary = game.state.duplicate(true)
	if not game.state.has("company_tools"): game.state.company_tools = {}
	game.state.company_tools.record_assistant = {"version":VERSION,"purchased_day":int(game.state.day),"purchase_cost":PURCHASE_COST}
	game.state.cash = int(game.state.cash) - PURCHASE_COST
	game.state.history.append({"kind":"investment","tool_id":"record_assistant","title":"模擬AI 記録整理助手","day":int(game.state.day),"amount":PURCHASE_COST})
	if not game.save_game():
		game.state = previous
		game.notified.emit("助手の導入を保存できませんでした。残高は元に戻しました。")
		return false
	game.changed.emit()
	return true
