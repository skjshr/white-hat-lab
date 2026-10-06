extends Node

signal changed
signal notified(message: String)

const SAVE_NAME := "user://security_lab_save.json"
const SAVE_BACKUP_NAME := "user://security_lab_save.json.bak"
const SAVE_PREVIOUS_NAME := "user://security_lab_save.json.previous.json"
const COPY_PATH := "res://content/copy.json"
const SETTINGS_PATH := "user://security_lab_settings.json"
const STATE_VERSION := 1
const OPERATIONS = preload("res://scripts/operations_dispatch.gd")
const DAY_LEDGER = preload("res://scripts/day_ledger.gd")
const BILLING = preload("res://scripts/company_billing.gd")
const COMPANY_CYCLE = preload("res://scripts/company_cycle.gd")
const BRANCH_HANDOFF = preload("res://scripts/branch_handoff.gd")
const CAREER_CLOSEOUT = preload("res://scripts/career_closeout.gd")
const ENDPOINT_ENGAGEMENT = preload("res://scripts/endpoint_engagement.gd")
const COMPANY_ROADMAP = preload("res://scripts/company_roadmap.gd")
const SERVICE_MONITOR_VM = preload("res://scripts/virtual_machine.gd")
const BUSINESS_TRANSACTIONS = preload("res://scripts/business_transactions.gd")
const BUSINESS_DATA = preload("res://scripts/business_workspace.gd")
const HOTEL_FRONTDESK = preload("res://scripts/hotel_frontdesk_model.gd")
const HOTEL_RECOVERY = preload("res://scripts/hotel_recovery.gd")
const HOTEL_HANDOFF = preload("res://scripts/hotel_handoff.gd")
const SAAS_WATCH = preload("res://scripts/company_saas_watch.gd")
const SAAS_PARTNER = preload("res://scripts/saas_partner_followup.gd")
const SAAS_AI = preload("res://scripts/saas_ai_followup.gd")
const SAAS_AI_HANDOFF = preload("res://scripts/saas_ai_handoff_followup.gd")
const BUSINESS_START_MINUTE := 9 * 60
const BUSINESS_END_MINUTE := 18 * 60
const DELIVERY_WAIT_SECONDS := 30.0
const EQUIPMENT_SLOTS := {"plant":0,"backup":1,"monitor":2,"workstation":3,"diagnostic":4,"teamdesk":5,"annexdesk_a":6,"annexdesk_b":7}
const REWARDS := [1500, 2500, 4000, 5000, 7000, 10000]
const DIFFICULTIES := ["入門", "初級", "中級", "中級", "上級", "最終案件"]
const REQUIRED_CREDIT := [0, 8, 25, 50, 100, 160]
const CATEGORIES := ["advisory", "operations", "advisory", "operations", "response", "advisory"]
## The first eight thresholds are part of the original save contract. The
## remaining thresholds make all ten ranks obtainable during long career play
## without changing the meaning of existing credit values.
const SKILL_THRESHOLDS := [20, 50, 100, 200, 400, 800, 1600, 3200, 3400, 3600, 3800, 4000, 4200, 4400, 4600, 4800, 5000, 5250, 5500, 5750, 6000, 6250, 6500, 6750, 7000, 7250, 7500, 7750, 8000, 8200]
const LEVEL_XP := [0,1000,3000,6500,11000,18000,27000,39000,54000,73000,97000,127000,165000,212000,270000,340000,425000,530000,660000,820000]
const CASES = preload("res://scripts/case_catalog.gd")
const UI_COPY = preload("res://scripts/ui_theme.gd")
const CARE = preload("res://scripts/care_lifecycle.gd")
const CARE_SUPPORT = preload("res://scripts/care_contract_support.gd")
const MAINTENANCE_SCOPE = preload("res://scripts/maintenance_scope.gd")
const MAINTENANCE_DISPATCH = preload("res://scripts/maintenance_dispatch.gd")
const PLACEMENT_RULES = preload("res://scripts/placement_rules.gd")
const MARKET_DEMAND = preload("res://scripts/market_demand.gd")
const CUSTOMER_STOCK = preload("res://scripts/customer_stock.gd")
const DISPATCH_FORECAST = preload("res://scripts/dispatch_forecast.gd")
const PRICING_CATEGORIES := ["advisory", "operations", "response"]
const PRICING_MIN_PERCENT := 50
const PRICING_MAX_PERCENT := 150
const PRICING_STEP_PERCENT := 5

var save_path: String = SAVE_NAME
var backup_path: String = SAVE_BACKUP_NAME
var previous_path: String = SAVE_PREVIOUS_NAME
var settings_path: String = SETTINGS_PATH
var last_load_error := ""
var state: Dictionary = {}
var copy: Dictionary = {}
var settings: Dictionary = {
	"quality": "auto", "render_scale": 0.67, "msaa": 0, "shadows": "off", "max_fps": 60,
	"vsync": true, "window_mode": "windowed", "resolution": "1280x720", "fov": 70.0,
	"text_scale": 1.0, "volume": 50, "effects_volume": 65, "ambient_volume": 12, "music_volume": 35, "mouse_sensitivity": 1.0, "invert_y": false,
}
var _assignments: Dictionary = {}
var _crew_runtime_available: Dictionary = {"aya":true,"ren":true}
var _crew_runtime_registered: Dictionary = {}
var _machine: RefCounted
var _machine_key := ""
var _crew_update := 0.0
var _maintenance_dispatch_elapsed := 0.0
var _office_clock_paused := false
var _delivery_clock_enabled := false
var _delivery_clock_paused := false
var _dispatch_start_remaining := -1.0
var _dispatch_start_member := ""
var _dispatch_transaction := false

const STAFF_CANDIDATES := {"mio":{"role":"aya","hire_fee":2400,"daily_wage":600},"haru":{"role":"ren","hire_fee":3200,"daily_wage":800},"sora":{"role":"maintenance","hire_fee":2000,"daily_wage":500}}
const STAFF_SHIFTS := {"day":{"start":540,"end":1080,"fraction":1.0},"morning":{"start":540,"end":780,"fraction":0.5},"afternoon":{"start":780,"end":1080,"fraction":0.5}}

const RULES: Array = [
	{"id":"share", "fields":[["staff",1,2],["guest",2,0]], "checks":["スタッフが書き込める","ゲストの読み取りを拒否"]},
	{"id":"backup", "fields":[["schedule",0,1],["location",0,1],["restore",0,1]], "checks":["毎日のバックアップ","別場所への保存","復元テストによるデータ回収"]},
	{"id":"network", "fields":[["dns",0,1],["business",1,1],["admin_public",1,0],["tls",0,1]], "checks":["名前解決が使える","通常業務可能","外部からの管理接続を拒否","通信暗号化"]},
	{"id":"account", "fields":[["former",0,1],["sessions",0,1],["current",1,1],["mfa",0,1]], "checks":["退職者のログインを拒否","既存セッションを失効","在籍者の業務を許可","追加認証要求"]},
	{"id":"incident", "fields":[["endpoint",0,1],["healthy",0,0],["logs",0,0],["reset",0,0]], "checks":["対象端末を隔離","正常端末で業務を継続","証拠保全・再インストール待機"]},
	{"id":"transfer", "fields":[["staff",1,2],["partner",2,1],["public",1,0],["expires",0,1],["partner_mfa",0,1],["transfer_tls",0,1],["audit",0,1]], "checks":["スタッフが書き込める","取引先は閲覧可能","取引先は書き込めない","公開アクセスを拒否","有効期限を7日に設定","取引先の追加認証を必須化","通信をHTTPS化","監査ログ有効化"]},
]

func _init() -> void:
	# Scripted QA is isolated even if the caller omits/misplaces --qa-profile.
	# This must run before SceneTree test scripts can call new_game().
	var profile_id := ""
	for argument in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--qa-profile="):
			var requested := argument.trim_prefix("--qa-profile=")
			if not requested.is_empty() and requested.replace("-","").is_valid_identifier(): profile_id=requested
	# Godot consumes engine flags before exposing command-line arguments. Detect
	# the actual display/main loop as well, including native SceneTree tests.
	var main_loop := Engine.get_main_loop()
	var test_run := DisplayServer.get_name() == "headless" or (main_loop != null and main_loop.get_script() != null)
	for argument in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument in ["--headless", "--script", "-s", "--smoke", "--performance"] or argument.begins_with("--script="):
			test_run = true
	if profile_id.is_empty() and test_run: profile_id="automatic-"+str(OS.get_process_id())
	if not profile_id.is_empty():
		save_path="user://qa-"+profile_id+".json"; backup_path=save_path+".bak"; previous_path=save_path+".previous"; settings_path="user://qa-"+profile_id+"-settings.json"
		print("QA_STORAGE ",save_path)

func _ready() -> void:
	_load_copy()
	_load_settings()
	if state.is_empty():
		_reset_state()

func _process(delta: float) -> void:
	# The isolated exercise advances only through explicit response actions.
	# Keep delivery, maintenance and crew clocks outside that simulated time.
	if incident_active():
		return
	if _delivery_clock_enabled and not _delivery_clock_paused:
		advance_delivery(delta)
	if _office_clock_paused:
		return
	_maintenance_dispatch_elapsed += delta
	if _maintenance_dispatch_elapsed >= 0.25:
		_maintenance_dispatch_elapsed=0.0
		MAINTENANCE_DISPATCH.dispatch(self)
	_dispatch_auto_start()
	_crew_update += delta
	var running := false
	var completed: Array[String]=[]
	for id in _assignments.keys().duplicate():
		var job: Dictionary = _assignments[id]
		if job.get("status", "") != "working": continue
		running = true
		if str(job.get("kind", "normal")) == "maintenance":
			if not bool(_crew_runtime_available.get(str(id),true)):
				job.phase = UI_COPY.copy("care_maintenance_unavailable")
				continue
			_begin_crew_time(job)
			var next_remaining := maxf(0.0,float(job.get("remaining",12.0)) - delta)
			if next_remaining <= 0.0:
				# Keep the pre-segment remaining value until the finisher's
				# transaction succeeds.  A failed save must be able to restore the
				# exact working assignment and retry it.
				completed.append(str(id))
			else:
				job.remaining = next_remaining
				job.phase = UI_COPY.copy("care_maintenance_working")
				var stored_job := _maintenance_job_for(str(job.get("client", "")))
				if not stored_job.is_empty(): stored_job.remaining = next_remaining
			continue
		if not bool(_crew_runtime_available.get(str(id),true)):
			job.phase = UI_COPY.copy("npc_returning")
			continue
		if not _colleague_hardware_connected(job):
			job.phase = UI_COPY.copy("stock_error_hardware")
			continue
		# Preserve the observed evidence before the recovery specialist changes data.
		if colleague_role(str(id)) == "ren":
			var waiting := false
			for other_id in _assignments.keys():
				var other: Dictionary = _assignments[other_id]
				if other_id != id and str(other.get("status","")) == "working" and colleague_role(str(other_id)) == "aya" and str(other.get("contract_id","")) == str(job.get("contract_id","")) and str(other.get("vm_key","")) == str(job.get("vm_key","")) and int(other.get("target_index",-1)) == int(job.get("target_index",-2)): waiting = true; break
			if not waiting:
				for observer in _dispatch_queue_map():
					if colleague_role(str(observer)) != "aya": continue
					for observation in state.dispatch_queues[observer]:
						if str(observation.get("kind","normal"))=="normal" and str(observation.get("contract_id",""))==str(job.get("contract_id","")) and int(observation.get("target_index",-1))==int(job.get("target_index",-2)): waiting=true; break
			if waiting: job.phase = UI_COPY.copy("dispatch_waiting"); continue
		if not job.has("contract_id") and (str(job.get("vm_key",_vm_key())) != _vm_key() or current_done()):
			job.status = "cancelled"; job.phase = "対象案件が変わったため中止"
			continue
		_begin_crew_time(job)
		var next_remaining := maxf(0.0,float(job.get("remaining",0.0)) - delta)
		var ratio := 1.0 - float(next_remaining) / maxf(1.0,float(job.get("total",8.0)))
		job.phase = (["接続してログを調査中","診断結果を整理中","調査記録を保存中"] if colleague_role(str(id)) == "aya" else ["復旧対象を確認中","復元・証拠保全を実行中","証拠保全の結果を保存中"])[mini(2,int(ratio*3))]
		if next_remaining <= 0.0: completed.append(str(id))
		else: job.remaining = next_remaining
	# Finish after all workers have progressed, so a colleague finishing earlier
	# in the iteration cannot move another simultaneous job's start time.
	for id in completed:
		var job: Dictionary=_assignments.get(id,{})
		if str(job.get("status",""))!="working":continue
		if str(job.get("kind","normal"))=="maintenance":_finish_maintenance(id,job)
		else:_finish_colleague(id,job)
	_dispatch_auto_start()
	if running and _crew_update >= 0.25:
		_crew_update = 0.0
		state.assignments = _assignments.duplicate(true)
		changed.emit()

func set_colleague_runtime_availability(id: String, available: bool) -> void:
	if id in ["aya","ren"] or state.get("staff",{}).has(id):
		_crew_runtime_available[id] = available
		_crew_runtime_registered[id] = true

func colleague_runtime_availability(id: String) -> Dictionary:
	return {"available":bool(_crew_runtime_available.get(id,true)),"registered":_crew_runtime_registered.has(id)}

func _crew_minutes(job: Dictionary) -> float:
	return float(job.get("minutes",12.0)) if str(job.get("kind","normal")) == "maintenance" else float(job.get("work_minutes",job.get("total",0.0)))

func _begin_crew_time(job: Dictionary) -> void:
	if job.has("work_started_at"): return
	var total := maxf(0.001,float(job.get("total",0.0)))
	var remaining := float(job.get("remaining",total))
	# Old saves may already contain elapsed work but no execution anchor.
	var prior := float(job.get("work_minutes_accounted",0.0))
	var elapsed := maxf(0.0,_crew_minutes(job)*(1.0-remaining/total)-prior)
	job.work_started_at = float(clock_minutes())-elapsed
	job.work_started_day = int(state.day)
	job.segment_minutes = _crew_minutes(job)-prior

func _advance_crew_clock(job: Dictionary, finished: bool = true) -> void:
	if not job.has("work_started_at"): return
	var total := maxf(0.001,float(job.get("total",0.0)))
	var outstanding := 0.0 if finished else _crew_minutes(job)*float(job.get("remaining",total))/total
	var elapsed := maxf(0.0,float(job.get("segment_minutes",_crew_minutes(job)))-outstanding)
	var day_offset := (int(job.get("work_started_day",state.day))-int(state.day))*1440
	state.clock_minutes = maxi(clock_minutes(),day_offset+ceili(float(job.work_started_at)+elapsed-0.00001))

func _account_crew_minutes(member_id: String, job: Dictionary, finished: bool) -> void:
	var total := maxf(0.001,float(job.get("total",0.0)))
	var done := _crew_minutes(job) if finished else _crew_minutes(job)*(1.0-clampf(float(job.get("remaining",total))/total,0.0,1.0))
	var added := maxf(0.0,done-float(job.get("work_minutes_accounted",0.0)))
	if str(job.get("kind","normal")) == "normal" and added > 0.0:
		var contract_id := str(job.get("contract_id",state.get("current_contract_id","")))
		if contract_id == str(state.get("current_contract_id","")):
			_work_add(added,0,false)
		elif state.get("contract_contexts",{}).has(contract_id):
			var context: Dictionary = state.contract_contexts[contract_id]
			ENDPOINT_ENGAGEMENT.advance_context(context, state.get("vm_states", {}), contract_id, added)
			context.work.minutes = float(context.work.get("minutes",0.0))+added
	if state.get("staff",{}).has(member_id):
		var staff_item: Dictionary = state.staff[member_id]
		if int(staff_item.get("minutes_day",-1)) != int(state.day): staff_item.minutes_used=0.0; staff_item.minutes_day=int(state.day)
		staff_item.minutes_used = float(staff_item.get("minutes_used",0.0))+added
	job.work_minutes_accounted=done; job.work_minutes_done=done
	_advance_crew_clock(job,finished)

func _finish_colleague(id: String, job: Dictionary) -> void:
	if not _colleague_hardware_connected(job): return
	if _machine != null and not _machine_key.is_empty(): state.vm_states[_machine_key] = _machine.export_state()
	_sync_target()
	var snapshot := state.duplicate(true); var assignments_snapshot := _assignments.duplicate(true)
	var return_context := str(state.get("current_contract_id", "")); var return_target_index := int(state.get("target_index", 0)); var job_context := str(job.get("contract_id", ""))
	if not job_context.is_empty() and job_context != return_context and state.get("career_mode",false) and not _activate_contract_context(job_context): return
	var job_target_index := int(job.get("target_index", state.get("target_index", 0)))
	if job_target_index >= 0 and job_target_index < state.get("targets", []).size():
		state.target_index = job_target_index
		var job_target: Dictionary = state.targets[job_target_index]
		state.chapter = int(job_target.get("chapter", state.chapter)); state.config = job_target.get("config", state.config).duplicate(true); state.inspected = bool(job_target.get("inspected", state.inspected)); state.checks = job_target.get("checks", state.checks).duplicate(true); state.revision = int(job_target.get("revision", state.revision)); state.validated_revision = int(job_target.get("validated_revision", state.validated_revision))
		for field in ["baseline_recorded","baseline_locked","baseline_config","baseline_sha","baseline_report","baseline_report_content"]:
			state[field] = job_target.get(field, false if field in ["baseline_recorded","baseline_locked"] else "")
	var machine = _vm(); var before: Array = machine.evaluate().duplicate(); var mutation := int(machine.state.mutation); var role := colleague_role(id); var log: Array = machine.cooperate(role, {"name":member_name(id),"report_path":colleague_result_path(id),"observed_day":int(state.day),"observed_time":business_clock()})
	# Persist the job's VM/context in memory first; _store_vm() would save and emit
	# while the background context is active, leaking it into the player's screen.
	state.vm_states[_vm_key()] = machine.export_state()
	var now: Array = machine.evaluate()
	if now != before or int(machine.state.get("mutation",0)) != mutation:
		state.revision += 1; state.validated_revision = -1; state.checks = []
	if bool(machine.state.get("connected",false)): state.inspected = true
	_account_crew_minutes(id,job,true)
	_work_add(0.0,100 if id in ["aya","ren"] else 0,false)
	job.status = "done"; job.remaining = 0.0; job.result = "\n".join(log)
	job.phase = UI_COPY.copy("backup_selection_required") if role == "ren" and bool(machine.state.get("cooperation_requires_selection", false)) else ("調査ログを保存しました" if role == "aya" else "復旧・証拠保全完了")
	job.revision = int(state.revision); _assignments[id] = job; state.assignments = _assignments.duplicate(true)
	_sync_contract_context()
	if not return_context.is_empty() and return_context != job_context and state.get("career_mode",false):
		if not _activate_contract_context(return_context): state = snapshot; _assignments = assignments_snapshot; _machine = null; _machine_key = ""; return
	elif return_context == job_context and return_target_index >= 0 and return_target_index < state.get("targets", []).size() and return_target_index != int(state.get("target_index", 0)):
		state.target_index = return_target_index
		var return_target: Dictionary = state.targets[return_target_index]
		state.chapter = int(return_target.get("chapter", state.chapter)); state.config = return_target.get("config", state.config).duplicate(true); state.inspected = bool(return_target.get("inspected", state.inspected)); state.checks = return_target.get("checks", state.checks).duplicate(true); state.revision = int(return_target.get("revision", state.revision)); state.validated_revision = int(return_target.get("validated_revision", state.validated_revision)); _machine = null; _machine_key = ""
		for field in ["baseline_recorded","baseline_locked","baseline_config","baseline_sha","baseline_report","baseline_report_content"]:
			state[field] = return_target.get(field, false if field in ["baseline_recorded","baseline_locked"] else "")
	state.assignments = _assignments.duplicate(true)
	if not save_game(): state = snapshot; _assignments = assignments_snapshot; _machine = null; _machine_key = ""; return
	changed.emit()
	notified.emit(member_name(id)+": "+str(job.phase)+"。チームで成果を確認できます。")

## Modal settings, pause, and title screens stop passive colleague work.
## Work and management screens leave the office clock running as usual.
func set_office_clock_paused(paused: bool) -> void:
	_office_clock_paused = paused

func _load_copy() -> void:
	if not FileAccess.file_exists(COPY_PATH):
		copy = {}
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(COPY_PATH))
	copy = parsed if parsed is Dictionary else {}

func _default_fields(chapter: int) -> Dictionary:
	var result := {}
	for entry in RULES[chapter]["fields"]:
		result[entry[0]] = int(entry[1])
	return result

func _reset_state() -> void:
	_crew_runtime_registered.clear()
	state = {"version":STATE_VERSION,"maintenance_scope_version":2,"chapter":0,"day":1,"cash":5000,"trust":0,
		"accepted":false,"inspected":false,"config":_default_fields(0),"revision":0,
		"validated_revision":-1,"checks":[],"completed_ids":[],"history":[],
		"equipment":[],"delivery_orders":[],"office_expansion":{"status":"locked","price":28000,"available_day":-1},"assignments":{},"clients":{},"customer_relations":{},"care_agreements":{},"staff":{},"staff_payroll":{"enabled":false,"last_settled_day":-1,"due":[]},"care_incidents":{},"maintenance_targets":{},"maintenance_jobs":[],"maintenance_settled_day":-1,"offer_quotes":{},"quote_decisions":[],"retainer_settled_day":-1,"contract_contexts":{},"contract_closeouts":{},"credit_loss":0,"offer_plan":"standard","pricing_policy":_default_pricing_policy(),"procurement_cart":CUSTOMER_STOCK.empty_cart(),"desktop_sessions":{},"retainer_daily":{},"restore_preview":0,"strategy":"","skills":{"operations":0,"advisory":0,"response":0},"profit":0,"credit":0,"cash_flow_start_day":0,"recurring_clients":[],"strategy_income":0,"career_mode":false,"contracts_completed":0,"current_contract_id":"","offers":[],"market_day":-1,"market_leads":[],"awaiting_contract":false,"game_complete":false,"errors":[],"profile":profile_defaults(),"diagnostics_required":false,"ui_help_seen":{},"dispatch_queues":{},"dispatch_holds":{}}
	_assignments = {}
	state.targets = []; state.target_index = 0; state.contract = {}; state.contract_plan = "standard"; state.offer_plan = "standard"; state.clock_minutes = BUSINESS_START_MINUTE; state.work = {"minutes":0.0,"started_at":BUSINESS_START_MINUTE,"started_day":1,"restarts_failed":0,"resets":0,"incident_cost":0,"plan":"standard"}
	state.vm_states = {}; state.peak_profit = 0; _machine = null; _machine_key = ""
	CUSTOMER_STOCK.ensure(state)
	BILLING.ensure(state)
	COMPANY_CYCLE.ensure(state)
	_load_settings()

func profile_defaults() -> Dictionary:
	return {"company":"あおばセキュリティ相談所","player":"青葉","aya":"綾","ren":"蓮"}

func profile() -> Dictionary:
	var result := profile_defaults()
	var saved = state.get("profile", {})
	if saved is Dictionary:
		for key in result:
			if saved.has(key) and typeof(saved[key]) == TYPE_STRING and profile_error({key:String(saved[key])}).is_empty(): result[key] = String(saved[key]).strip_edges()
	return result.duplicate(true)

func profile_error(values: Dictionary) -> String:
	var limits := {"company":40,"player":20,"aya":20,"ren":20}
	var labels := {"company":"会社名","player":"あなたの名前","aya":"調査担当","ren":"復旧担当"}
	for key in limits:
		if not values.has(key): continue
		if typeof(values[key]) != TYPE_STRING: return "%s は文字列で入力してください" % labels[key]
		var value := String(values[key])
		if value.strip_edges().is_empty(): return "%s は空欄にできません" % labels[key]
		if value.length() > int(limits[key]): return "%s は%d文字以内で入力" % [labels[key],limits[key]]
		for i in value.length():
			var code := value.unicode_at(i)
			if code < 32 or code == 127: return "%s に制御文字は使えません" % labels[key]
	return ""

func set_profile(values: Dictionary) -> bool:
	var input_error := profile_error(values)
	if not input_error.is_empty():
		notified.emit(input_error)
		return false
	var merged := profile()
	for key in merged:
		if values.has(key): merged[key] = String(values[key]).strip_edges()
	var error := profile_error(merged)
	if not error.is_empty():
		notified.emit(error)
		return false
	var previous := profile()
	state.profile = merged.duplicate(true)
	if not save_game():
		state.profile = previous
		return false
	changed.emit()
	return true

func company_name() -> String:
	return profile().company

func player_name() -> String:
	return profile().player

func member_name(id: String) -> String:
	if STAFF_CANDIDATES.has(id):return UI_COPY.copy("staff_name_"+id,id)
	var names := profile()
	return String(names.get(id, id))

func personalize(text: String) -> String:
	var names := profile()
	var sources := ["あおばセキュリティ相談所","青葉","綾","蓮"]
	var replacements := [names.company,names.player,names.aya,names.ren]
	var result := ""
	var cursor := 0
	while cursor < text.length():
		var best_pos := -1
		var best_index := -1
		for i in sources.size():
			var position := text.find(sources[i], cursor)
			if position >= 0 and (best_pos < 0 or position < best_pos):
				best_pos = position; best_index = i
		if best_pos < 0:
			result += text.substr(cursor)
			break
		result += text.substr(cursor, best_pos - cursor) + replacements[best_index]
		cursor = best_pos + sources[best_index].length()
	return result

func _default_pricing_policy() -> Dictionary:
	return {"advisory":100,"operations":100,"response":100}

func _valid_pricing_policy(value: Variant) -> bool:
	if not value is Dictionary: return false
	for category in PRICING_CATEGORIES:
		if not value.has(category): return false
		var amount: Variant = value[category]
		if typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(amount)) or float(amount) != floorf(float(amount)): return false
		var percent := int(amount)
		if percent < PRICING_MIN_PERCENT or percent > PRICING_MAX_PERCENT or posmod(percent - PRICING_MIN_PERCENT, PRICING_STEP_PERCENT) != 0: return false
	for key in value.keys():
		if str(key) not in PRICING_CATEGORIES: return false
	return true

func _valid_procurement_cart(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in value.keys():
		if not CUSTOMER_STOCK.known_sku(str(key)): return false
		var quantity: Variant = value[key]
		if typeof(quantity) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(quantity)) or float(quantity) != floorf(float(quantity)) or int(quantity) < 0 or int(quantity) > 3: return false
	return true

func _load_settings() -> void:
	settings = _default_settings()
	if FileAccess.file_exists(settings_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
		if parsed is Dictionary:
			set_settings(parsed, false)
			if not parsed.has("input_revision"):
				settings.max_fps = 60
				_save_settings()

func _default_settings() -> Dictionary:
	return {"input_revision":2,"quality":"auto","render_scale":0.67,"msaa":0,"shadows":"off","max_fps":60,"vsync":true,"window_mode":"windowed","resolution":"1280x720","fov":70.0,"text_scale":1.0,"volume":50,"effects_volume":65,"ambient_volume":12,"music_volume":35,"mouse_sensitivity":1.0,"invert_y":false}

func _save_settings() -> void:
	var f := FileAccess.open(settings_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings)); f.close()

func _current_chapter(index: int = -1) -> int:
	var target_index := int(state.get("target_index", 0)) if index < 0 else index
	var targets: Array = state.get("targets", [])
	if target_index >= 0 and target_index < targets.size() and targets[target_index] is Dictionary and targets[target_index].has("chapter"):
		return clampi(int(targets[target_index].chapter), 0, RULES.size() - 1)
	return clampi(int(state.get("chapter", 0)), 0, RULES.size() - 1)

func _copy_mission(chapter: int = -1) -> Dictionary:
	var missions = copy.get("missions", [])
	var selected := _current_chapter() if chapter < 0 else chapter
	return missions[selected] if missions is Array and selected < missions.size() else {}

func mission() -> Dictionary:
	if state.is_empty(): _reset_state()
	var chapter := _current_chapter()
	if advanced_active(): return _advanced_mission()
	var rule: Dictionary = RULES[chapter]
	var source: Dictionary = _copy_mission()
	var scenario := _scenario()
	if not scenario.is_empty(): source = scenario
	var fields: Array = []
	var source_fields: Dictionary = source.get("fields", {})
	for entry in rule["fields"]:
		var id: String = entry[0]
		var f: Dictionary = source_fields.get(id, {})
		var options: Array = f.get("options", [])
		if options.is_empty():
			options = _fallback_options(id)
		fields.append({"id":id,"label":String(f.get("label", id)),"options":options,"initial":int(entry[1]),"desired":int(entry[2])})
	var checks: Array = source.get("checks", rule["checks"])
	var base_reward := int(source.get("reward", REWARDS[chapter]))
	var mission_id := String(source.get("id", rule["id"]))
	var category: String = CATEGORIES[chapter]
	base_reward = _specialist_reward(chapter, base_reward)
	var contract: Dictionary = state.get("contract", {})
	if state.get("career_mode", false) and not contract.is_empty(): base_reward = int(contract.reward)
	var result := {"id":mission_id,"title":String(contract.get("title",source.get("title", rule["id"]))),
		"client":String(contract.get("client",source.get("client", ""))),"brief":String(source.get("brief", "")),"contract_brief":String(contract.get("brief","")),"target_title":String(source.get("title","")),
		"service":source.get("service", ""),"console":"WHITE HAT LAB Remote Shell","asset":["files01.client.test:/etc/samba/smb.conf","backup01.client.test:/etc/restic/backup.conf","gateway01.client.test:/etc/firewall/rules.conf","identity01.client.test:/etc/identity/users.conf","edr01.client.test:/etc/edr/policy.conf","portal01.client.test:/etc/share/portal.conf"][chapter],
		"evidence":source.get("evidence", []),"hints":source.get("hints", []),"debrief":String(source.get("debrief", "")),
		"fields":fields,"checks":checks,"reward":base_reward,"base_reward":int(source.get("reward", REWARDS[chapter])),"difficulty":["初級","中級","上級"][clampi(int(contract.get("grade",1))-1,0,2)] if not contract.is_empty() else DIFFICULTIES[chapter],"required_level":contract.get("required_level",1),"required_credit":contract.get("required_credit", REQUIRED_CREDIT[chapter]),"estimated_cost":700,"expected_profit":base_reward - 700,"current_credit":state.get("credit",0),"category":str(contract.get("category",category)),"estimated_workload":chapter + 1}
	if contract.has("maintenance_incident_id"):
		result.maintenance_incident_id = str(contract.maintenance_incident_id)
		result.brief = str(contract.brief); result.debrief = UI_COPY.copy("care_incident_debrief")
		result.service = str(contract.service); result.base_reward = 0; result.estimated_cost = 0; result.expected_profit = 0
	return result

func _advanced_mission() -> Dictionary:
	var contract: Dictionary = state.get("contract", {})
	var case_id := str(contract.get("case_id", ""))
	var view := advanced_view()
	var checks: Array = _advanced_engine().checks(state.advanced)
	var reward := int(contract.get("reward", 0))
	var result := {"id":case_id,"title":str(contract.get("title", UI_COPY.copy("adv_%s_title" % case_id.trim_prefix("advanced-")))),"client":str(contract.get("client", "")),"brief":str(contract.get("brief", UI_COPY.copy("adv_%s_brief" % case_id.trim_prefix("advanced-")))),"contract_brief":str(contract.get("brief", "")),"target_title":UI_COPY.copy("adv_environment"),"service":UI_COPY.copy("adv_service"),"console":"advanced","asset":"","evidence":view.get("events",[]),"hints":[],"debrief":UI_COPY.copy("adv_check_summary"),"fields":[],"checks":checks,"reward":reward,"base_reward":reward,"difficulty":str(contract.get("difficulty", UI_COPY.copy("adv_difficulty", "tier3"))),"required_level":int(contract.get("required_level", 1)),"required_credit":int(contract.get("required_credit", 0)),"estimated_cost":700,"expected_profit":reward-700,"current_credit":int(state.get("credit", 0)),"category":str(contract.get("category", "response")),"estimated_workload":int(contract.get("advanced_work_minutes", 0))}
	if case_id == "advanced-portal":
		result.service = UI_COPY.copy("adv_portal_service")
		result.target_title = "portal.mihama.test"
		result.debrief = UI_COPY.copy("adv_portal_debrief")
		result.difficulty = UI_COPY.copy("portal_difficulty")
	if case_id == SAAS_AI.CASE_ID:
		result.service = "AI連携・公開前審査"
		result.target_title = "北斗物流・AI Gate"
		result.debrief = "資料参照と送付先の許可範囲を実測し、要約の社内受付と外部送信の記録を報告しました。"
	if case_id == SAAS_AI_HANDOFF.CASE_ID:
		result.service = "AI連携・委託先業務"
		result.target_title = "北斗物流・ミナト配送"
		result.debrief = "AI-401の配送連絡、範囲外の拒否、受付期限と前回記録の引継ぎを確認しました。"
	return result

func _specialist_reward(chapter: int, base: int, category_override: String = "") -> int:
	var category := category_override if not category_override.is_empty() else str(CATEGORIES[chapter])
	var rank := int(state.skills.get(category, 0))
	if category == "advisory": return roundi(base * (1.0 if rank <= 0 else (1.35 if rank == 1 else (1.5 if rank == 2 else 1.7 + 0.05 * float(rank - 3)))))
	if category == "response": return roundi(base * (1.0 if rank <= 0 else (1.7 if rank == 1 else (1.95 if rank == 2 else 2.2 + 0.05 * float(rank - 3)))))
	return base

func _fallback_options(id: String) -> Array:
	if id in ["staff", "guest", "partner", "public"]: return ["拒否", "読み取り", "書き込み"]
	if id == "schedule": return ["オフ", "毎日"]
	if id == "location": return ["同じPC", "別の場所"]
	if id == "restore": return ["未テスト", "テスト済み"]
	if id in ["dns", "tls", "mfa"]: return ["オフ", "オン"]
	if id in ["partner_mfa", "transfer_tls", "audit"]: return ["HTTP" if id == "transfer_tls" else "オフ", "HTTPS" if id == "transfer_tls" else "オン"]
	if id == "expires": return ["無期限", "7日間", "30日間"]
	if id in ["business", "admin_public"]: return ["拒否", "許可"]
	if id == "former": return ["有効", "無効"]
	if id == "sessions": return ["保持", "失効"]
	if id == "current": return ["無効", "有効"]
	if id == "endpoint": return ["接続", "隔離"]
	if id == "healthy": return ["接続", "隔離"]
	if id == "logs": return ["保持", "消去"]
	if id == "reset": return ["待機", "再インストール"]
	return ["未設定", "設定済み"]

func _valid_state(candidate: Dictionary) -> bool:
	var required := ["version","chapter","day","cash","trust","accepted","inspected","config","revision","validated_revision","checks","completed_ids","history","equipment","assignments","clients","game_complete","errors"]
	for key in required:
		if not candidate.has(key): return false
	if int(candidate.get("version", -1)) != STATE_VERSION: return false
	if typeof(candidate.get("chapter", -1)) not in [TYPE_INT, TYPE_FLOAT] or int(candidate.get("chapter")) < 0 or int(candidate.get("chapter")) > 5: return false
	if typeof(candidate.get("day", -1)) not in [TYPE_INT, TYPE_FLOAT] or int(candidate.get("day")) < 1: return false
	for key in ["cash", "trust", "revision", "validated_revision"]:
		if typeof(candidate.get(key)) not in [TYPE_INT, TYPE_FLOAT]: return false
	if int(candidate.trust) < 0 or int(candidate.revision) < 0: return false
	for key in ["accepted", "inspected", "game_complete"]:
		if typeof(candidate.get(key)) != TYPE_BOOL: return false
	if candidate.has("strategy") and String(candidate.strategy) not in ["", "operations", "advisory", "response"]: return false
	for key in ["config", "assignments", "clients"]:
		if not candidate.get(key, null) is Dictionary: return false
	for key in ["checks", "completed_ids", "history", "equipment", "errors"]:
		if not candidate.get(key, null) is Array: return false
	if candidate.has("last_load_error") and typeof(candidate.last_load_error) != TYPE_STRING: return false
	if candidate.has("ui_help_seen") and not candidate.ui_help_seen is Dictionary: return false
	for key in ["vm_states", "skills", "contract", "desktop_sessions", "os_files", "work"]:
		if candidate.has(key) and not candidate[key] is Dictionary: return false
	if candidate.has("delivery_orders"):
		if not candidate.delivery_orders is Array: return false
		for order in candidate.delivery_orders:
			if not order is Dictionary or str(order.get("id", "")).is_empty(): return false
	if candidate.has("customer_stock") and not CUSTOMER_STOCK.validate(candidate.customer_stock): return false
	if candidate.has("company_cycle") and not COMPANY_CYCLE.validate(candidate.company_cycle): return false
	if candidate.has("saas_watch") and not SAAS_WATCH.validate(candidate.saas_watch): return false
	if candidate.has("contract_closeouts") and not CAREER_CLOSEOUT.validate(candidate.contract_closeouts): return false
	if candidate.has("credit_loss") and (typeof(candidate.credit_loss) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(candidate.credit_loss)) or float(candidate.credit_loss) < 0.0 or float(candidate.credit_loss) != floorf(float(candidate.credit_loss))): return false
	if candidate.has("pricing_policy") and not _valid_pricing_policy(candidate.pricing_policy): return false
	if candidate.has("procurement_cart") and not _valid_procurement_cart(candidate.procurement_cart): return false
	if candidate.has("cash_flow_start_day") and (typeof(candidate.cash_flow_start_day) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(candidate.cash_flow_start_day)) or float(candidate.cash_flow_start_day) != floorf(float(candidate.cash_flow_start_day)) or int(candidate.cash_flow_start_day) < 0): return false
	if candidate.has("targets"):
		if not candidate.targets is Array: return false
		for target in candidate.targets:
			if not target is Dictionary or not target.get("config", null) is Dictionary or not target.get("checks", null) is Array: return false
	for key in candidate.config:
		if typeof(candidate.config[key]) not in [TYPE_INT, TYPE_FLOAT] or int(candidate.config[key]) < 0: return false
	for key in candidate.assignments:
		var job = candidate.assignments[key]
		if not job is Dictionary or typeof(job.get("status", "")) != TYPE_STRING: return false
		if job.has("remaining") and typeof(job.remaining) not in [TYPE_INT, TYPE_FLOAT]: return false
	return true

func load_game() -> bool:
	if save_path == SAVE_NAME and not _archive_player_save(): return false
	var load_error := ""
	var primary_exists := FileAccess.file_exists(save_path)
	var raw := FileAccess.get_file_as_string(save_path) if primary_exists else ""
	var parsed = _parse_save_json(raw) if primary_exists else null
	var needs_migration := false
	if not parsed is Dictionary or not _valid_state(parsed):
		if primary_exists: _preserve_corrupt(raw)
		var backup_raw := FileAccess.get_file_as_string(backup_path) if FileAccess.file_exists(backup_path) else ""
		var backup_parsed = _parse_save_json(backup_raw)
		if backup_parsed is Dictionary and _valid_state(backup_parsed):
			parsed = backup_parsed
			load_error = "backup_recovered_primary_invalid" if primary_exists else "backup_recovered_primary_missing"
			notified.emit("破損・欠落データをバックアップから復元完了")
		else:
			load_error = "primary_invalid_no_backup" if primary_exists else "primary_missing_no_backup"
			last_load_error = load_error
			notified.emit("セーブデータを読み込めませんでした。既存データは保持されています。")
			return false
	state = parsed
	if not state.has("contract_closeouts"):
		CAREER_CLOSEOUT.ensure(state); needs_migration = true
	if not state.has("credit_loss"):
		state.credit_loss = 0; needs_migration = true
	if not state.has("company_cycle"):
		COMPANY_CYCLE.ensure(state); needs_migration = true
	if not state.has("customer_stock"):
		CUSTOMER_STOCK.ensure(state)
		needs_migration = true
	state.last_load_error = load_error
	if not state.has("billing"):
		BILLING.ensure(state); needs_migration = true
	if not state.has("pricing_policy"):
		state.pricing_policy = _default_pricing_policy(); needs_migration = true
	else:
		var migrated_policy: Dictionary = state.pricing_policy.duplicate(true)
		for category in PRICING_CATEGORIES:
			if not migrated_policy.has(category): migrated_policy[category] = 100; needs_migration = true
		state.pricing_policy = migrated_policy
	if not state.has("procurement_cart"):
		state.procurement_cart = CUSTOMER_STOCK.empty_cart(); needs_migration = true
	else:
		var migrated_cart: Dictionary = state.procurement_cart.duplicate(true)
		for sku in CUSTOMER_STOCK.empty_cart().keys():
			if not migrated_cart.has(sku): migrated_cart[sku] = 0; needs_migration = true
		state.procurement_cart = migrated_cart
	if not state.has("cash_flow_start_day"):
		# Existing saves do not have a trustworthy opening cash row. Start the
		# factual cash-flow window on the next day rather than inventing history.
		state.cash_flow_start_day = int(state.day) + 1; needs_migration = true
	if not state.has("ui_help_seen") or not state.ui_help_seen is Dictionary:
		state.ui_help_seen = {"legacy":true}
		needs_migration = true
	var loaded_profile = state.get("profile", {})
	if loaded_profile is Dictionary:
		var normalized := profile_defaults()
		for key in normalized:
			if loaded_profile.has(key) and typeof(loaded_profile[key]) == TYPE_STRING:
				var candidate := String(loaded_profile[key]).strip_edges()
				if profile_error({key:candidate}).is_empty(): normalized[key] = candidate
		state.profile = normalized
	else:
		state.profile = profile_defaults()
	if not state.has("skills") or not state.skills is Dictionary: state.skills = {"operations":0,"advisory":0,"response":0}
	for sid in ["operations","advisory","response"]: state.skills[sid] = clampi(int(state.skills.get(sid, 0)), 0, 10)
	if not state.has("profit"): state.profit = 0
	if not state.has("credit"): state.credit = 0
	_update_growth()
	if not state.has("strategy"): state.strategy = "advisory" if state.completed_ids.size() > 0 else ""
	if not state.has("recurring_clients"): state.recurring_clients = []
	if not state.has("strategy_income"): state.strategy_income = 0
	if not state.has("customer_relations") or not state.customer_relations is Dictionary: state.customer_relations = {}; needs_migration = true
	if not state.has("care_agreements") or not state.care_agreements is Dictionary: state.care_agreements = {}; needs_migration = true
	if not state.has("contract_contexts") or not state.contract_contexts is Dictionary: state.contract_contexts = {}; needs_migration = true
	if not state.has("offer_plan") or str(state.offer_plan).is_empty(): state.offer_plan = str(state.get("contract_plan", "standard")); needs_migration = true
	if not state.has("desktop_sessions") or not state.desktop_sessions is Dictionary: state.desktop_sessions = {}; needs_migration = true
	if not state.has("retainer_daily") or not state.retainer_daily is Dictionary: state.retainer_daily = {}; needs_migration = true
	if not state.has("staff") or not state.staff is Dictionary: state.staff = {}; needs_migration = true
	if not state.has("dispatch_queues") or not state.dispatch_queues is Dictionary: state.dispatch_queues = {}; needs_migration = true
	if not state.has("dispatch_holds") or not state.dispatch_holds is Dictionary: state.dispatch_holds = {}; needs_migration = true
	if not state.has("staff_payroll") or not state.staff_payroll is Dictionary: state.staff_payroll = {"enabled":false,"last_settled_day":-1,"due":[]}; needs_migration = true
	if not state.staff_payroll.has("due") or not state.staff_payroll.due is Array: state.staff_payroll.due = []; needs_migration = true
	for payroll_item in state.staff_payroll.due:
		if not payroll_item.has("paid_amount"): payroll_item.paid_amount = int(payroll_item.get("amount",0)) if bool(payroll_item.get("paid",false)) else 0; needs_migration = true
	if not state.has("care_incidents") or not state.care_incidents is Dictionary: state.care_incidents = {}; needs_migration = true
	if not state.has("maintenance_targets") or not state.maintenance_targets is Dictionary: state.maintenance_targets = {}; needs_migration = true
	if not state.has("maintenance_jobs") or not state.maintenance_jobs is Array: state.maintenance_jobs = []; needs_migration = true
	if not state.has("maintenance_settled_day"): state.maintenance_settled_day = -1; needs_migration = true
	if not state.has("retainer_settled_day"):
		state.retainer_settled_day = -1
		# Legacy final-story saves have already paid the closing day's retainer;
		# mark that day settled so migration cannot pay it a second time.
		if bool(state.get("game_complete", false)): state.retainer_settled_day = int(state.day)
		elif not state.history.is_empty() and int(state.history[-1].get("day", -1)) == int(state.day) and int(state.history[-1].get("retainer", 0)) > 0: state.retainer_settled_day = int(state.day)
		needs_migration = true
	if not state.has("offer_quotes") or not state.offer_quotes is Dictionary: state.offer_quotes = {}; needs_migration = true
	if not state.has("quote_decisions") or not state.quote_decisions is Array: state.quote_decisions = []; needs_migration = true
	if not state.has("market_day") or typeof(state.market_day) not in [TYPE_INT, TYPE_FLOAT]:
		# Existing boards are already presented to the player; preserve them for
		# this day and begin market rotation on the next successful day advance.
		state.market_day = int(state.day) if not state.get("offers", []).is_empty() else -1
		state.market_leads = []
		for legacy_offer in state.get("offers", []):
			if legacy_offer is Dictionary and bool(legacy_offer.get("unlocked", false)): state.market_leads.append(str(legacy_offer.get("case_id", legacy_offer.get("id", ""))))
		needs_migration = true
	if not state.has("market_leads") or not state.market_leads is Array: state.market_leads = []; needs_migration = true
	for legacy_offer in state.get("offers", []):
		if not legacy_offer is Dictionary: continue
		if not legacy_offer.has("market_available"):
			legacy_offer.market_available = bool(legacy_offer.get("unlocked", false)) and str(legacy_offer.get("case_id", legacy_offer.get("id", ""))) in state.market_leads
			needs_migration = true
		if not legacy_offer.has("market_day"): legacy_offer.market_day = int(state.market_day); needs_migration = true
	if state.quote_decisions.size() > 100: state.quote_decisions = state.quote_decisions.slice(-100); needs_migration = true
	# Legacy recurring clients are grandfathered into explicit agreements. Their
	# existing roster is preserved, while all new agreements require care.
	for legacy_client in state.recurring_clients:
		var legacy_name := str(legacy_client)
		if legacy_name.is_empty(): continue
		if not state.customer_relations.has(legacy_name): state.customer_relations[legacy_name] = {"satisfaction":70,"completed_count":0,"last_quality":"","last_day":0}
		if not state.care_agreements.has(legacy_name):
			state.care_agreements[legacy_name] = {"fee":150 + 600 * int(state.skills.operations),"active":true,"pending":false,"agreed_day":0,"grandfathered":true}
			needs_migration = true
	# Saves from before maintenance targets cannot safely invent a healthy VM.
	# Preserve their recurring payment and expose the agreement as legacy until
	# the next successful delivery records an actual VM snapshot.
	for legacy_name in state.care_agreements.keys():
		var legacy_agreement: Dictionary = state.care_agreements[legacy_name]
		if not state.maintenance_targets.has(str(legacy_name)) and not legacy_agreement.has("maintenance_legacy"):
			legacy_agreement.maintenance_legacy = true
			state.care_agreements[legacy_name] = legacy_agreement
			needs_migration = true
	for key in ["career_mode", "awaiting_contract"]:
		if not state.has(key): state[key] = false
	if not state.has("delivery_orders") or not state.delivery_orders is Array:
		state.delivery_orders = []
		needs_migration = true
	if not state.has("office_expansion") or not state.office_expansion is Dictionary:
		state.office_expansion = {"status":"locked","price":28000,"available_day":-1}
		needs_migration = true
	else:
		if not state.office_expansion.has("status"): state.office_expansion.status = "locked"; needs_migration = true
		if not state.office_expansion.has("price"): state.office_expansion.price = 28000; needs_migration = true
		if not state.office_expansion.has("available_day"): state.office_expansion.available_day = -1; needs_migration = true
	# Existing equipment was already placed in v1.8. Keep it active and mark
	# it as installed so the new order flow never charges or re-delivers it.
	for installed_index in state.equipment.size():
		var installed_id: String = str(state.equipment[installed_index])
		var found_installed := false
		for existing in state.delivery_orders:
			if str(existing.get("id", "")) == str(installed_id) and (str(existing.get("status", "")) == "installed" or bool(existing.get("moving_installed",false))):
				found_installed = true
				break
		if not found_installed:
			var migrated_order := _new_delivery_order(installed_id, 0, "installed")
			migrated_order.install_slot = equipment_slot(str(installed_id))
			state.delivery_orders.append(migrated_order)
			needs_migration = true
	var occupied_workplaces: Array[String] = []
	for worker in state.staff.values():
		if bool(worker.get("active",false)) and str(worker.get("workplace","")) in state.equipment: occupied_workplaces.append(str(worker.workplace))
	for worker in state.staff.values():
		if not bool(worker.get("active",false)) or worker.has("workplace"): continue
		for workplace in ["teamdesk","annexdesk_a","annexdesk_b"]:
			if workplace in state.equipment and workplace not in occupied_workplaces:
				worker.workplace=workplace; occupied_workplaces.append(workplace); needs_migration=true; break
	for restored_order in state.delivery_orders:
		if str(restored_order.get("id","")) == "monitor" and str(restored_order.get("status","")) == "installed":
			var monitor_position: Variant = restored_order.get("install_position",[])
			var legacy_monitor: bool = not monitor_position is Array or monitor_position.size()<3
			if not legacy_monitor:
				legacy_monitor = absf(float(monitor_position[1]))<0.01 or (is_equal_approx(float(monitor_position[0]),2.0) and is_equal_approx(float(monitor_position[2]),-2.8))
			if legacy_monitor:
				var legacy_place := PLACEMENT_RULES.legacy_monitor_placement()
				restored_order.install_position = legacy_place.position
				restored_order.rotation_y = legacy_place.rotation_y
				needs_migration = true
		# A carried box cannot be restored in the player's hand. Put it at the
		# known receiving point while preserving its order and remaining wait.
		if bool(restored_order.get("moving_installed",false)):
			restored_order.status="installed"; restored_order.rotation_y=float(restored_order.get("move_origin_rotation",restored_order.get("rotation_y",0.0)))
			restored_order.erase("moving_installed"); restored_order.erase("move_origin_rotation"); needs_migration=true
		elif str(restored_order.get("status", "")) == "carried" or str(restored_order.get("status", "")) == "placing":
			restored_order.status = "ready"
			restored_order.box_position = _delivery_box_position(str(restored_order.get("id", "")))
			needs_migration = true
	if not state.has("diagnostics_required"): state.diagnostics_required = false
	for key in ["contracts_completed", "target_index"]:
		if not state.has(key): state[key] = 0
	for key in ["offers", "targets"]:
		if not state.has(key): state[key] = []
	if not state.has("current_contract_id"): state.current_contract_id = ""
	if not state.has("contract_plan") or state.contract_plan == "": state.contract_plan = "standard"
	if not state.has("work") or not state.work is Dictionary: state.work = {"minutes":0.0,"started_at":BUSINESS_START_MINUTE,"restarts_failed":0,"resets":0,"incident_cost":0,"plan":state.contract_plan}
	if not state.work.has("started_at"): state.work.started_at = BUSINESS_START_MINUTE; needs_migration = true
	if not state.work.has("started_day"): state.work.started_day = int(state.day); needs_migration = true
	if not state.has("clock_minutes"):
		# Old saves already persisted work minutes. Preserve that elapsed work in
		# the new display clock while keeping an unopened day at 09:00.
		state.clock_minutes = BUSINESS_START_MINUTE + (int(round(float(state.work.get("minutes", 0.0)))) if bool(state.get("accepted", false)) else 0)
		needs_migration = true
	state.clock_minutes = maxi(BUSINESS_START_MINUTE, int(state.get("clock_minutes", BUSINESS_START_MINUTE)))
	if not state.has("contract"): state.contract = {}
	if bool(state.get("career_mode", false)) and bool(state.get("accepted", false)) and state.contract_contexts.is_empty():
		var legacy_id := str(state.get("current_contract_id", "")); if legacy_id.is_empty(): legacy_id = "legacy-career-%d" % int(state.day)
		state.contract_contexts[legacy_id] = _context_from_projection(); state.contract_contexts[legacy_id].id = legacy_id; needs_migration = true
	if not state.has("vm_states"):
		state.vm_states = {}; state.checks = []; state.validated_revision = -1
	if bool(state.get("accepted", false)) and not bool(state.get("career_mode", false)) and state.get("targets", []).is_empty():
		var old_vm: Dictionary = state.vm_states.get("story-%d/site-0" % int(state.chapter), {})
		var changed_before_record: bool = int(old_vm.get("mutation",0)) > 0 or bool(old_vm.get("dirty",false))
		state.targets = [{"config":state.config.duplicate(true),"inspected":state.inspected,"checks":state.checks.duplicate(true),"revision":state.revision,"validated_revision":state.validated_revision,"baseline_recorded":false,"baseline_locked":changed_before_record,"baseline_config":"","baseline_sha":"","baseline_report":"","baseline_report_content":""}]
	_machine = null; _machine_key = ""
	for key in ["config", "checks", "completed_ids", "history", "equipment", "assignments", "clients", "errors"]:
		if not state.has(key): state[key] = {} if key in ["config", "assignments", "clients"] else []
	_assignments = state.get("assignments", {}).duplicate(true)
	_crew_runtime_registered.clear()
	needs_migration = MAINTENANCE_SCOPE.migrate(self) or needs_migration
	if state.get("awaiting_contract",false): _make_offers()
	last_load_error = load_error
	needs_migration = preload("res://scripts/profile_paths.gd").migrate(state) or needs_migration
	if needs_migration or not load_error.is_empty(): save_game()
	changed.emit()
	return true

func _parse_save_json(raw: String):
	var document := JSON.new()
	return document.data if document.parse(raw) == OK else null

func _preserve_corrupt(raw: String) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("/", "-")
	var path := save_path + ".corrupt." + stamp
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(raw)
		f.close()

func new_game(initial_profile: Dictionary = {}) -> bool:
	if not initial_profile.is_empty() and not profile_error(initial_profile).is_empty():
		notified.emit(profile_error(initial_profile))
		return false
	if FileAccess.file_exists(save_path):
		if save_path == SAVE_NAME and not _archive_player_save(): return false
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(previous_path)) != OK:
			notified.emit("現在の保存を退避できないため開始を中止しました")
			return false
	_reset_state()
	if not initial_profile.is_empty():
		var fresh_profile := profile_defaults()
		for key in fresh_profile:
			if initial_profile.has(key): fresh_profile[key] = String(initial_profile[key]).strip_edges()
		state.profile = fresh_profile
	var saved := save_game()
	changed.emit()
	return saved

func _archive_player_save() -> bool:
	# Keep immutable pre-load / pre-new-game copies. Rolling .bak and .previous
	# files alone cannot recover an earlier session after repeated new games.
	if not FileAccess.file_exists(SAVE_NAME): return true
	var directory := "user://save-history"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK: return false
	var digest := FileAccess.get_sha256(SAVE_NAME)
	if digest.is_empty(): return false
	var destination := directory+"/"+digest+".json"
	if FileAccess.file_exists(destination): return true
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_NAME),ProjectSettings.globalize_path(destination)) == OK

func save_game(record_milestones: bool = true) -> bool:
	if _machine != null and not _machine_key.is_empty() and _machine_key == _vm_key():
		state.vm_states[_machine_key] = _machine.export_state()
	_sync_contract_context()
	_sync_target()
	state["assignments"] = _assignments.duplicate(true)
	var save_snapshot: Dictionary = state.duplicate(true)
	COMPANY_CYCLE.ensure(save_snapshot)
	if not COMPANY_CYCLE.validate(save_snapshot.company_cycle):
		notified.emit("保存データ検証失敗。既存データ保持。")
		return false
	var temp_path := save_path + ".tmp"
	var f := FileAccess.open(temp_path, FileAccess.WRITE)
	if f == null:
		notified.emit("保存失敗")
		return false
	# Milestone rewards are staged with this exact successful save. Failed writes
	# cannot award a token or announce an achievement that was not persisted.
	var earned_goals: Dictionary = COMPANY_ROADMAP.earned_after_save(save_snapshot) if record_milestones else save_snapshot.company_cycle.get("earned_goals", {}).duplicate(true)
	save_snapshot.company_cycle.earned_goals = earned_goals
	var serialized := JSON.stringify(save_snapshot, "\t")
	f.store_string(serialized)
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK or not FileAccess.file_exists(temp_path) or FileAccess.get_file_as_string(temp_path) != serialized:
		notified.emit("保存失敗。既存データ保持。")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	var staged = _parse_save_json(serialized)
	if not staged is Dictionary or not _valid_state(staged):
		notified.emit("保存データ検証失敗。既存データ保持。")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	var prior = _parse_save_json(FileAccess.get_file_as_string(save_path)) if FileAccess.file_exists(save_path) else null
	if prior is Dictionary and _valid_state(prior) and DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(backup_path)) != OK:
		notified.emit("既存セーブデータ退避失敗")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	if FileAccess.file_exists(save_path) and not (prior is Dictionary and _valid_state(prior)):
		_preserve_corrupt(FileAccess.get_file_as_string(save_path))
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(save_path)) != OK:
		if FileAccess.file_exists(backup_path): DirAccess.copy_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(save_path))
		notified.emit("保存失敗")
		return false
	COMPANY_CYCLE.ensure(state)
	state.company_cycle.earned_goals = earned_goals
	return true

func set_setting(key: String, value) -> void:
	set_settings({key:value})

func set_settings(values: Dictionary, persist: bool = true) -> void:
	for key in values:
		if not settings.has(key): continue
		var value = values[key]
		match key:
			"quality":
				if String(value) in ["auto","low","medium","high"]: settings[key] = String(value)
			"render_scale": settings[key] = clampf(float(value), 0.5, 1.0)
			"msaa": settings[key] = 0 if int(value) <= 0 else (2 if int(value) <= 2 else 4)
			"shadows":
				if String(value) in ["off","low","high"]: settings[key] = String(value)
			"max_fps": settings[key] = 0 if int(value) <= 0 else (30 if int(value) <= 30 else (60 if int(value) <= 60 else 120))
			"vsync": settings[key] = bool(value)
			"window_mode":
				if String(value) in ["windowed","fullscreen","borderless"]: settings[key] = String(value)
			"resolution":
				if String(value) in ["960x600","1280x720","1600x900","1920x1080"]: settings[key] = String(value)
			"fov": settings[key] = clampf(float(value), 55.0, 100.0)
			"text_scale": settings[key] = clampf(float(value), 0.5, 2.0)
			"volume", "effects_volume", "ambient_volume", "music_volume": settings[key] = clampi(int(value), 0, 100)
			"mouse_sensitivity": settings[key] = clampf(float(value), 0.1, 3.0)
			"invert_y": settings[key] = bool(value)
	if persist: _save_settings()
	changed.emit()

func has_settings() -> bool:
	if not FileAccess.file_exists(settings_path): return false
	return JSON.parse_string(FileAccess.get_file_as_string(settings_path)) is Dictionary

func has_save() -> bool:
	if FileAccess.file_exists(save_path): return true
	if FileAccess.file_exists(backup_path):
		var backup = _parse_save_json(FileAccess.get_file_as_string(backup_path))
		return backup is Dictionary and _valid_state(backup)
	return false
func contract_plans() -> Array:
	return [{"id":"standard","label":"標準","budget":90.0,"multiplier":1.0,"care":false},{"id":"priority","label":"特急","budget":40.0,"multiplier":1.25,"care":false},{"id":"care","label":"保守付き","budget":150.0,"multiplier":0.9,"care":true}]

func _context_from_projection() -> Dictionary:
	return {"id":str(state.get("current_contract_id", "")),"chapter":int(state.get("chapter",0)),"contract":state.get("contract",{}).duplicate(true),"contract_plan":str(state.get("contract_plan","standard")),"accepted":bool(state.get("accepted",false)),"inspected":bool(state.get("inspected",false)),"targets":state.get("targets",[]).duplicate(true),"target_index":int(state.get("target_index",0)),"config":state.get("config",{}).duplicate(true),"checks":state.get("checks",[]).duplicate(true),"revision":int(state.get("revision",0)),"validated_revision":int(state.get("validated_revision",-1)),"work":state.get("work",{}).duplicate(true),"advanced":state.get("advanced",{}).duplicate(true),"baseline_recorded":bool(state.get("baseline_recorded",false)),"baseline_locked":bool(state.get("baseline_locked",false)),"baseline_config":str(state.get("baseline_config","")),"baseline_sha":str(state.get("baseline_sha","")),"baseline_report":str(state.get("baseline_report","")),"baseline_report_content":str(state.get("baseline_report_content","")),"diagnostics_required":bool(state.get("diagnostics_required",false)),"restore_preview":int(state.get("restore_preview",0)),"last_receipt":state.get("last_receipt",{}).duplicate(true),"completed":current_done() if not state.get("current_contract_id","").is_empty() else false}

func _sync_contract_context() -> void:
	if not state.get("career_mode",false) or str(state.get("current_contract_id","")).is_empty(): return
	if _machine != null and _machine_key == _vm_key(): state.vm_states[_machine_key] = _machine.export_state()
	_sync_target()
	state.contract_contexts[str(state.current_contract_id)] = _context_from_projection()
	state.contract_contexts[str(state.current_contract_id)].id = str(state.current_contract_id)

func _activate_contract_context(id: String) -> bool:
	if not state.get("contract_contexts",{}).has(id): return false
	_sync_contract_context()
	var context: Dictionary = state.contract_contexts[id].duplicate(true)
	state.chapter = int(context.get("chapter",state.chapter)); state.current_contract_id=id; state.contract=context.get("contract",{}).duplicate(true); state.contract_plan=str(context.get("contract_plan","standard")); state.accepted=bool(context.get("accepted",false)); state.awaiting_contract=false; state.inspected=bool(context.get("inspected",false)); state.targets=context.get("targets",[]).duplicate(true); state.target_index=int(context.get("target_index",0)); state.config=context.get("config",{}).duplicate(true); state.checks=context.get("checks",[]).duplicate(true); state.revision=int(context.get("revision",0)); state.validated_revision=int(context.get("validated_revision",-1)); state.work=context.get("work",{}).duplicate(true); state.advanced=context.get("advanced",{}).duplicate(true); state.baseline_recorded=bool(context.get("baseline_recorded",false)); state.baseline_locked=bool(context.get("baseline_locked",false)); state.baseline_config=str(context.get("baseline_config","")); state.baseline_sha=str(context.get("baseline_sha","")); state.baseline_report=str(context.get("baseline_report","")); state.baseline_report_content=str(context.get("baseline_report_content","")); state.diagnostics_required=bool(context.get("diagnostics_required",false)); state.restore_preview=int(context.get("restore_preview",0)); state.last_receipt=context.get("last_receipt",{}).duplicate(true); _machine=null; _machine_key=""; return true

func contract_closeout_preview() -> Dictionary:
	return CAREER_CLOSEOUT.preview(self)

func cancel_current_contract() -> bool:
	return CAREER_CLOSEOUT.cancel(self)

func contract_capacity() -> int:
	return 3 + (2 if "teamdesk" in state.get("equipment",[]) else 0) + (1 if "annexdesk_a" in state.get("equipment",[]) else 0) + (1 if "annexdesk_b" in state.get("equipment",[]) else 0)

func office_expanded() -> bool:
	return str(state.get("office_expansion", {}).get("status", "locked")) == "open"

func office_expansion_status() -> Dictionary:
	var expansion: Dictionary = state.get("office_expansion", {})
	return {"status":str(expansion.get("status","locked")),"price":int(expansion.get("price",28000)),"available_day":int(expansion.get("available_day",-1))}

func office_expansion_reason() -> String:
	if office_expanded(): return ""
	var expansion := office_expansion_status()
	if str(expansion.status) == "ordered": return ""
	if not bool(state.get("career_mode",false)): return UI_COPY.copy("expansion_career_only")
	if PLACEMENT_RULES.expansion_blocked(state.get("delivery_orders",[])): return UI_COPY.copy("equipment_route_blocked")
	if int(state.cash) < int(expansion.price): return UI_COPY.copy("expansion_insufficient") % int(expansion.price)
	return ""

func buy_office_expansion() -> bool:
	var expansion := office_expansion_status()
	if not office_expansion_reason().is_empty() or str(expansion.status) != "locked": return false
	var previous := state.duplicate(true)
	state.cash -= int(expansion.price)
	state.history.append({"kind":"investment","day":int(state.day),"equipment_id":"office_expansion","amount":int(expansion.price)})
	state.office_expansion.status = "ordered"
	state.office_expansion.available_day = int(state.day) + 1
	if not save_game():
		state = previous
		return false
	changed.emit()
	return true

func _complete_office_expansion() -> void:
	var expansion: Dictionary = state.get("office_expansion", {})
	if str(expansion.get("status","")) == "ordered" and int(state.day) >= int(expansion.get("available_day", 2147483647)):
		expansion.status = "open"
		expansion.available_day = -1
		state.office_expansion = expansion

func _open_contract_count() -> int:
	var count := 0
	for context in state.get("contract_contexts", {}).values():
		if not bool(context.get("completed", false)): count += 1
	return count

func contract_queue() -> Array:
	_sync_contract_context()
	var out: Array = []
	for id in state.get("contract_contexts",{}).keys():
		var c: Dictionary = state.contract_contexts[id]; var work_info: Dictionary = c.get("work",{}); var start_day := int(work_info.get("started_day",state.day)); var started := int(work_info.get("started_at",BUSINESS_START_MINUTE)); var elapsed := maxi(0,(int(state.day)-start_day)*1440 + int(state.clock_minutes)-started); var contract_data: Dictionary = c.get("contract",{}) if c.get("contract",{}) is Dictionary else {}; var budget := float(contract_data.get("agreed_budget",_contract_budget(int(c.get("chapter",0)),int(c.get("targets",[]).size()),contract_data.get("target_specs",[]),str(c.get("contract_plan","standard"))).budget)); var completed := bool(c.get("completed",false))
		var deadline_total := started + int(round(budget)); var deadline_day := start_day + int(floor(float(deadline_total) / 1440.0)); var deadline_clock := _clock_text(deadline_total)
		out.append({"id":str(id),"client":str(contract_data.get("client","")),"title":str(contract_data.get("title","")),"plan":str(c.get("contract_plan","standard")),"active":str(id)==str(state.current_contract_id),"completed":completed,"deadline_text":UI_COPY.copy("queue_deadline") % [deadline_day,deadline_clock],"remaining":maxf(0.0,budget-float(elapsed)),"late_minutes":maxi(0,elapsed-int(round(budget))),"fee":int(contract_data.get("agreed_fee",0)),"target_count":c.get("targets",[]).size()})
	return out

func offer_plan() -> String:
	return str(state.get("offer_plan",state.get("contract_plan","standard")))

func set_offer_plan(plan: String) -> bool:
	for candidate in contract_plans():
		if str(candidate.id)==plan: state.offer_plan=plan; changed.emit(); return true
	return false

func switch_contract(id: String) -> bool:
	if not state.get("career_mode", false) or not state.contract_contexts.has(id): return false
	var previous_state := state.duplicate(true); var previous_machine = _machine; var previous_key := _machine_key
	if not _activate_contract_context(id): return false
	if not save_game(): state = previous_state; _machine = previous_machine; _machine_key = previous_key; return false
	changed.emit(); return true

func can_end_day() -> bool:
	if state.game_complete or (not state.get("career_mode",false) and not current_done()): return false
	return end_day_reason().is_empty()

func end_day_reason() -> String:
	if not maintenance_end_day_reason().is_empty(): return UI_COPY.copy("queue_end_busy")
	for item in _assignments.values():
		if str(item.get("status",""))=="working": return UI_COPY.copy("queue_end_busy")
	return ""

func set_contract_plan(id: String) -> bool:
	if state.get("accepted", false) or state.get("strategy", "") == "": return false
	for plan in contract_plans():
		if plan.id == id:
			state.contract_plan = id; state.offer_plan = id; save_game(); changed.emit(); return true
	return false
func strategy_catalog() -> Array:
	return [{"id":"operations","title":"運用・監視","description":"保守契約と継続監視","benefit":"新規保守の単価・枠上昇。バックアップ装置・監視モニター20%割引"},{"id":"advisory","title":"診断・改善","description":"診断と改善提案","benefit":"対象案件の報酬35%増"},{"id":"response","title":"事故対応","description":"事故対応と復旧","benefit":"事故対応の報酬70%増"}]

func choose_strategy(id: String) -> bool:
	if state.get("accepted", false) or state.get("strategy", "") != "" or id not in ["operations","advisory","response"]: return false
	state.strategy = id; state.skills[id] = max(1, int(state.skills.get(id, 0)))
	save_game(); changed.emit(); return true

func accept_mission() -> bool:
	if state.game_complete or state.accepted or state.strategy == "" or state.contract_plan == "" or current_done() or state.get("awaiting_contract", false): return false
	if int(state.credit) < REQUIRED_CREDIT[int(state.chapter)] and not (int(state.chapter) > 0 and ("share" if int(state.chapter) == 1 else RULES[int(state.chapter) - 1].id) in state.completed_ids): return false
	var previous_state: Dictionary = state.duplicate(true)
	var previous_assignments: Dictionary = _assignments.duplicate(true)
	var story_client := str(mission().get("client", ""))
	if state.contract_plan == "care" and not _agree_care(story_client): return false
	state.accepted = true
	state.inspected = false
	state.diagnostics_required = true
	state.validated_revision = -1
	state.clock_minutes = BUSINESS_START_MINUTE
	state.work = {"minutes":0.0,"started_at":BUSINESS_START_MINUTE,"restarts_failed":0,"resets":0,"incident_cost":0,"plan":state.contract_plan}
	if not state.get("career_mode", false):
		state.targets = []
	if state.get("targets", []).is_empty():
		state.targets = [{"config":state.config.duplicate(true),"inspected":false,"checks":[],"revision":state.revision,"validated_revision":-1,"baseline_recorded":false,"baseline_locked":false,"baseline_config":"","baseline_sha":"","baseline_report":"","baseline_report_content":""}]
	if not save_game(): state = previous_state; _assignments = previous_assignments; return false
	changed.emit(); return true

func inspect_mission() -> void:
	if not state.accepted: return
	state.inspected = true
	save_game()
	changed.emit()

func _sha256_text(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()

func _target_has_baseline(target: Dictionary, machine_state: Dictionary) -> bool:
	if not bool(target.get("baseline_recorded", false)): return false
	var expected := str(target.get("baseline_config", ""))
	var expected_sha := str(target.get("baseline_sha", ""))
	var config := str(machine_state.get("fs", {}).get("/home/operator/baseline.conf", ""))
	var report := str(machine_state.get("fs", {}).get("/home/operator/baseline-report.txt", ""))
	var expected_report := str(target.get("baseline_report_content", ""))
	return not expected.is_empty() and config == expected and _sha256_text(config) == expected_sha and not expected_report.is_empty() and report == expected_report

func capture_baseline() -> bool:
	if not state.accepted or current_done(): return false
	var machine = _vm()
	if not bool(machine.state.get("connected", false)): return false
	var index := int(state.get("target_index", 0))
	if index >= state.targets.size(): return false
	var target: Dictionary = state.targets[index]
	if bool(target.get("baseline_locked", false)) or bool(target.get("baseline_recorded", false)): return false
	var config := str(machine.state.get("fs", {}).get(machine.state.get("config_path", ""), ""))
	if config.is_empty(): return false
	var sha := _sha256_text(config)
	var report := "WHITE HAT LAB BASELINE\ncompany=%s\noperator=%s\nhost=%s\nconfig_path=%s\nsha256=%s\nservice=%s\nactive=%s\n" % [company_name(),player_name(),str(machine.state.host),str(machine.state.config_path),sha,str(machine.state.service),str(machine.state.active)]
	var previous_state := state.duplicate(true)
	var previous_assignments := _assignments.duplicate(true)
	var previous_vm: Dictionary = machine.export_state()
	var previous_machine_key := _machine_key
	if not machine.write_file("/home/operator/baseline.conf", config) or not machine.write_file("/home/operator/baseline-report.txt", report) or str(machine.read_file("/home/operator/baseline.conf")) != config or sha not in machine.read_file("/home/operator/baseline-report.txt"):
		machine.state = previous_vm
		return false
	_work_add(2.0)
	target.baseline_recorded = true; target.baseline_locked = true; target.baseline_config = config; target.baseline_sha = sha; target.baseline_report = "/home/operator/baseline-report.txt"; target.baseline_report_content = report
	state.targets[index] = target
	state.vm_states[_vm_key()] = machine.export_state()
	if not save_game():
		state = previous_state; _assignments = previous_assignments
		machine.state = previous_vm; _machine = machine; _machine_key = previous_machine_key
		changed.emit()
		return false
	changed.emit()
	return true

func rollback_configuration() -> bool:
	if not state.accepted or current_done(): return false
	var index := int(state.get("target_index", 0))
	if index >= state.targets.size(): return false
	var target: Dictionary = state.targets[index]
	var baseline := str(target.get("baseline_config", ""))
	if not bool(target.get("baseline_recorded", false)) or baseline.is_empty() or not bool(_vm().state.get("connected", false)): return false
	var info := vm_info()
	if not vm_write(info.config_path, baseline): return false
	var result := vm_run("systemctl restart "+str(info.service))
	return not result.begins_with("Job failed") and bool(_vm().state.get("active", false))

func case_review() -> Dictionary:
	if str(state.get("contract", {}).get("case_id", "")) == "advanced-portal" and advanced_active():
		return _portal_case_review()
	if str(state.get("contract", {}).get("case_id", "")) in ["advanced-saas-response", "advanced-saas-watch", "advanced-saas-sessions", SAAS_AI.CASE_ID, SAAS_AI_HANDOFF.CASE_ID] and advanced_active():
		return _saas_case_review()
	var total := maxi(1, state.get("targets", []).size())
	var recorded_sites := 0
	var current_recorded := false
	var objectives: Array = []
	for i in total:
		var target: Dictionary = state.targets[i] if i < state.targets.size() else {}
		var key := _vm_key(i)
		var saved: Dictionary = state.get("vm_states", {}).get(key, {})
		var machine_state: Dictionary = saved
		if i == int(state.get("target_index", 0)) and _machine != null: machine_state = _machine.export_state()
		if _target_has_baseline(target, machine_state):
			recorded_sites += 1
			if i == int(state.get("target_index", 0)): current_recorded = true
	var recorded := recorded_sites == total
	var safe := int(state.get("work", {}).get("restarts_failed", 0)) == 0 and int(state.get("work", {}).get("resets", 0)) == 0
	var status := work_status()
	var on_time := float(status.get("minutes", 0.0)) <= float(status.get("budget", 0.0))
	var available: bool = bool(state.get("accepted", false)) and not current_done() and not state.get("game_complete", false)
	var score := (1 if recorded else 0) + (1 if safe else 0) + (1 if on_time else 0)
	var grade := "S" if score == 3 else ("A" if score == 2 else ("B" if score == 1 else "C"))
	var fee := int(status.get("estimated_fee", 0))
	var bonus := roundi(fee * 0.05) if recorded and not state.get("contract",{}).has("maintenance_incident_id") else 0
	objectives.append({"id":"baseline","title":"変更前の記録","detail":"全拠点の baseline.conf と報告書","done":recorded})
	objectives.append({"id":"safe","title":"安全な作業","detail":"再起動・リセット失敗なし","done":safe})
	objectives.append({"id":"deadline","title":"期限内の納品","detail":"納期内完了","done":on_time})
	return {"available":available,"can_capture":available and int(state.get("target_index",0)) < state.targets.size() and not bool(state.targets[int(state.get("target_index",0))].get("baseline_locked",false)) and bool(_vm().state.get("connected",false)),"recorded":recorded,"current_recorded":current_recorded,"recorded_sites":recorded_sites,"total_sites":total,"score":score,"grade":grade,"bonus":bonus,"objectives":objectives,"record_path":"/home/operator/baseline-report.txt"}

func _saas_case_review() -> Dictionary:
	var checks: Array = _advanced_engine().checks(state.advanced)
	var reported := bool(state.advanced.get("report", {}).get("submitted", false))
	var verified := not checks.is_empty() and checks.all(func(row): return bool(row.get("passed", false)))
	var lost: int = state.advanced.get("egress", {}).get("exported_rows", []).size()
	var business: Dictionary = state.advanced.get("session_case", {}).get("business", {})
	var business_loss := _saas_business_cost(state.advanced)
	var status := work_status()
	var on_time := float(status.get("elapsed_minutes", status.get("minutes", 0))) <= float(status.get("budget", 0))
	var score := int(reported) + int(verified) + int(on_time)
	var objectives: Array = [{"id":"evidence","title":"申請と監査の報告","detail":"保存した原記録","done":reported},{"id":"retest","title":"封じ込めと請求復旧","detail":"現在の接続と実受付","done":verified},{"id":"prevention","title":"流出前の防止","detail":"持出し 延べ%d行" % lost,"done":lost == 0},{"id":"deadline","title":"期限内の納品","detail":"契約の作業期限","done":on_time}]
	if not business.is_empty(): objectives.append({"id":"continuity","title":"顧客業務の締切","detail":"業務遅延の補償 ¥%d" % business_loss,"done":business_loss == 0 and business.get("jobs", []).all(func(job): return str(job.get("status", "")) == "completed")})
	if str(state.advanced.get("model_version", "")) == SAAS_AI.MODEL:
		business = state.advanced.get("ai_preflight", {}).get("business", {})
		objectives = [{"id":"evidence","title":"公開前審査の報告","detail":"方針と模擬ジョブの原記録","done":reported},{"id":"retest","title":"許可範囲と要約受付","detail":"範囲外の拒否とSUM-001の受付","done":verified},{"id":"prevention","title":"外部送信の予防","detail":"持出し 延べ%d行" % lost,"done":lost == 0},{"id":"continuity","title":"要約受付の締切","detail":"業務遅延の補償 ¥%d" % business_loss,"done":business_loss == 0 and str(business.get("status", "")) == "completed"},{"id":"deadline","title":"期限内の納品","detail":"契約の作業期限","done":on_time}]
	if str(state.advanced.get("model_version", "")) == SAAS_AI_HANDOFF.MODEL:
		business = state.advanced.get("handoff", {}).get("business", {})
		objectives = [{"id":"evidence","title":"前回承認と今回記録","detail":"AI-301・正常実行・報告原本","done":reported},{"id":"retest","title":"配送先別の制御","detail":"範囲外拒否と委託先連絡の実測","done":verified},{"id":"prevention","title":"配送情報の保全","detail":"持出し 延べ%d行" % lost,"done":lost == 0},{"id":"continuity","title":"3便連絡の期限","detail":"補償 ¥%d" % business_loss,"done":business_loss == 0 and str(business.get("status", "")) == "completed"},{"id":"deadline","title":"期限内の納品","detail":"契約の作業期限","done":on_time}]
	return {"available":not current_done(),"can_capture":false,"recorded":reported,"current_recorded":reported,"recorded_sites":1 if reported else 0,"total_sites":1,"score":score,"grade":"S" if score == 3 and lost == 0 and business_loss == 0 else "A" if score == 3 else "B" if score == 2 else "C","bonus":roundi(int(status.get("estimated_fee", 0))*0.05) if reported and verified and lost == 0 and business_loss == 0 else 0,"objectives":objectives,"record_path":""}

func _portal_case_review() -> Dictionary:
	# A tester preserves HTTP evidence, not a customer's server configuration.
	var checks: Array = _advanced_engine().checks(state.advanced)
	var report_saved := false
	var retested := true
	for check in checks:
		if str(check.get("id", "")) == "report": report_saved = bool(check.get("passed", false))
		else: retested = retested and bool(check.get("passed", false))
	var status := work_status()
	var on_time := float(status.get("elapsed_minutes", status.get("minutes", 0.0))) <= float(status.get("budget", 0.0))
	var score := int(report_saved) + int(retested) + int(on_time)
	var objectives: Array = [
		{"id":"evidence","title":UI_COPY.copy("portal_review_evidence"),"detail":UI_COPY.copy("portal_review_evidence_detail"),"done":report_saved},
		{"id":"retest","title":UI_COPY.copy("portal_review_retest"),"detail":UI_COPY.copy("portal_review_retest_detail"),"done":retested},
		{"id":"deadline","title":UI_COPY.copy("portal_review_deadline"),"detail":UI_COPY.copy("portal_review_deadline_detail"),"done":on_time}
	]
	return {"available":not current_done() and not state.get("game_complete", false),"can_capture":false,"recorded":report_saved,"current_recorded":report_saved,"recorded_sites":1 if report_saved else 0,"total_sites":1,"score":score,"grade":"S" if score == 3 else ("A" if score == 2 else ("B" if score == 1 else "C")),"bonus":roundi(int(status.get("estimated_fee", 0)) * 0.05) if report_saved else 0,"objectives":objectives,"record_path":""}

func _vm_key(index: int = -1) -> String:
	var contract_id := str(state.current_contract_id) if state.career_mode else "story-%d" % int(state.chapter)
	return "%s/site-%d" % [contract_id, int(state.get("target_index", 0)) if index < 0 else index]

func _vm():
	var key := _vm_key()
	if _machine == null or _machine_key != key:
		_machine = load("res://scripts/virtual_machine.gd").new()
		_machine.setup(_current_chapter(), state.get("vm_states", {}).get(key, {}), _scenario())
		_machine_key = key
	if _machine.has_method("set_identity"):
		_machine.set_identity(profile())
	var hardware := _customer_hardware()
	if not hardware.is_empty():
		_machine.state.customer_device = {"serial":hardware.serial,"model":hardware.model,"supplier":hardware.supplier}
		_machine.state.fs["/etc/hardware.json"] = JSON.stringify(_machine.state.customer_device)
	_bind_linked_identity(_machine)
	_bind_linked_business(_machine)
	return _machine

func _bind_linked_business(machine) -> void:
	var branch: bool = machine.has_method("has_linked_branch_storage") and machine.has_linked_branch_storage()
	if not machine.has_linked_business() and not branch: return
	var provider: Dictionary = {"available":false,"error":"provider_unavailable","fs":{}}
	if branch:
		var source_info := _branch_storage_source()
		provider = _branch_storage_provider_from_state(source_info.machine.state if not source_info.is_empty() else {})
		machine.set_linked_business_provider(provider)
		return
	for provider_index in state.get("targets", []).size():
		if _current_chapter(provider_index) != 1: continue
		var provider_key := _vm_key(provider_index)
		var source = _machine if _machine != null and _machine_key == provider_key else null
		if source == null:
			source = load("res://scripts/virtual_machine.gd").new()
			source.setup(1, state.get("vm_states", {}).get(provider_key, {}), _scenario(provider_index))
		provider = {"available":true,"writable":bool(source.state.get("active",false)),"fs":source.state.fs.duplicate(true)}
		break
	machine.set_linked_business_provider(provider)

func _branch_storage_source() -> Dictionary:
	for provider_index in state.get("targets", []).size():
		if _current_chapter(provider_index) != 0: continue
		var provider_key := _vm_key(provider_index)
		var source = _machine if _machine != null and _machine_key == provider_key else null
		if source == null:
			var saved: Variant = state.get("vm_states", {}).get(provider_key)
			if not saved is Dictionary or int(saved.get("schema", 0)) != 2 or not saved.get("fs") is Dictionary: return {}
			source = load("res://scripts/virtual_machine.gd").new()
			source.setup(0, saved, _scenario(provider_index))
		return {"key":provider_key,"index":provider_index,"machine":source}
	return {}

func _branch_storage_provider_from_state(saved: Dictionary) -> Dictionary:
	var source_fs: Dictionary = saved.get("fs", {}) if saved.get("fs", {}) is Dictionary else {}
	var provider_fs: Dictionary = {}
	if source_fs.has("/srv/share/customers.csv"):
		provider_fs["/srv/share/customers.csv"] = source_fs["/srv/share/customers.csv"]
		provider_fs["/srv/data/customers.csv"] = source_fs["/srv/share/customers.csv"]
	if source_fs.has("/srv/share/partner-order.csv"):
		provider_fs["/srv/share/partner-order.csv"] = source_fs["/srv/share/partner-order.csv"]
		provider_fs["/srv/data/orders.csv"] = source_fs["/srv/share/partner-order.csv"]
	var applied: Dictionary = saved.get("applied", {}) if saved.get("applied", {}) is Dictionary else {}
	var shares: Dictionary = applied.get("shares", {}) if applied.get("shares", {}) is Dictionary else {}
	var share_settings: Dictionary = shares.get("share", {}) if shares.get("share", {}) is Dictionary else {}
	var staff_mode: String = str(applied.get("staff", "none"))
	if int(saved.get("samba_model_version", 1)) >= 2 and not share_settings.is_empty(): staff_mode = str(load("res://scripts/samba_config.gd")._mode(share_settings, "staff"))
	var readable: bool = staff_mode in ["read", "write"]
	var service_available: bool = bool(saved.get("active", false)) and not share_settings.is_empty() and bool(share_settings.get("available", true)) and str(share_settings.get("path", "")) == "/srv/share"
	var provider_error: String = "" if service_available and readable else ("provider_unavailable" if not service_available else "storage_denied")
	var writable: bool = staff_mode == "write" and provider_error.is_empty()
	return {"available":provider_error.is_empty(),"writable":writable,"error":provider_error,"fs":provider_fs,"external_storage":{"enabled":true,"ok":provider_error.is_empty(),"code":200 if provider_error.is_empty() else (403 if provider_error == "storage_denied" else 503),"error":provider_error,"host":"files01.client.test","share":"share","path":"/srv/share/partner-order.csv","writable":writable}}

func _sync_branch_provider(machine) -> bool:
	if _current_chapter() != 5 or not machine.has_linked_branch_storage(): return false
	var provider_fs: Dictionary = machine.linked_business_provider_fs()
	var source_info := _branch_storage_source()
	if source_info.is_empty(): return false
	var source_key := str(source_info.key)
	var path := "/srv/share/partner-order.csv"
	var source = source_info.machine
	if not provider_fs.has(path) or str(source.state.fs.get(path, "")) == str(provider_fs[path]): return false
	source.state.fs[path] = provider_fs[path]
	source._touch("shared storage PUT partner-order.csv")
	state.vm_states[source_key] = source.export_state()
	var target: Dictionary = state.targets[int(source_info.index)]
	target.revision = int(target.get("revision", 0)) + 1
	target.validated_revision = -1
	target.checks = []
	return true

func _prepare_linked_business_contract() -> void:
	var branch: bool = str(state.get("contract", {}).get("case_id", "")) == "composite-branch-reopen"
	if not branch and str(state.get("contract", {}).get("case_id", "")) != "composite-corruption-response": return
	if branch:
		state.contract.linked_branch_version = 1
		state.contract.brief = UI_COPY.copy("branch_brief")
	else:
		state.contract.linked_business_version = 1
		state.contract.brief = UI_COPY.copy("business_corruption_brief")
	var healthy_ledger: String = load("res://scripts/virtual_machine.gd").RECORDS["ledger.txt"]
	for target in state.targets:
		var scenario: Dictionary = CASES.by_id(str(target.case_id)).duplicate(true)
		if branch and int(target.chapter) in [0, 2, 5]:
			scenario.linked_branch_storage = true
		if branch and int(target.chapter) == 0:
			scenario.initial = {"staff":"none","guest":"none"}
			scenario.desired = {"staff":"write","guest":"none"}
			scenario.brief = UI_COPY.copy("branch_share_brief")
			for probe in scenario.probes:
				probe.command = str(probe.get("command", "")).replace("//client/", "//files01.client.test/")
				if str(probe.get("id", "")) == "staff-write": probe.expectation = "OK"
			scenario.probes.append({"id":"branch-source-customers","label":UI_COPY.copy("branch_probe_shared") + " / customers.csv","description":"","command":"sha256sum /srv/share/customers.csv","expectation":load("res://scripts/virtual_machine.gd").RECORDS["customers.csv"].sha256_text()})
			scenario.probes.append({"id":"branch-source-orders","label":UI_COPY.copy("branch_probe_shared") + " / partner-order.csv","description":"","command":"sha256sum /srv/share/partner-order.csv","expectation":load("res://scripts/virtual_machine.gd").RECORDS["orders.csv"].sha256_text()})
		if branch and int(target.chapter) == 2:
			scenario.linked_business = true
			scenario.brief = UI_COPY.copy("branch_gateway_brief")
			scenario.probes.append({"id":"branch-business-orders","label":UI_COPY.copy("branch_probe_orders"),"description":"","command":"curl https://intranet.client.test/api/business/orders","expectation":"status:200|" + load("res://scripts/virtual_machine.gd").RECORDS["orders.csv"].sha256_text()})
		elif branch and int(target.chapter) == 5:
			scenario.brief = UI_COPY.copy("branch_portal_brief")
			scenario.probes.append({"id":"branch-probe-shared","label":UI_COPY.copy("branch_probe_shared"),"description":"","command":"curl -H 'Authorization: Bearer staff-session' 'https://portal.client.test/staff?link=current'","expectation":"status:200"})
		elif int(target.chapter) == 1:
			scenario.brief = UI_COPY.copy("business_backup_brief")
			# This contract approves production replacement after staging. The
			# standalone recovery request instead requires its damaged original
			# to remain untouched; do not inherit that different customer scope.
			scenario.erase("backup_preservation_required")
			scenario.backup_acceptance_mode = "production_replacement"
			scenario.checks = scenario.get("checks", []).slice(0, 3)
			if scenario.checks.size() >= 3:
				scenario.checks[2] = "指定データを復元先へ展開し、正常な保存内容と照合"
		elif int(target.chapter) == 2:
			scenario.linked_business = true
			scenario.brief = UI_COPY.copy("business_gateway_brief")
			scenario.probes.append({"id":"linked-business-ledger","label":UI_COPY.copy("business_probe_ledger"),"description":"","command":"curl https://intranet.client.test/api/business/ledger","expectation":"status:200|"+healthy_ledger.sha256_text()})
		target.scenario = scenario
	if branch:
		# Materialize the provider once at acceptance. Missing later storage must
		# remain unavailable rather than recreating the customer's original data.
		for index in state.targets.size():
			if int(state.targets[index].chapter) != 0: continue
			var source = load("res://scripts/virtual_machine.gd").new()
			source.setup(0, {}, state.targets[index].scenario)
			state.vm_states[_vm_key(index)] = source.export_state()

func _bind_maintenance_business(machine, targets: Array) -> void:
	if machine.has_method("has_linked_branch_storage") and machine.has_linked_branch_storage():
		for source in targets:
			if int(source.get("chapter", -1)) != 0: continue
			var saved: Dictionary = source.get("vm_state", {}) if source.get("vm_state", {}) is Dictionary else {}
			machine.set_linked_business_provider(_branch_storage_provider_from_state(saved)); break
		return
	if not machine.has_linked_business(): return
	var provider: Dictionary = {"available":false}
	for source in targets:
		if int(source.get("chapter", -1)) != 1: continue
		var saved: Dictionary = source.get("vm_state", {})
		provider = {"available":saved.has("fs"),"fs":saved.get("fs",{}).duplicate(true)}
		break
	machine.set_linked_business_provider(provider)

func _bind_linked_identity(machine, index: int = -1) -> void:
	if int(state.get("contract", {}).get("linked_identity_version", 0)) != 1: return
	var target_index := int(state.get("target_index", 0)) if index < 0 else index
	if _current_chapter(target_index) != 5: return
	var provider_snapshot: Dictionary = {}
	for provider_index in state.get("targets", []).size():
		if _current_chapter(provider_index) != 3: continue
		var provider_key := _vm_key(provider_index)
		var provider = _machine if _machine != null and _machine_key == provider_key else null
		if provider == null:
			provider = load("res://scripts/virtual_machine.gd").new()
			provider.setup(3, state.get("vm_states", {}).get(provider_key, {}), _scenario(provider_index))
		provider_snapshot = {"active":bool(provider.state.get("active", false)), "sessions":provider.state.get("identity_sessions", []).duplicate(true), "users":provider.state.get("identity_users", {}).duplicate(true), "realm":str(provider.state.get("host", ""))}
		break
	machine.set_linked_identity_provider(provider_snapshot)

func _prepare_linked_identity_contract() -> void:
	if str(state.get("contract", {}).get("case_id", "")) != "composite-former-access": return
	state.contract.linked_identity_version = 1
	for target in state.targets:
		var scenario: Dictionary = CASES.by_id(str(target.case_id)).duplicate(true)
		if int(target.chapter) == 3:
			scenario.sessions = [{"id":"former-seed-1","user":"former","client":"files-app","ip":"192.0.2.44","issued":1,"revoked":false,"mfa":true},{"id":"current-seed-1","user":"current","client":"files-app","ip":"192.0.2.10","issued":2,"revoked":false,"mfa":true}]
		elif int(target.chapter) == 5:
			scenario.linked_identity = true
			scenario.brief = UI_COPY.copy("linked_identity_portal_brief")
			for probe in scenario.probes:
				if str(probe.get("id", "")) == "staff-read":
					probe.linked_subject = "current"
					probe.command = str(probe.command).replace("staff-session", "current-seed-1")
			scenario.probes.append({"id":"linked-former-session","label":UI_COPY.copy("linked_identity_probe_former"),"description":"","command":"curl -H 'Authorization: Bearer former-seed-1' 'https://portal.client.test/staff?link=current'","expectation":"status:401|linked_session_revoked"})
		target.scenario = scenario

func vm_info() -> Dictionary:
	if not state.accepted: return {"connected":false,"cwd":"/home/operator","host":"client","config_path":"","service":""}
	var machine = _vm()
	return {"connected":bool(machine.state.get("connected", false)) and _customer_hardware_connected(),"cwd":str(machine.state.get("cwd", "/")),"host":str(machine.state.get("host", "client")),"config_path":str(machine.state.get("config_path", "")),"service":str(machine.state.get("service", ""))}

## Read-only monitor projection. Never initialize the game's VM while rendering:
## only a matching live VM export or a saved VM snapshot is eligible for preview.
func service_monitor_snapshot(target_index: int = -1) -> Dictionary:
	var selected_index := int(state.get("target_index", 0)) if target_index < 0 else target_index
	var chapter := _current_chapter(selected_index)
	var key := _vm_key(selected_index)
	var targets: Array = state.get("targets", []) if state.get("targets", []) is Array else []
	var target: Dictionary = targets[selected_index] if selected_index >= 0 and selected_index < targets.size() and targets[selected_index] is Dictionary else {}
	var contract: Dictionary = state.get("contract", {}) if state.get("contract", {}) is Dictionary else {}
	var snapshot: Dictionary = {
		"initialized":false,"connected":false,"host":SERVICE_MONITOR_VM.HOSTS[chapter],
		"service":SERVICE_MONITOR_VM.SERVICES[chapter],"config_path":SERVICE_MONITOR_VM.PATHS[chapter],
		"active":null,"dirty":null,"error":"","applied":{},"pending":{},"models":{},"probes":[],
		"observations":[],"events":[],"fingerprint":"","freshness_known":false,
		"guest_state":{},"portal_files":[],"context":key,"current_revision":int(target.get("revision", state.get("revision", 0))),
		"client":str(contract.get("client", "")),"completed":current_done(),
		"index":selected_index,"name":str(target.get("name", SERVICE_MONITOR_VM.HOSTS[chapter])),"chapter":chapter,
		"current":selected_index == int(state.get("target_index", 0))
	}
	if not bool(state.get("accepted", false)) or selected_index < 0 or selected_index >= targets.size():
		return snapshot
	var live := _machine != null and _machine_key == key
	var saved_vm := _service_monitor_vm_snapshot(selected_index)
	if saved_vm.is_empty():
		return snapshot
	# VM.setup performs compatibility normalization on its input copy. All further
	# bindings and fingerprint work stay on this preview, never on Game._machine.
	var preview = SERVICE_MONITOR_VM.new()
	preview.setup(chapter, saved_vm.duplicate(true), _scenario(selected_index))
	preview.set_identity(profile())
	# Rebind linked inputs from current schema-2 snapshots on the preview. This
	# refreshes consumer fingerprints after another live target's data changes.
	var providers_known := _service_monitor_bind_providers(preview, selected_index)
	var hardware := _customer_hardware(selected_index)
	if not hardware.is_empty():
		preview.state.customer_device = {"serial":str(hardware.get("serial", "")),"model":str(hardware.get("model", "")),"supplier":str(hardware.get("supplier", ""))}
		preview.state.fs["/etc/hardware.json"] = JSON.stringify(preview.state.customer_device)
	var portal_files: Array = preview.portal_snapshot().get("files", []).duplicate(true) if chapter == 5 and int(preview.state.get("portal_model_version", 1)) >= 2 else []
	var probes: Array = preview.probes()
	for item in probes:
		item["freshness_known"] = providers_known
		if not providers_known:
			item["fresh"] = false
			item["passed"] = false
			item["freshness"] = "unknown"
		else:
			item["freshness"] = "fresh" if bool(item.get("fresh", false)) else ("stale" if bool(item.get("recorded", false)) else "unmeasured")
	var pending: Dictionary = preview.state.get("applied", {}).duplicate(true)
	var pending_error := ""
	if int(preview.state.get("firewall_model_version", 1)) >= SERVICE_MONITOR_VM.FIREWALL_MODEL_VERSION:
		var firewall_pending: Variant = preview.state.get("firewall_pending", {})
		if firewall_pending is Dictionary: pending = firewall_pending.duplicate(true)
	else:
		var disk_values: Dictionary = preview._parse_config(str(preview.state.get("fs", {}).get(str(preview.state.get("config_path", "")), "")))
		pending = disk_values.get("values", {}).duplicate(true)
		pending_error = str(disk_values.get("error", ""))
	snapshot.merge({
		"initialized":true,"connected":bool(preview.state.get("connected", false)) and _customer_hardware_connected(selected_index),
		"host":str(preview.state.get("host", SERVICE_MONITOR_VM.HOSTS[chapter])),
		"service":str(preview.state.get("service", SERVICE_MONITOR_VM.SERVICES[chapter])),
		"config_path":str(preview.state.get("config_path", SERVICE_MONITOR_VM.PATHS[chapter])),
		"active":bool(preview.state.get("active", false)),"dirty":bool(preview.state.get("dirty", false)),
		"error":str(preview.state.get("error", "")) if not str(preview.state.get("error", "")).is_empty() else pending_error,
		"applied":preview.state.get("applied", {}).duplicate(true),
		"pending":pending,
		"models":_service_monitor_models(preview.state),"probes":probes,
		"observations":preview.state.get("observations", []).duplicate(true),
		"events":preview.state.get("events", []).duplicate(true),
		"fingerprint":preview._fingerprint(),"freshness_known":providers_known,
		"guest_state":preview.export_state(),"portal_files":portal_files
	}, true)
	return snapshot

func branch_monitor_snapshot() -> Dictionary:
	var contract: Dictionary = state.get("contract", {}) if state.get("contract", {}) is Dictionary else {}
	var case_id := str(contract.get("case_id", ""))
	var result := {"available":bool(state.get("accepted", false)) and case_id == "composite-branch-reopen","client":str(contract.get("client", "")),"case_id":case_id,"current_target":int(state.get("target_index", 0)),"services":[]}
	if not bool(result.available): return result
	var targets: Array = state.get("targets", []) if state.get("targets", []) is Array else []
	var services: Array = []
	for index in targets.size():
		if not targets[index] is Dictionary: continue
		var target: Dictionary = targets[index]
		var projection := service_monitor_snapshot(index)
		services.append({"index":index,"name":str(target.get("name", projection.get("name", ""))),"chapter":int(target.get("chapter", projection.get("chapter", -1))),"context":str(projection.get("context", _vm_key(index))),"snapshot":projection,"current":index == int(state.get("target_index", 0))})
	result.services = services
	return result

func _service_monitor_valid_vm_snapshot(value: Variant) -> bool:
	return value is Dictionary and int(value.get("schema", 0)) == 2 \
		and value.get("fs", null) is Dictionary and value.get("applied", null) is Dictionary \
		and value.get("events", null) is Array and value.get("dirs", null) is Array \
		and value.get("snapshots", null) is Array

func _service_monitor_vm_snapshot(index: int) -> Dictionary:
	var key := _vm_key(index)
	var value: Variant = _machine.export_state() if _machine != null and _machine_key == key else state.get("vm_states", {}).get(key, {})
	return value.duplicate(true) if _service_monitor_valid_vm_snapshot(value) else {}

func _service_monitor_find_target(chapter: int) -> int:
	for index in state.get("targets", []).size():
		if _current_chapter(index) == chapter: return index
	return -1

func _service_monitor_bind_providers(preview, target_index: int) -> bool:
	var known := true
	if preview.has_linked_branch_storage():
		var provider_index := _service_monitor_find_target(0)
		var provider_state := _service_monitor_vm_snapshot(provider_index) if provider_index >= 0 else {}
		if provider_state.is_empty():
			preview.set_linked_business_provider({"available":false,"error":"provider_unavailable","fs":{}})
			known = false
		else:
			# The provider factory accepts a value object. Pass a deep copy so no
			# derived mapping aliases either the saved or live source VM.
			preview.set_linked_business_provider(_branch_storage_provider_from_state(provider_state.duplicate(true)))
	elif preview.has_linked_business():
		var provider_index := _service_monitor_find_target(1)
		var provider_state := _service_monitor_vm_snapshot(provider_index) if provider_index >= 0 else {}
		if provider_state.is_empty():
			preview.set_linked_business_provider({"available":false,"error":"provider_unavailable","fs":{}})
			known = false
		else:
			var source = SERVICE_MONITOR_VM.new()
			source.setup(1, provider_state.duplicate(true), _scenario(provider_index))
			preview.set_linked_business_provider({"available":true,"writable":bool(source.state.get("active", false)),"fs":source.state.get("fs", {}).duplicate(true)})
	if preview.has_linked_identity() and int(state.get("contract", {}).get("linked_identity_version", 0)) == 1 and _current_chapter(target_index) == 5:
		var identity_index := _service_monitor_find_target(3)
		var identity_state := _service_monitor_vm_snapshot(identity_index) if identity_index >= 0 else {}
		if identity_state.is_empty():
			preview.set_linked_identity_provider({})
			known = false
		else:
			var identity_source = SERVICE_MONITOR_VM.new()
			identity_source.setup(3, identity_state.duplicate(true), _scenario(identity_index))
			preview.set_linked_identity_provider({"active":bool(identity_source.state.get("active", false)),"sessions":identity_source.state.get("identity_sessions", []).duplicate(true),"users":identity_source.state.get("identity_users", []).duplicate(true),"realm":str(identity_source.state.get("host", ""))})
	return known

func _service_monitor_models(vm_state: Dictionary) -> Dictionary:
	var result := {}
	for key in ["access_model_version","samba_model_version","backup_model_version","firewall_model_version","identity_model_version","edr_model_version","portal_model_version"]:
		if vm_state.has(key): result[key] = vm_state[key]
	return result


func advanced_active() -> bool:
	return bool(state.get("accepted", false)) and _advanced_case_id(str(state.get("contract", {}).get("case_id", ""))) and state.get("advanced", {}) is Dictionary and not state.advanced.is_empty()

func record_assistant_status() -> Dictionary:
	return preload("res://scripts/company_record_assistant.gd").status(self)

func buy_record_assistant() -> bool:
	return preload("res://scripts/company_record_assistant.gd").purchase(self)

func saas_watch_status() -> Dictionary:
	return SAAS_WATCH.status(self)

func enroll_saas_watch() -> bool:
	return SAAS_WATCH.enroll(self)

func saas_watch_offer() -> Dictionary:
	for offer in state.get("offers", []):
		if str(offer.get("case_id", "")) == "advanced-saas-watch" and bool(offer.get("market_available", false)):
			return offer.duplicate(true)
	return {}

func incident_active() -> bool:
	return advanced_active() and str(state.advanced.get("kind", "")) == "advanced-portal" and bool(state.advanced.get("exercise", {}).get("active", false))

func _advanced_case_id(case_id: String) -> bool:
	return case_id in ["advanced-hunt","advanced-pentest","advanced-pentest-relay","advanced-recovery","advanced-ddos","advanced-api","advanced-supplychain","advanced-cloud","advanced-saas-response","advanced-saas-watch","advanced-saas-sessions",SAAS_AI.CASE_ID,SAAS_AI_HANDOFF.CASE_ID,"advanced-malware","advanced-detection","advanced-portal"]

func _advanced_engine(case_id: String = ""):
	var id := case_id if not case_id.is_empty() else str(state.get("contract", {}).get("case_id", ""))
	if id == "advanced-portal": return load("res://scripts/pentest_portal.gd")
	if id == SAAS_AI.CASE_ID: return load("res://scripts/saas_ai_preflight.gd")
	if id == SAAS_AI_HANDOFF.CASE_ID: return load("res://scripts/saas_ai_handoff.gd")
	if id in ["advanced-saas-response", "advanced-saas-watch", "advanced-saas-sessions"]: return load("res://scripts/saas_response.gd")
	if id in ["advanced-cloud","advanced-malware","advanced-detection"]: return load("res://scripts/advanced_threats.gd")
	if id in ["advanced-ddos","advanced-api","advanced-supplychain"]: return load("res://scripts/advanced_assurance.gd")
	return load("res://scripts/advanced_operations.gd")

func advanced_view(selected: String = "") -> Dictionary:
	if not advanced_active(): return {}
	return _advanced_engine().view(state.advanced, selected)

func _advanced_result_message(result: Dictionary) -> String:
	var explicit := str(result.get("message", ""))
	if not explicit.is_empty(): return explicit
	var key := str(result.get("result_key", ""))
	if key.is_empty(): return ""
	var text := UI_COPY.copy(key, key)
	var args: Array = result.get("result_args", []) if result.get("result_args", []) is Array else []
	if not args.is_empty() and text.contains("%"):
		text = text % args
	return text

func advanced_action(action: String, args: Dictionary = {}) -> Dictionary:
	var exercise_request := advanced_active() and str(state.advanced.get("kind", "")) == "advanced-portal" and (action.begins_with("incident_") or incident_active())
	if not advanced_active() or ((current_done() or bool(state.get("game_complete", false))) and not exercise_request):
		var unavailable := {"ok":false,"changed":false,"minutes":0,"result_key":"adv_unavailable","result_args":[]}
		unavailable.message = _advanced_result_message(unavailable)
		return unavailable
	if str(state.advanced.get("kind", "")) == "advanced-saas-response" and action == "organize_records" and str(args.get("mode", "")) == "assistant" and not bool(record_assistant_status().owned):
		return {"ok":false,"changed":false,"minutes":0,"cost":0,"message":"記録整理助手を導入すると利用できます。手動整理も選べます。"}
	var before := state.duplicate(true)
	var before_assignments := _assignments.duplicate(true)
	var before_machine = _machine
	var before_machine_key := _machine_key
	var result: Dictionary = _advanced_engine().act(state.advanced, action, args)
	if not bool(result.get("changed", false)):
		# Engines may populate last_result even for a rejected action. Keep the
		# persistent context unchanged unless the observation can be saved.
		state = before
		result.message = _advanced_result_message(result)
		return result
	state.advanced = result.get("state", state.advanced)
	if bool(result.get("exercise_only", false)):
		# The operational exercise has its own clock and result. Persist its
		# branch atomically without invalidating paid work or company progress.
		if not save_game():
			state = before; _assignments = before_assignments; _machine = before_machine; _machine_key = before_machine_key
			var exercise_save_failed := {"ok":false,"changed":false,"exercise_only":true,"minutes":0,"result_key":"queue_save_failed","result_args":[]}
			exercise_save_failed.message = _advanced_result_message(exercise_save_failed)
			return exercise_save_failed
		changed.emit()
		result.message = _advanced_result_message(result)
		return result
	if bool(result.get("observed", true)): state.inspected = true
	state.revision = int(state.revision) + 1
	if action in ["verify", "measure", "retest"] and state.advanced.has("measurement_revision"):
		state.advanced.measurement_revision = int(state.advanced.revision)
	state.validated_revision = -1
	var change_cost := maxi(0, int(result.get("cost", 0))) if action == "request_change" and str(state.advanced.get("kind", "")) == "advanced-pentest" else 0
	if change_cost > 0:
		state.work["pentest_change_cost"] = int(state.work.get("pentest_change_cost", 0)) + change_cost
	if str(state.advanced.get("kind", "")) == "advanced-saas-response":
		change_cost = maxi(0, int(result.get("cost", 0)))
		var business_added := maxi(0, _saas_business_cost(state.advanced) - _saas_business_cost(before.get("advanced", {})))
		_record_saas_costs(int(result.get("usage_cost", 0)), maxi(0, int(result.get("impact_cost", 0)) - business_added), business_added)
	_work_add(float(result.get("minutes", 0)), change_cost, true)
	_sync_target()
	if not save_game():
		state = before; _assignments = before_assignments; _machine = before_machine; _machine_key = before_machine_key
		var save_failed := {"ok":false,"changed":false,"minutes":0,"result_key":"queue_save_failed","result_args":[]}
		save_failed.message = _advanced_result_message(save_failed)
		return save_failed
	changed.emit()
	result.message = _advanced_result_message(result)
	return result

func diagnostic_probes() -> Array:
	if not state.get("accepted", false): return []
	if advanced_active(): return _vm_checks()
	var machine = _vm()
	if not machine.has_method("probes"): return []
	return machine.probes()

func run_diagnostic(id: String) -> String:
	for probe in diagnostic_probes():
		if str(probe.get("id", "")) == id:
			if bool(probe.get("requires_login", false)):
				return JSON.stringify({"ok":false,"code":401,"error":"credentials_required","user":str(probe.get("user", ""))})
			return vm_run(str(probe.get("command", "")), "measurement")
	return "指定された診断は見つかりません。"

func _store_vm(before: Array, previous_mutation: int) -> bool:
	state.vm_states[_vm_key()] = _vm().export_state()
	var now: Array = _vm().evaluate()
	if now != before or int(_vm().state.get("mutation", 0)) != previous_mutation:
		state.revision += 1; state.validated_revision = -1; state.checks = []
	if bool(_vm().state.get("connected", false)): state.inspected = true
	var saved := save_game()
	if saved: changed.emit()
	return saved

func _saas_business_cost(model: Dictionary) -> int:
	if str(model.get("model_version", "")) == SAAS_AI.MODEL:
		return maxi(0, int(model.get("ai_preflight", {}).get("business", {}).get("loss_cost", 0)))
	if str(model.get("model_version", "")) == SAAS_AI_HANDOFF.MODEL:
		return maxi(0, int(model.get("handoff", {}).get("business", {}).get("loss_cost", 0)))
	return maxi(0, int(model.get("session_case", {}).get("business", {}).get("loss_cost", 0)))

func _record_saas_costs(usage: int, impact: int, business: int = 0) -> void:
	var costs: Dictionary = state.work.get("saas_costs", {})
	costs["usage_cost"] = int(costs.get("usage_cost", 0)) + maxi(0, usage)
	costs["impact_cost"] = int(costs.get("impact_cost", 0)) + maxi(0, impact)
	costs["assistant_runs"] = int(costs.get("assistant_runs", 0)) + (1 if usage > 0 else 0)
	if business > 0 or costs.has("business_cost"): costs["business_cost"] = int(costs.get("business_cost", 0)) + maxi(0, business)
	state.work["saas_costs"] = costs

func _saas_outcome() -> Dictionary:
	var model: Dictionary = state.get("advanced", {})
	if str(model.get("kind", "")) != "advanced-saas-response": return {}
	var outcome := {"costs":state.work.get("saas_costs", {}).duplicate(true)}
	for key in ["model_version", "elapsed_minutes", "egress", "invoice", "report", "records", "organization", "watch_source", "threat_app_id", "session_case", "ai_preflight", "handoff"]:
		if model.has(key): outcome[key] = model[key].duplicate(true) if model[key] is Dictionary or model[key] is Array else model[key]
	return outcome

func _work_add(minutes: float, cost: int = 0, advance_clock := true) -> void:
	if not state.has("work") or not state.accepted: return
	var added := maxf(0.0, minutes)
	ENDPOINT_ENGAGEMENT.advance(self, added)
	state.work.minutes = float(state.work.get("minutes", 0.0)) + added
	state.work.incident_cost = int(state.work.get("incident_cost", 0)) + cost
	if advanced_active() and not current_done() and str(state.advanced.get("kind", "")) == "advanced-saas-response":
		# The engine already advances explicit SaaS actions. Charge only time
		# added elsewhere (for example acceptance verification), in this save.
		var remaining := maxf(0.0, float(state.work.minutes) - float(state.advanced.get("elapsed_minutes", 0)))
		if remaining > 0:
			var business_before := _saas_business_cost(state.advanced)
			var impact: int = _advanced_engine().advance(state.advanced, remaining)
			var business_added := maxi(0, _saas_business_cost(state.advanced) - business_before)
			state.work.incident_cost = int(state.work.incident_cost) + impact
			_record_saas_costs(0, maxi(0, impact - business_added), business_added)
	if advance_clock:state.clock_minutes = maxi(BUSINESS_START_MINUTE, int(state.get("clock_minutes", BUSINESS_START_MINUTE)) + int(round(added)))

func action_minutes(kind: String, base_minutes: float) -> float:
	var result := base_minutes
	if kind == "edit" and "workstation" in state.equipment: result = maxf(1.0, base_minutes - 2.0)
	if kind == "diagnostic" and "diagnostic" in state.equipment: result = maxf(1.0, base_minutes - 2.0)
	if kind == "measurement" and "diagnostic" in state.equipment: result = maxf(1.0, base_minutes - 1.0)
	return result

## Absolute in-game minutes since midnight. UI panels never call this; the
## office/world may use it for a short walk between desks or the exit.
func clock_minutes() -> int:
	return maxi(BUSINESS_START_MINUTE, int(state.get("clock_minutes", BUSINESS_START_MINUTE)))

func business_clock() -> String:
	var total := clock_minutes()
	return "%02d:%02d" % [int(total / 60) % 24, total % 60]

func advance_office_time(minutes: float = 1.0) -> bool:
	if not state.get("accepted", false) or current_done() or state.get("game_complete", false): return false
	var added := clampf(minutes, 0.25, 10.0)
	state.clock_minutes = clock_minutes() + int(round(added))
	# Walking is part of the deadline clock, but it is not billable work and
	# does not change work_status().minutes or its incident cost.
	changed.emit()
	return true

func office_walk(minutes: float = 1.0) -> bool:
	return advance_office_time(minutes)

func _clock_text(total: int) -> String:
	return "%02d:%02d" % [int(total / 60) % 24, total % 60]

func _lock_baseline_before_change() -> void:
	if state.get("targets", []).is_empty(): return
	var index := int(state.get("target_index", 0))
	if index >= state.targets.size(): return
	var target: Dictionary = state.targets[index]
	if not bool(target.get("baseline_recorded", false)):
		target.baseline_locked = true
		state.targets[index] = target

func vm_run(command: String, work_kind: String = "") -> String:
	if not state.accepted: return "先にメールで案件を受注してください"
	if not _customer_hardware_connected(): return JSON.stringify({"ok":false,"code":409,"error":"hardware_unavailable","message":UI_COPY.copy("stock_error_hardware")})
	if current_done(): return "報告済み案件。案件ボードから次の営業へ進行可能。"
	var transaction_requested := work_kind == "measurement"
	var transaction_state: Dictionary = state.duplicate(true) if transaction_requested else {}
	var transaction_assignments: Dictionary = _assignments.duplicate(true) if transaction_requested else {}
	var transaction_machine = _machine
	var transaction_machine_key := _machine_key
	var transaction_vm_state: Dictionary = _machine.export_state() if transaction_requested and _machine != null and _machine_key == _vm_key() else {}
	var transaction_identity_provider: Dictionary = _machine._linked_identity_provider.duplicate(true) if transaction_requested and _machine != null and _machine_key == _vm_key() else {}
	var transaction_business_provider: Dictionary = _machine._linked_business_provider.duplicate(true) if transaction_requested and _machine != null and _machine_key == _vm_key() else {}
	var machine = _vm()
	var operation := command.strip_edges().trim_prefix("sudo ")
	var console_operation := operation.begins_with("cp ") or int(state.get("contract", {}).get("linked_identity_version", 0)) == 1 or operation.begins_with("identity ") or operation.begins_with("edr ") or operation.begins_with("portal ") or (_current_chapter()==0 and int(machine.state.get("samba_model_version",1))>=2) or (_current_chapter()==1 and int(machine.state.get("backup_model_version",1))>=2) or (operation.begins_with("curl ") and _current_chapter()==5 and int(machine.state.get("portal_model_version",1))>=2)
	console_operation = console_operation or int(machine.state.get("scenario", {}).get("endpoint_engagement", 0)) in [1, 2]
	var transactional := transaction_requested or console_operation
	var previous_state: Dictionary = transaction_state if transaction_requested else (state.duplicate(true) if console_operation else {})
	var previous_assignments: Dictionary = transaction_assignments if transaction_requested else (_assignments.duplicate(true) if console_operation else {})
	var previous_vm: Dictionary = transaction_vm_state if transaction_requested and transaction_machine == machine else (machine.export_state() if console_operation else {})
	var branch_portal: bool = _current_chapter() == 5 and machine.has_linked_branch_storage()
	var previous_provider: Dictionary = machine.linked_business_provider_fs() if branch_portal and transactional else {}
	var config_path := str(machine.state.get("config_path", ""))
	var before_config := str(machine.state.get("fs", {}).get(config_path, ""))
	var before_applied: Dictionary = machine.state.get("applied", {}).duplicate(true)
	var before_active := bool(machine.state.get("active", true))
	var before: Array = _vm().evaluate().duplicate()
	var previous_mutation := int(_vm().state.get("mutation", 0))
	var output: String = _vm().run(command)
	var lower := command.to_lower()
	var normalized := lower.strip_edges()
	if normalized.begins_with("sudo "): normalized = normalized.substr(5).strip_edges()
	var restic_command:=""
	var operation_args: Array=machine._tokens(normalized)
	if not operation_args.is_empty() and operation_args[0]=="restic":
		var index:=1
		while index<operation_args.size():
			if operation_args[index]=="-r":index+=2;continue
			restic_command=str(operation_args[index]);break
	if normalized == "reset-lab --confirm":
		_work_add(30.0, 500); state.work.resets = int(state.work.get("resets", 0)) + 1
	elif normalized.begins_with("systemctl restart"):
		_work_add(10.0)
		if output.begins_with("Job failed"): state.work.restarts_failed = int(state.work.get("restarts_failed", 0)) + 1; _work_add(15.0)
	elif restic_command in ["snapshots","ls","dump"] or (restic_command=="restore" and "--dry-run" in operation_args): pass
	elif restic_command=="backup": _work_add(12.0)
	elif restic_command=="restore": _work_add(15.0)
	elif lower.get_slice(" ",0) in ["help","man","pwd","ls","cat","cd","journalctl","whoami","hostname"]:
		if not state.work.has("reads"): state.work.reads = []
		if lower not in state.work.reads: _work_add(1.0); state.work.reads.append(lower)
	else: _work_add(action_minutes(work_kind, 3.0) if not work_kind.is_empty() else 3.0)
	var changed_config: bool = str(machine.state.get("fs", {}).get(config_path, "")) != before_config
	var changed_service: bool = machine.state.get("applied", {}) != before_applied or bool(machine.state.get("active", true)) != before_active
	if changed_config or changed_service: _lock_baseline_before_change()
	if branch_portal: _sync_branch_provider(machine)
	var stored := _store_vm(before, previous_mutation)
	if transactional and not stored:
		state = previous_state
		_assignments = previous_assignments
		if transaction_machine == machine and not previous_vm.is_empty():
			machine.state = previous_vm
			if transaction_requested:
				machine._linked_identity_provider = transaction_identity_provider
				machine._linked_business_provider = transaction_business_provider
		if branch_portal and transaction_machine == machine: machine.restore_linked_business_provider_fs(previous_provider)
		_machine = transaction_machine
		_machine_key = transaction_machine_key
		changed.emit()
		return "測定結果を保存できませんでした。操作前の状態へ戻しました。" if work_kind == "measurement" else JSON.stringify({"ok":false,"code":507,"error":"save_failed"})
	return output

func firewall_action(action: String, payload: Dictionary = {}) -> Dictionary:
	if not state.accepted or current_done():return {"ok":false,"code":409,"error":"contract_unavailable"}
	if not _customer_hardware_connected():return {"ok":false,"code":409,"error":"hardware_unavailable","detail":UI_COPY.copy("stock_error_hardware")}
	var machine = _vm()
	if _current_chapter()!=2 or int(machine.state.get("firewall_model_version",1))<2:return {"ok":false,"code":400,"error":"unsupported_model"}
	var previous_state: Dictionary=state.duplicate(true);var previous_vm: Dictionary=machine.export_state()
	var before: Array=machine.evaluate().duplicate();var mutation:=int(machine.state.get("mutation",0))
	var result: Dictionary=machine.firewall_action(action,payload)
	if not bool(result.get("ok",false)):return result
	var changed_config: bool=machine.state.fs!=previous_vm.fs or machine.state.applied!=previous_vm.applied
	if changed_config:_lock_baseline_before_change()
	_work_add(10.0 if action=="apply" else action_minutes("edit",8.0) if changed_config else 3.0)
	if not _store_vm(before,mutation):
		state=previous_state;machine.state=previous_vm
		changed.emit()
		return {"ok":false,"code":507,"error":"save_failed"}
	return result

func portal_request(role: String, method: String, age: String, token: String, content: String = "") -> String:
	if not state.accepted or current_done():return "HTTP/1.1 409 Conflict\ncontract unavailable"
	var machine = _vm()
	if _current_chapter()!=5 or int(machine.state.get("portal_model_version",1))<2:return "HTTP/1.1 400 Bad Request\nunsupported_model"
	var previous_state: Dictionary=state.duplicate(true);var previous_vm: Dictionary=machine.export_state();var previous_provider: Dictionary=machine.linked_business_provider_fs() if machine.has_method("linked_business_provider_fs") else {}
	var before: Array=machine.evaluate().duplicate();var mutation:=int(machine.state.get("mutation",0))
	var response: String=machine.portal_request(role,method,age,token,content)
	_work_add(3.0)
	_sync_branch_provider(machine)
	if not _store_vm(before,mutation):
		state=previous_state;machine.state=previous_vm
		if machine.has_method("restore_linked_business_provider_fs"): machine.restore_linked_business_provider_fs(previous_provider)
		changed.emit()
		return "HTTP/1.1 507 Insufficient Storage\nsave_failed"
	return response

func _business_response(result: Dictionary) -> Dictionary:
	var out := result.duplicate(true)
	# A DNS/TLS/policy failure received no HTTP response from the application.
	# Keep structured metadata for the UI, without manufacturing a server status.
	if bool(out.get("transport_error", false)):
		out.response = JSON.stringify(result)
		return out
	var code := int(out.get("code",500))
	var phrase := str({200:"OK",201:"Created",400:"Bad Request",403:"Forbidden",404:"Not Found",409:"Conflict",422:"Unprocessable Entity",429:"Too Many Requests",503:"Service Unavailable",507:"Insufficient Storage"}.get(code,"Error"))
	out.response = "HTTP/1.1 %d %s\nContent-Type: application/json\n\n%s" % [code,phrase,JSON.stringify(result)]
	return out

func _business_owner() -> Dictionary:
	var machine = _vm()
	if machine.has_linked_branch_storage(): return _branch_storage_source()
	if machine.has_linked_business():
		for index in state.get("targets",[]).size():
			if _current_chapter(index) != 1: continue
			var key := _vm_key(index)
			var source = load("res://scripts/virtual_machine.gd").new()
			source.setup(1,state.get("vm_states",{}).get(key,{}),_scenario(index))
			return {"key":key,"index":index,"machine":source}
		return {}
	return {"key":_vm_key(),"index":int(state.get("target_index",0)),"machine":machine}

func business_read(resource: String = "orders", request_url: String = "") -> Dictionary:
	if not bool(state.get("accepted",false)): return _business_response({"ok":false,"code":409,"error":"contract_unavailable"})
	if advanced_active(): return _business_response({"ok":false,"code":400,"error":"unsupported_model"})
	if not _customer_hardware_connected(): return _business_response({"ok":false,"code":503,"error":"hardware_unavailable"})
	var result: Dictionary = _vm().business_read(resource,request_url)
	if result.get("data") is Dictionary:
		var owner := _business_owner()
		result.data.history = owner.machine.state.get("business_journal",[]).duplicate(true) if not owner.is_empty() else []
	if current_done(): result.capabilities.write = false
	return _business_response(result)

func hotel_snapshot() -> Dictionary:
	var version := int(_scenario().get("hotel_workflow_version", 0))
	if not bool(state.get("accepted", false)) or _current_chapter() != 4 or version not in [1, 2]: return {"enabled":false}
	# Acceptance owns initial materialization. Never construct/repair a VM merely
	# to draw the front desk, including a save whose customer file is now missing.
	var key := _vm_key()
	var saved: Dictionary = _machine.state if _machine != null and _machine_key == key else state.get("vm_states", {}).get(key, {"scenario":_scenario()})
	var result: Dictionary = HOTEL_FRONTDESK.snapshot(saved)
	result.client = str(state.get("contract", {}).get("client", result.get("client", "白波ホテル")))
	result.connected = bool(result.get("connected", false)) and _customer_hardware_connected()
	result.workflow_version = version
	result.can_send = not current_done() and version == 1
	result.outcome = HOTEL_FRONTDESK.outcome(saved)
	if version == 2:
		result.reservation = HOTEL_RECOVERY.snapshot(saved)
		result.reservation.connected = bool(result.connected)
		result.reservation.can_send = not current_done()
	return result

func hotel_action(folio_id: String) -> Dictionary:
	if not bool(state.get("accepted", false)) or current_done() or _current_chapter() != 4: return HOTEL_FRONTDESK.rejected(409, "contract_unavailable")
	var version := int(_scenario().get("hotel_workflow_version", 0))
	if version not in [1, 2]: return HOTEL_FRONTDESK.rejected(404, "unsupported_workflow")
	if version == 2 and folio_id != "R-204-NEXT": return HOTEL_FRONTDESK.rejected(409, "prior_folio_read_only")
	if not _customer_hardware_connected(): return HOTEL_FRONTDESK.rejected(503, "hardware_unavailable")
	if not (_machine != null and _machine_key == _vm_key()) and not state.get("vm_states", {}).has(_vm_key()): return HOTEL_FRONTDESK.rejected(422, "data_unavailable")
	var machine = _vm()
	var plan: Dictionary = HOTEL_RECOVERY.plan(machine.state, folio_id, int(state.day), business_clock()) if version == 2 else HOTEL_FRONTDESK.plan(machine.state, folio_id, int(state.day), business_clock())
	if not bool(plan.get("changed", false)): return plan
	var previous := state.duplicate(true)
	var previous_assignments := _assignments.duplicate(true)
	var previous_vm: Dictionary = machine.export_state()
	var previous_key := _machine_key
	# The three working minutes belong to the applied endpoint state before
	# this send completes, just as ordinary EDR commands account their work.
	_work_add(float(plan.get("minutes", 3.0)))
	machine.state.fs[str(plan.get("path", HOTEL_FRONTDESK.PATH))] = str(plan.file)
	if version == 2: machine.state.reservation_journal = plan.journal.duplicate(true)
	else: machine.state.hotel_journal = plan.journal.duplicate(true)
	machine._touch("hotel " + folio_id + " response " + str(plan.code))
	state.vm_states[_vm_key()] = machine.export_state()
	if bool(plan.ok) and not bool(plan.get("duplicate", false)):
		state.revision += 1; state.validated_revision = -1; state.checks = []
	_sync_target()
	if not save_game():
		state = previous; _assignments = previous_assignments
		_machine = machine; _machine_key = previous_key; machine.state = previous_vm
		changed.emit()
		return HOTEL_FRONTDESK.rejected(507, "save_failed")
	plan.erase("file"); plan.erase("journal")
	changed.emit()
	return plan

func network_request_view(url: String) -> Dictionary:
	if not bool(state.get("accepted",false)) or _current_chapter()!=2 or advanced_active(): return {"available":false}
	if _machine == null or _machine_key != _vm_key() or int(_machine.state.get("firewall_model_version",1))<2: return {"available":false}
	if str(_machine.state.get("scenario",{}).get("id",""))!="service-2-case-0": return {"available":false}
	var helper = preload("res://scripts/network_request_evidence.gd")
	var request: Dictionary = helper.request(url)
	if request.is_empty(): return {"available":false}
	var saved: Variant = _machine.state.get("network_request_evidence",{})
	var record: Dictionary = saved.get(url,{}) if saved is Dictionary and saved.get(url,{}) is Dictionary else {}
	var result: Dictionary = helper.project(record,_vm_key(),url,_machine._fingerprint())
	result.available = true
	result.can_test = not current_done() and bool(_machine.state.get("connected",false)) and _customer_hardware_connected()
	var repeated := false
	for probe in _machine.probes():
		if str(probe.get("id",""))=="business-check": repeated = _machine._normalize_command(str(probe.command)) == _machine._normalize_command('curl "'+str(request.request_url)+'"')
	result.minutes = action_minutes("measurement",3.0)*(3.0 if repeated else 4.0)
	return result

func network_request_test(url: String) -> Dictionary:
	var helper = preload("res://scripts/network_request_evidence.gd")
	var request: Dictionary = helper.request(url)
	if request.is_empty(): return {"ok":false,"error":"invalid_request"}
	if not bool(state.get("accepted",false)) or current_done() or _current_chapter()!=2 or advanced_active(): return {"ok":false,"error":"contract_unavailable"}
	if not _customer_hardware_connected(): return {"ok":false,"error":"hardware_unavailable"}
	var machine = _vm()
	if int(machine.state.get("firewall_model_version",1))<2 or not bool(machine.state.get("connected",false)): return {"ok":false,"error":"not_connected"}
	if str(machine.state.get("scenario",{}).get("id",""))!="service-2-case-0": return {"ok":false,"error":"unsupported_case"}
	var previous: Dictionary = state.duplicate(true)
	var previous_vm: Dictionary = machine.export_state()
	var before: Array = machine.evaluate().duplicate()
	var mutation := int(machine.state.get("mutation",0))
	var outputs := {}
	var commands := {}
	var request_command := 'curl "'+str(request.request_url)+'"'
	var reused := false
	var executions := 0
	# Existing acceptance probes remain authoritative; no new mandatory click.
	for probe in machine.probes():
		var id := str(probe.get("id",""))
		if id in ["dns-check","business-check","admin-check"]:
			commands[id] = str(probe.command)
			outputs[id] = machine.run(str(probe.command))
			executions += 1
			if machine._normalize_command(str(probe.command)) == machine._normalize_command(request_command): outputs.request = outputs[id]; reused = true
	commands.request = request_command
	if not reused: outputs.request = machine.run(request_command); executions += 1
	var rows: Array = helper.rows(outputs)
	var passed: bool = rows.all(func(row): return bool(row.passed))
	for probe in machine.probes():
		if str(probe.get("id","")) in ["dns-check","business-check","admin-check"]: passed = passed and bool(probe.get("passed",false))
	var record := {"context":_vm_key(),"url":url,"request_url":request.request_url,"fingerprint":machine._fingerprint(),"rows":rows,"outputs":outputs,"commands":commands,"passed":passed,"day":int(state.day),"clock":business_clock()}
	if not machine.state.get("network_request_evidence",{}) is Dictionary: machine.state.network_request_evidence = {}
	if not machine.state.has("network_request_evidence"): machine.state.network_request_evidence = {}
	machine.state.network_request_evidence[url] = record
	_work_add(action_minutes("measurement",3.0)*float(executions))
	if not _store_vm(before,mutation):
		state = previous; machine.state = previous_vm
		changed.emit()
		return {"ok":false,"error":"save_failed"}
	return {"ok":true,"measurement":record}

func _business_source_path(path: String, branch: bool) -> String:
	if branch and path == BUSINESS_DATA.CUSTOMERS_FILE: return "/srv/share/customers.csv"
	if branch and path == BUSINESS_DATA.ORDERS_FILE: return "/srv/share/partner-order.csv"
	return path

## Current-data probes may follow a committed business change. Recovery snapshots
## and hashes of restored/evidence files retain their original expectations.
func _business_current_probes() -> Array:
	var out: Array = []
	for target in state.get("targets",[]):
		for probe in target.get("scenario",{}).get("probes",[]):
			var command := str(probe.get("command",""))
			if command.begins_with("sha256sum /srv/share/") or command.contains("/api/business/"): out.append(probe)
	return out

func _business_recovery_ready(provider: Dictionary) -> bool:
	for probe in _business_current_probes():
		var command := str(probe.get("command","")); var expected := str(probe.get("expectation",""))
		for name in ["customers.csv","orders.csv","ledger.txt"]:
			var matches: bool = command.contains(name) or (name == "orders.csv" and (command.contains("partner-order.csv") or command.contains("/api/business/orders"))) or (name == "ledger.txt" and command.contains("/api/business/ledger"))
			if not matches: continue
			var file := BUSINESS_DATA._file(provider,name)
			if not bool(file.get("ok",false)) or not expected.contains(str(file.text).sha256_text()): return false
	return true

func _business_follow_hashes(before_provider: Dictionary, writes: Dictionary) -> void:
	var replacements := {}
	for path in writes:
		var old := BUSINESS_DATA._file(before_provider,str(path).get_file())
		if bool(old.get("ok",false)): replacements[str(old.text).sha256_text()] = str(writes[path]).sha256_text()
	for index in state.get("targets",[]).size():
		var target: Dictionary = state.targets[index]
		var key := _vm_key(index)
		var containers: Array = [target.get("scenario",{})]
		if state.vm_states.get(key) is Dictionary: containers.append(state.vm_states[key].get("scenario",{}))
		if index == int(state.get("target_index",0)): containers.append(_vm().state.get("scenario",{}))
		for scenario in containers:
			for probe in scenario.get("probes",[]):
				var command := str(probe.get("command",""))
				if not command.begins_with("sha256sum /srv/share/") and not command.contains("/api/business/"): continue
				var expectation := str(probe.get("expectation",""))
				for prior in replacements: expectation = expectation.replace(str(prior),str(replacements[prior]))
				if expectation != str(probe.get("expectation","")):
					probe.expectation = expectation
					for field in ["recorded","passed","fresh","result","fingerprint","fingerprint_kind","initial_result"]: probe.erase(field)

func business_action(action: String, payload: Dictionary = {}) -> Dictionary:
	if not bool(state.get("accepted",false)) or current_done(): return _business_response(BUSINESS_TRANSACTIONS.rejected(409,"contract_unavailable"))
	var resource := "ledger" if action == "append_ledger" else "orders"
	var current := business_read(resource,str(payload.get("request_url","")))
	if not bool(current.get("ok",false)): return current
	var machine = _vm()
	var provider: Dictionary = machine._business_provider().duplicate(true)
	var owner := _business_owner()
	if owner.is_empty(): return _business_response(BUSINESS_TRANSACTIONS.rejected(503,"provider_unavailable"))
	provider.sequences = owner.machine.state.get("business_sequences",{}).duplicate(true)
	if not _business_recovery_ready(provider): return _business_response(BUSINESS_TRANSACTIONS.rejected(409,"recovery_required"))
	var plan := BUSINESS_TRANSACTIONS.plan(provider,action,payload)
	if not bool(plan.get("ok",false)) or not bool(plan.get("changed",false)): return _business_response(plan)
	var previous := state.duplicate(true); var previous_vm: Dictionary = machine.export_state()
	var previous_provider: Dictionary = machine.linked_business_provider_fs()
	var source = owner.machine
	var branch: bool = machine.has_linked_branch_storage()
	for path in plan.writes: source.state.fs[_business_source_path(str(path),branch)] = plan.writes[path]
	if not source.state.has("business_sequences"): source.state.business_sequences = {}
	source.state.business_sequences.merge(plan.get("sequence",{}),true)
	if not source.state.has("business_journal"): source.state.business_journal = []
	var sequence := 1 if source.state.business_journal.is_empty() else int(source.state.business_journal.back().get("sequence",0))+1
	source.state.business_journal.append({"sequence":sequence,"action":action,"item":plan.item.duplicate(true),"actor":"staff","day":int(state.day)})
	if source.state.business_journal.size() > 256: source.state.business_journal.pop_front()
	source._touch("business " + action)
	state.vm_states[str(owner.key)] = source.export_state()
	_business_follow_hashes(provider,plan.writes)
	# Every dependent service must be measured again against the current bytes.
	for index in state.get("targets",[]).size():
		var target: Dictionary = state.targets[index]
		if index == int(owner.index) or bool(target.get("scenario",{}).get("linked_business",false)) or bool(target.get("scenario",{}).get("linked_branch_storage",false)):
			target.revision = int(target.get("revision",0))+1; target.validated_revision = -1; target.checks = []
	state.revision += 1; state.validated_revision = -1; state.checks = []
	_bind_linked_business(machine)
	_work_add(3.0)
	if not save_game():
		state = previous; machine.state = previous_vm; machine.restore_linked_business_provider_fs(previous_provider); changed.emit()
		return _business_response(BUSINESS_TRANSACTIONS.rejected(507,"save_failed"))
	changed.emit()
	var result := business_read(resource,str(payload.get("request_url","")))
	result.erase("response"); result.changed = true; result.code = int(plan.code); result.item = plan.item
	return _business_response(result)

func vm_list(path: String) -> Array:
	return _vm().list_files(path) if state.accepted else []

func vm_read(path: String) -> String:
	return _vm().read_file(path) if state.accepted else ""

func vm_write(path: String, text: String) -> bool:
	if not state.accepted or current_done(): return false
	if not _customer_hardware_connected(): return false
	if _vm().state.connected and _vm().read_file(path) == text: return true
	var previous_state: Dictionary=state.duplicate(true)
	var machine=_vm()
	var previous_vm: Dictionary=machine.export_state()
	var before: Array = _vm().evaluate().duplicate()
	var previous_mutation := int(_vm().state.get("mutation", 0))
	var config_path := str(_vm().state.get("config_path", ""))
	var before_config := str(_vm().state.get("fs", {}).get(config_path, ""))
	if not _vm().write_file(path, text): return false
	var after_config := str(_vm().state.get("fs", {}).get(config_path, ""))
	_work_add(action_minutes("edit", 8.0))
	if after_config != before_config: _lock_baseline_before_change()
	# Editing configuration invalidates a previously issued validation, even before service reload.
	state.revision += 1; state.validated_revision = -1; state.checks = []
	if not _store_vm(before, previous_mutation):
		state=previous_state; machine.state=previous_vm; changed.emit(); return false
	return true

func _contract_budget(chapter: int, target_count: int, target_specs: Array, plan_id: String) -> Dictionary:
	var plan: Dictionary = {"id":"standard","label":"標準","budget":90.0,"multiplier":1.0}
	for candidate in contract_plans():
		if str(candidate.id) == plan_id: plan = candidate; break
	var chapter_factors: Array[float] = [1.0,1.7,1.25,1.4,1.3,1.5]
	var factor := chapter_factors[clampi(chapter, 0, chapter_factors.size() - 1)]
	if not target_specs.is_empty():
		factor = 0.0
		for spec in target_specs:
			if spec is Dictionary:
				var definition: Dictionary = CaseCatalog.by_id(str(spec.get("case_id", "")))
				var advanced_minutes := int(definition.get("advanced_work_minutes", 0))
				factor += float(advanced_minutes) / 90.0 if advanced_minutes > 0 else chapter_factors[clampi(int(spec.get("chapter", chapter)), 0, chapter_factors.size() - 1)]
		factor = maxf(factor, 1.0)
	var budget: float = float(plan.budget) * factor * (1.0 if not target_specs.is_empty() else maxi(1, target_count))
	return {"plan":plan,"factor":factor,"budget":budget}

func _market_demand(offer: Dictionary) -> Dictionary:
	var category := str(offer.get("category", "advisory"))
	var category_offset: int = int({"advisory":0,"operations":1,"response":2}.get(category, 0))
	var phase := posmod(int(state.get("day", 1)) + int(category_offset), 3)
	var labels := ["相談少なめ", "通常", "相談増加"]
	var caps := [1.05, 1.15, 1.30]
	var label := str(labels[phase])
	var relation: Dictionary = state.customer_relations.get(str(offer.get("client", "")), {"satisfaction":70})
	var satisfaction_bonus := maxi(0, int(relation.get("satisfaction", 70)) - 70) * 5
	return {"label":label,"cap_factor":float(caps[phase]),"satisfaction_bonus":satisfaction_bonus}

func pricing_policy() -> Dictionary:
	var result := _default_pricing_policy()
	var saved: Variant = state.get("pricing_policy", {})
	if saved is Dictionary:
		for category in PRICING_CATEGORIES:
			if saved.has(category): result[category] = clampi(int(saved[category]), PRICING_MIN_PERCENT, PRICING_MAX_PERCENT)
	return result

func set_pricing_policy(category: String, percent: int) -> bool:
	if category not in PRICING_CATEGORIES or percent < PRICING_MIN_PERCENT or percent > PRICING_MAX_PERCENT or posmod(percent - PRICING_MIN_PERCENT, PRICING_STEP_PERCENT) != 0: return false
	var previous := state.duplicate(true)
	if not state.has("pricing_policy") or not state.pricing_policy is Dictionary: state.pricing_policy = _default_pricing_policy()
	state.pricing_policy[category] = percent
	if not _valid_pricing_policy(state.pricing_policy) or not save_game():
		state = previous
		return false
	changed.emit()
	return true

func set_offer_quote(id: String, amount: int) -> bool:
	if state.get("game_complete", false) or amount < 0: return false
	if state.get("contract_contexts",{}).has(id) or id in state.get("completed_ids",[]): return false
	for offer in state.get("offers", []):
		if str(offer.get("id", "")) != id: continue
		if not bool(offer.get("unlocked", false)) or not bool(offer.get("market_available", true)): return false
		var preview := contract_quote(offer)
		var plan_id := str(preview.selected_plan)
		var reference := int(preview.reference_fee)
		if amount > maxi(reference * 10, 1): return false
		var quotes: Dictionary = state.offer_quotes.get(id, {})
		var previous_quotes: Dictionary = state.offer_quotes.duplicate(true)
		quotes[plan_id] = amount; state.offer_quotes[id] = quotes
		if not save_game(): state.offer_quotes = previous_quotes; return false
		changed.emit(); return true
	return false

func contract_quote(offer: Dictionary, quoted_override: int = -1) -> Dictionary:
	var plan_id := str(state.get("offer_plan", "standard"))
	var specs: Array = offer.get("target_specs", []) if offer.get("target_specs", []) is Array else []
	var pricing := _contract_budget(int(offer.get("chapter", state.chapter)), int(offer.get("targets", 1)), specs, plan_id)
	var plan: Dictionary = pricing.plan
	var reference_fee := roundi(float(offer.get("reward", offer.get("base_reward", 0))) * float(plan.multiplier))
	var category := str(offer.get("category", "advisory"))
	var policy := pricing_policy()
	var policy_percent := int(policy.get(category, 100))
	var policy_fee := roundi(float(reference_fee) * float(policy_percent) / 100.0)
	var offer_supply: Dictionary = offer.get("supply_requirement",{}) if offer.get("supply_requirement",{}) is Dictionary else {}
	var supply_cost := int(CUSTOMER_STOCK.product(str(offer_supply.get("sku",CUSTOMER_STOCK.SKU))).get("unit_cost",CUSTOMER_STOCK.UNIT_COST)) if not offer_supply.is_empty() else 0
	var costs := 700 + supply_cost
	var budget := float(pricing.budget)
	var demand := _market_demand(offer)
	var budget_limit := roundi(float(reference_fee) * float(demand.cap_factor) + int(demand.satisfaction_bonus))
	var quoted_fee := policy_fee
	var plan_quotes: Dictionary = state.offer_quotes.get(str(offer.get("id", "")), {})
	var has_saved_quote := plan_quotes.has(str(plan.id))
	if has_saved_quote: quoted_fee = int(plan_quotes[plan.id])
	if quoted_override >= 0: quoted_fee = quoted_override
	var reaction := "discount" if quoted_fee < roundi(reference_fee * 0.9) else ("premium" if quoted_fee > roundi(reference_fee * 1.1) else "fair")
	var affordable := quoted_fee <= budget_limit
	var reason := ""
	if plan.id == "care":
		reason = care_case_reason(offer)
		if reason.is_empty(): reason = care_eligibility(str(offer.get("client", "")))
	if not affordable: reason = "顧客予算 ¥%d を超えています。" % budget_limit
	return {"selected_plan":str(plan.id),"plan_label":str(plan.label),"estimated_fee":quoted_fee,"costs":costs,"budget":budget,"deadline_text":_clock_text(BUSINESS_START_MINUTE + int(round(budget))),"invoice_total":quoted_fee+supply_cost,"net":quoted_fee+supply_cost-costs,"reference_fee":reference_fee,"policy_fee":policy_fee,"policy_percent":policy_percent,"quoted_fee":quoted_fee,"budget_limit":budget_limit,"market_label":str(demand.label),"price_reaction":reaction,"affordable":affordable,"reason":reason,"manual_quote":has_saved_quote or quoted_override >= 0}

func work_status() -> Dictionary:
	var minutes := float(state.get("work", {}).get("minutes", 0.0))
	var started_at := int(state.get("work", {}).get("started_at", BUSINESS_START_MINUTE))
	var started_day := int(state.get("work", {}).get("started_day", state.day))
	var elapsed_minutes := maxf(0.0, float((int(state.day)-started_day)*1440 + clock_minutes() - started_at)) if state.get("accepted", false) else minutes
	var target_specs: Array = state.get("contract", {}).get("target_specs", []) if state.get("contract", {}) is Dictionary else []
	var pricing := _contract_budget(int(state.chapter), int(state.get("targets",[]).size()), target_specs, str(state.get("contract_plan", "standard")))
	var plan: Dictionary = pricing.plan
	var budget: float = float(pricing.budget)
	if state.get("contract", {}) is Dictionary and state.contract.has("agreed_budget"): budget = float(state.contract.agreed_budget)
	var base := int(mission().get("reward", 0))
	var covered: bool = state.get("contract", {}).has("maintenance_incident_id")
	var cost := (0 if covered else 700) + int(state.get("work", {}).get("incident_cost", 0))
	var material_cost := _customer_material_cost()
	cost += material_cost
	var fee := roundi(base * float(plan.multiplier))
	if state.get("contract", {}) is Dictionary and state.contract.has("agreed_fee"): fee = int(state.contract.agreed_fee)
	var quality := "on_time" if elapsed_minutes <= budget else "late"
	if elapsed_minutes <= budget and (int(state.get("work", {}).get("restarts_failed", 0)) > 0 or int(state.get("work",{}).get("resets",0)) > 0): quality = "rework"
	var deadline_total := started_at + int(round(budget))
	var deadline_day := started_day + int(floor(float(deadline_total) / 1440.0))
	var late_minutes := maxi(0, int(round(elapsed_minutes - budget)))
	var late_fee_penalty := roundi(fee * minf(0.2, float(late_minutes) / maxf(budget, 1.0) * 0.2)) if late_minutes > 0 else 0
	var material_billable := bool(state.get("career_mode", false)) and int(state.get("contract", {}).get("billing_version", 0)) == 1
	var invoice_total := fee + (material_cost if material_billable else 0)
	var net := invoice_total - cost if material_billable else fee - cost
	return {"minutes":minutes,"elapsed_minutes":elapsed_minutes,"budget":budget,"time_text":"経過 %d分（作業 %d分） / 納期 %d分" % [elapsed_minutes,minutes,budget],"remaining":maxf(0.0,budget-elapsed_minutes),"quality":quality,"plan_label":UI_COPY.copy("care_incident_covered") if covered else plan.label,"estimated_fee":fee,"costs":cost,"material_cost":material_cost,"material_billable":material_billable,"invoice_total":invoice_total,"cost_breakdown":UI_COPY.copy("stock_work_costs") % [700,int(state.get("work",{}).get("incident_cost",0)),material_cost] if material_cost>0 else UI_COPY.copy("care_incident_costs") % cost if covered else "基本経費 ¥%d + 事故対応 ¥%d" % [700,int(state.get("work", {}).get("incident_cost",0))],"net":net,"phase":"working" if state.accepted else "idle","progress":clampf(elapsed_minutes / maxf(budget,1.0),0.0,1.0),"total":budget,"clock":business_clock(),"deadline_minutes":deadline_total,"deadline_day":deadline_day,"deadline_text":_clock_text(deadline_total),"late_minutes":late_minutes,"late_fee_penalty":late_fee_penalty,"actionable":"あと%d分。急ぐなら設定変更をまとめ、診断結果を確認して納品してください。" % maxi(0, int(ceil(budget-elapsed_minutes))) if elapsed_minutes < budget else ("期限超過。納品前に見込み報酬が¥%d減ります。" % late_fee_penalty if late_fee_penalty > 0 else "期限を超えています。")}

func completion_receipt() -> Dictionary:
	return state.get("last_receipt", {})

func invoice_terms(offer: Dictionary) -> Dictionary:
	var terms: Dictionary = BILLING.terms(offer)
	terms.label = UI_COPY.copy("billing_terms_immediate") if int(terms.days) == 0 else UI_COPY.copy("billing_terms_days") % int(terms.days)
	return terms

func company_invoices() -> Array:
	return BILLING.list(state)

func company_payments() -> Array:
	var billing: Variant = state.get("billing", {})
	if not billing is Dictionary or not billing.get("payments", []) is Array: return []
	return billing.get("payments", []).duplicate(true)

func billing_summary() -> Dictionary:
	return BILLING.summary(state, int(state.day))

func post_invoice(id: String) -> Dictionary:
	var before := state.duplicate(true)
	var result: Dictionary = BILLING.post(state, id)
	if not bool(result.get("ok", false)):
		state = before; return result
	if not save_game():
		state = before; return {"ok":false,"error":"save_failed"}
	changed.emit()
	return result

func _vm_checks(index: int = -1) -> Array:
	if advanced_active() and (index < 0 or index == int(state.get("target_index", 0))):
		var advanced_checks: Array = _advanced_engine().checks(state.advanced)
		for row in advanced_checks:
			if not row.has("label"):
				row.label = UI_COPY.copy(str(row.get("label_key", "")), str(row.get("id", "")))
		return advanced_checks
	var machine = _vm()
	if index >= 0 and index != int(state.get("target_index", 0)):
		machine = load("res://scripts/virtual_machine.gd").new()
		machine.setup(_current_chapter(index), state.get("vm_states", {}).get(_vm_key(index), {}), _scenario(index))
		_bind_linked_identity(machine, index)
		_bind_linked_business(machine)
	var passes: Array = machine.evaluate()
	var target_scenario := _scenario(index)
	var labels: Array = target_scenario.get("checks", mission().checks)
	var result: Array = []
	for i in passes.size(): result.append({"label":str(labels[i]) if i < labels.size() else "検証", "passed":bool(passes[i])})
	if bool(state.get("diagnostics_required", false)) and machine.has_method("probes"):
		for probe in machine.probes():
			var probe_passed: bool = bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))
			result.append({"label":str(probe.get("label", probe.get("id", "診断"))),"passed":probe_passed,"probe":true,"id":str(probe.get("id", ""))})
	if not _customer_requirement(index).is_empty():
		result.append({"label":UI_COPY.copy("stock_hardware_check"),"passed":str(_customer_hardware(index).get("status",""))=="delivered","hardware":true,"id":"customer-hardware"})
	return result

func verify() -> Array:
	if not state.accepted or current_done() or state.game_complete or incident_active(): return []
	if advanced_active():
		var before := state.duplicate(true)
		var before_assignments := _assignments.duplicate(true)
		var before_machine = _machine
		var before_machine_key := _machine_key
		if state.validated_revision != state.revision: _work_add(action_minutes("diagnostic", 6.0))
		var advanced_result := _vm_checks()
		state.checks = advanced_result
		state.validated_revision = state.revision
		_sync_target()
		if not save_game():
			state = before; _assignments = before_assignments; _machine = before_machine; _machine_key = before_machine_key
			return []
		changed.emit()
		return advanced_result
	var previous_state := state.duplicate(true)
	var previous_assignments := _assignments.duplicate(true)
	var previous_machine = _machine
	var previous_machine_key := _machine_key
	var previous_vm: Dictionary = _machine.export_state() if _machine != null else {}
	if state.validated_revision != state.revision: _work_add(action_minutes("diagnostic", 6.0))
	var result := _vm_checks()
	state.checks = result
	if int(state.chapter) == 1: state.restore_preview = 3 if result.size() == 3 and result[0].passed and result[1].passed and result[2].passed else 0
	state.validated_revision = state.revision
	if not save_game():
		state = previous_state; _assignments = previous_assignments
		_machine = previous_machine; _machine_key = previous_machine_key
		if _machine != null: _machine.state = previous_vm
		changed.emit()
		return []
	changed.emit()
	return result

func can_deliver() -> bool:
	if bool(care_conversion_offer().get("available", false)): return false
	if incident_active(): return false
	for queue in _dispatch_queue_map().values():
		for job in queue:
			if str(job.get("kind","normal"))=="normal" and str(job.get("contract_id",""))==str(state.get("current_contract_id","")): return false
	if not state.accepted or not state.inspected or current_done() or state.game_complete or state.validated_revision != state.revision or state.checks.is_empty(): return false
	for job in _assignments.values():
		if str(job.get("kind","normal")) == "normal" and str(job.get("status","")) == "working" and str(job.get("contract_id","")) == str(state.current_contract_id): return false
	var fresh := _vm_checks()
	for check in fresh:
		if not check.get("passed", false): return false
	_sync_target()
	for i in state.get("targets", []).size():
		var target: Dictionary = state.targets[i]
		if not target.inspected or target.validated_revision != target.revision: return false
		for check in _vm_checks(i):
			if not check.passed: return false
	return true

func skill_catalog() -> Array:
	return [
		{"id":"advisory","title":"診断・設計","rank":int(state.skills.advisory),"max_rank":10,"nodes":["権限監査","ネットワーク診断","外部共有設計","診断テンプレート","リスク優先度","顧客説明","設計レビュー","監査手順","品質チェック","主任アドバイザー"],"effects":_skill_effects("advisory"),"current_effect":skill_effect("advisory",int(state.skills.advisory)),"next_effect":skill_effect("advisory",int(state.skills.advisory)+1),"description":"診断案件の報酬が段階的に増えます（Lv4以降は+5%ずつ）。"},
		{"id":"operations","title":"監視・運用","rank":int(state.skills.operations),"max_rank":10,"nodes":["バックアップ運用","ID管理","継続監査","運用手順","保守計画","稼働監視","変更管理","復旧演習","自動点検","運用リーダー"],"effects":_skill_effects("operations"),"current_effect":skill_effect("operations",int(state.skills.operations)),"next_effect":skill_effect("operations",int(state.skills.operations)+1),"description":"新規保守契約の日額が1ランクごとに¥600増え、契約枠も1件増えます。合意済みの日額は変わりません。バックアップ装置と監視モニターは20%割引になります。"},
		{"id":"response","title":"調査・復旧","rank":int(state.skills.response),"max_rank":10,"nodes":["ログ分析","端末隔離","証拠保全","初動手順","影響範囲","復旧計画","証拠レビュー","再発防止","対応訓練","主任レスポンダー"],"effects":_skill_effects("response"),"current_effect":skill_effect("response",int(state.skills.response)),"next_effect":skill_effect("response",int(state.skills.response)+1),"description":"対応案件の報酬が段階的に増えます（Lv4以降は+5%ずつ）。"}]

func skill_effect(id: String, rank: int = -1) -> String:
	var level := int(state.skills.get(id, 0)) if rank < 0 else clampi(rank, 0, 10)
	if level <= 0: return "未習得（案件の基礎報酬）"
	if id == "operations": return "新規保守契約 ¥%d/日（契約時固定）・枠 +%d" % [600 * level + 150, level]
	if id == "advisory":
		var multiplier := 1.35 if level == 1 else (1.5 if level == 2 else 1.7 + 0.05 * float(level - 3))
		return "診断案件の報酬 +%d%%" % roundi((multiplier - 1.0) * 100.0)
	if id == "response":
		var multiplier := 1.7 if level == 1 else (1.95 if level == 2 else 2.2 + 0.05 * float(level - 3))
		return "対応案件の報酬 +%d%%" % roundi((multiplier - 1.0) * 100.0)
	return ""

func _skill_effects(id: String) -> Array:
	var effects: Array = []
	for rank in range(1, 11): effects.append(skill_effect(id, rank))
	return effects

func service_catalog() -> Array:
	var services: Array = []
	for i in RULES.size():
		var source: Dictionary = copy.missions[i]
		var category: String=CATEGORIES[i]
		services.append({"title":source.get("service", source.title),"required_credit":0,"category":category,"unlocked":int(state.skills.get(category,0))>=1})
	return services

func skill_points() -> int:
	var earned := 1
	for threshold in SKILL_THRESHOLDS:
		if int(state.credit) >= threshold: earned += 1
	earned = maxi(earned,mini(9,1+floori(float(company_level().level)/2.0)))
	var spent := 0
	for id in state.skills: spent += int(state.skills[id])
	return max(0, earned - spent)

func learn_skill(id: String) -> bool:
	if id not in ["operations","advisory","response"] or skill_points() <= 0 or int(state.skills.get(id, 0)) >= 10: return false
	var previous_state: Dictionary = state.duplicate(true)
	var previous_skills: Dictionary = state.skills.duplicate(true)
	state.skills[id] = int(state.skills.get(id, 0)) + 1
	if state.get("career_mode", false): _make_offers(previous_skills)
	if not save_game():
		state = previous_state
		return false
	changed.emit(); return true

func _update_growth() -> void:
	state.peak_profit = maxi(int(state.get("peak_profit",0)),maxi(int(state.profit),int(state.credit)*100))
	state.credit = maxi(int(state.credit), maxi(0, floori(int(state.peak_profit) / 100) - maxi(0,int(state.get("credit_loss",0)))))
	state.trust = int(state.credit)

func company_level() -> Dictionary:
	var xp := maxi(int(state.get("peak_profit",0)),maxi(int(state.get("profit",0)),int(state.get("credit",0))*100))
	var level := 1
	for threshold in LEVEL_XP:
		if xp >= threshold: level += 1
	level = clampi(level-1,1,LEVEL_XP.size())
	var floor_xp: int = LEVEL_XP[level-1]
	var next_xp: int = LEVEL_XP[level] if level < LEVEL_XP.size() else floor_xp
	var unlocks := {2:"新規初級案件・スキルポイント獲得",3:"SaaS緊急対応・記録整理助手（調査復旧1）",4:"スキルポイント",5:"中級の専門案件",7:"追加の中級案件",8:"2拠点の契約",10:"上級の専門案件",12:"追加の上級案件",15:"3拠点の契約",20:"会社ランク最高位"}
	var next_unlock := "最高レベル達成"
	for at in unlocks:
		if level < int(at): next_unlock = "Lv.%d  %s" % [at,unlocks[at]]; break
	return {"level":level,"xp":xp,"current_floor":floor_xp,"next_threshold":next_xp,"progress":clampf(float(xp-floor_xp)/maxf(1.0,float(next_xp-floor_xp)),0.0,1.0) if level<20 else 1.0,"next_unlock":next_unlock,"label":["駆け出しの会社","専門事務所","地域のセキュリティ企業","広域対応チーム","指名される会社"][4 if level==20 else (3 if level>=15 else (2 if level>=10 else (1 if level>=5 else 0)))]}

func work_guidance() -> Dictionary:
	if state.get("strategy","") == "": return {"title":"最初の専門分野を選ぶ","detail":"会社・スキルで得意分野を決めると受注できます。","app":"mail","command":""}
	if state.get("awaiting_contract",false): return {"title":"今日の依頼を選ぶ","detail":"案件ボードで会社レベルと専門スキルに合う仕事を選びます。","app":"mail","command":""}
	if current_done(): return {"title":"納品完了。精算確認後、翌日へ","detail":"%sの利益が会社の経験値になります。" % company_name(),"app":"receipt","command":""}
	if not state.accepted: return {"title":"メールで依頼内容を確認して受注","detail":"契約プランにより納期と報酬が変動。推奨：標準。%sが受注を決定。" % player_name(),"app":"mail","command":""}
	if advanced_active():
		var advanced_checks := _vm_checks()
		for check in advanced_checks:
			if not bool(check.get("passed", false)):
				return {"title":mission().title,"detail":mission().brief,"app":"advanced","command":"","advanced_view":"overview","advanced_selected":str(check.get("id", ""))}
		return {"title":UI_COPY.copy("adv_check_summary","Advanced verification"),"detail":UI_COPY.copy("adv_service","Complete the advanced operation and verify the result."),"app":"advanced","command":"","advanced_view":"overview"}
	var info := vm_info()
	if not info.connected: return {"title":"顧客の仮想端末へ接続","detail":"%sがターミナルで「接続 SSH」を実行。" % player_name(),"app":"terminal","command":"ssh client"}
	var console_title: String = {0:UI_COPY.copy("samba_title"),1:"Backrest",2:UI_COPY.copy("fw_rules"),3:UI_COPY.copy("identity_title"),4:UI_COPY.copy("edr_title"),5:UI_COPY.copy("portal_title")}.get(_current_chapter(),"")
	var model_key: String = ["samba_model_version","backup_model_version","firewall_model_version","identity_model_version","edr_model_version","portal_model_version"][_current_chapter()]
	var has_console: bool = int(_vm().state.get(model_key,1))>=2
	if bool(_vm().state.get("dirty",false)): return {"title":console_title if has_console else "保存した設定をサービスに反映","detail":"","app":"browser" if has_console else "monitor","command":"systemctl restart "+str(info.service)}
	if not bool(_vm().state.active): return {"title":"設定エラー修正","detail":str(_vm().state.error),"app":"editor","command":"edit "+str(info.config_path)}
	if _current_chapter()==3 and int(_vm().state.get("identity_model_version",1))>=2:
		if not _vm().evaluate().all(func(p):return p): return {"title":UI_COPY.copy("identity_title","Identity management"),"detail":"","app":"browser","command":"","identity_view":"users"}
		for probe in diagnostic_probes():
			if bool(probe.get("requires_login",false)) and not bool(probe.get("passed",false)):
				return {"title":UI_COPY.copy("identity_test_login","Test login"),"detail":"","app":"browser","command":"","identity_view":"login","identity_user":str(probe.get("user","current"))}
		var business: Array = _vm().probes().filter(func(probe):return str(probe.id)=="current-business")
		if not business.is_empty() and not business[0].passed:
			return {"title":UI_COPY.copy("identity_test_login","Test login"),"detail":"","app":"browser","command":"","identity_view":"login"}
	if _current_chapter()==4 and int(_vm().state.get("edr_model_version",1))>=2 and not _vm().evaluate().all(func(p):return p):
		if bool(_vm().state.get("scenario",{}).get("edr_recovery_required",false)):
			var snap: Dictionary = _vm().edr_snapshot()
			if not bool(snap.get("evidence",{}).get("valid",false)):
				return {"title":UI_COPY.copy("edr_collect"),"detail":"","app":"browser","command":"","edr_view":"devices","edr_device":"pc_a"}
			for device in snap.get("devices",[]):
				if not bool(device.get("scan_current",false)):
					return {"title":UI_COPY.copy("rmd_guide_scan"),"detail":"","app":"browser","command":"","edr_view":"devices","edr_device":str(device.id)}
				if not bool(device.get("scan_clean",false)):
					return {"title":UI_COPY.copy("rmd_guide_review"),"detail":"","app":"browser","command":"","edr_view":"devices","edr_device":str(device.id)}
				if not bool(device.get("business_available",false)):
					return {"title":UI_COPY.copy("rmd_restore"),"detail":"","app":"browser","command":"","edr_view":"actions"}
			return {"title":UI_COPY.copy("rmd_guide_reconnect"),"detail":"","app":"browser","command":"","edr_view":"devices"}
		return {"title":UI_COPY.copy("edr_title","Endpoint security"),"detail":"","app":"browser","command":"","edr_view":"devices"}
	if has_console and not _vm().evaluate().all(func(p):return p):
		return {"title":console_title,"detail":"","app":"browser","command":""}
	if bool(state.get("diagnostics_required", false)) and _vm().has_method("probes"):
		for probe in _vm().probes():
			if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))):
				return {"title":"実測診断を実行","detail":"許可される通信と拒否される通信を端末で確認します。","app":"verify","command":str(probe.get("command", ""))}
	if can_deliver(): return {"title":"検証に合格。メールから納品","detail":"納品・精算画面で報酬・経費・経験値を確認可能。","app":"receipt","command":""}
	if _vm().evaluate().all(func(p): return p): return {"title":"動作検証を実行","detail":"条件を満たしました。検証を実行してから納品してください。","app":"verify","command":""}
	if int(state.chapter)==1 and str(_vm().state.applied.get("schedule","off")) == "daily": return {"title":"バックアップを復元して内容を確認","detail":"既存バックアップは snapshots で確認できます。%sに復元を依頼することも可能です。" % member_name("ren"),"app":"terminal","command":"restic snapshots"}
	return {"title":"依頼条件と現在設定の比較","detail":"リファレンスで対象ファイル・手順を確認。%sにログ調査依頼可能。" % member_name("aya"),"app":"manual","command":"cat "+str(info.config_path)}

func continue_business() -> bool:
	if not state.game_complete or state.career_mode: return false
	var previous_state := state.duplicate(true); var previous_assignments := _assignments.duplicate(true); var previous_machine = _machine; var previous_key := _machine_key
	state.career_mode = true; state.game_complete = false; state.day = 7; state.awaiting_contract = true; state.accepted = false; state.staff_payroll.enabled = true
	_make_offers()
	if not save_game(): state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_key; return false
	changed.emit(); return true

func _make_offers(previous_skills: Dictionary = {}) -> void:
	var new_market_day := int(state.get("market_day", -1)) != int(state.day)
	if new_market_day: COMPANY_CYCLE.refresh_hotel_recoveries(state, int(state.day))
	if new_market_day: SAAS_WATCH.refresh(state, int(state.day))
	var saas_incidents: Array = SAAS_WATCH.available(state, int(state.day))
	var hotel_recoveries: Array = COMPANY_CYCLE.hotel_recovery_available(state, int(state.day))
	# Refreshing the same day's board must not replace previously offered terms.
	# Only a new offer ID receives a newly authored containment scenario.
	var previous_endpoint_offers: Dictionary = {}
	var previous_saas_offers: Dictionary = {}
	for previous_offer in state.get("offers", []):
		if previous_offer is Dictionary and str(previous_offer.get("case_id", "")) in [SAAS_PARTNER.CASE_ID, SAAS_AI.CASE_ID, SAAS_AI_HANDOFF.CASE_ID]:
			previous_saas_offers[str(previous_offer.get("id", ""))] = previous_offer.duplicate(true)
		if previous_offer is Dictionary and ENDPOINT_ENGAGEMENT.containment_case(str(previous_offer.get("case_id", ""))):
			previous_endpoint_offers[str(previous_offer.get("id", ""))] = previous_offer.duplicate(true)
	state.offers = []
	var level := int(company_level().level)
	for selected in CASES.all():
		if str(selected.id) == SAAS_AI.CASE_ID and SAAS_AI.payload(state, int(state.day)).is_empty(): continue
		if str(selected.id) == SAAS_AI_HANDOFF.CASE_ID and SAAS_AI_HANDOFF.payload(state, int(state.day)).is_empty(): continue
		if str(selected.id) == "advanced-saas-watch" and saas_incidents.is_empty(): continue
		if str(selected.id) == BRANCH_HANDOFF.CASE_ID and not BRANCH_HANDOFF.available(state): continue
		if HOTEL_HANDOFF.is_case(str(selected.id)) and hotel_recoveries.is_empty(): continue
		var tier := int(selected.tier)
		var category: String = selected.category
		var required_skills := _case_skill_requirements(selected)
		var required_rank := int(required_skills.get(category,tier))
		var needed_level := int(selected.required_level)
		var target_specs: Array = selected.get("targets", []) if selected.get("targets", []) is Array else []
		var sites := target_specs.size() if not target_specs.is_empty() else (tier if level >= 15 else (mini(tier,2) if level >= 8 else 1))
		var reward := _specialist_reward(int(selected.chapter),int(selected.reward),category) * (1 if not target_specs.is_empty() else sites)
		var chapter_factors: Array[float] = [1.0,1.7,1.25,1.4,1.3,1.5]
		var factor := chapter_factors[clampi(int(selected.chapter),0,chapter_factors.size()-1)]
		if not target_specs.is_empty():
			factor = 0.0
			for spec in target_specs:
				factor += chapter_factors[clampi(int(spec.get("chapter",selected.chapter)),0,chapter_factors.size()-1)]
		var estimated_budget := roundi(90.0 * maxf(1.0,factor) * (1.0 if not target_specs.is_empty() else max(1,sites)))
		if int(selected.get("advanced_work_minutes", 0)) > 0: estimated_budget = int(selected.advanced_work_minutes)
		var supply_requirement: Dictionary = selected.get("supply_requirement",{}).duplicate(true) if selected.get("supply_requirement",{}) is Dictionary else {}
		var supply_cost := int(CUSTOMER_STOCK.product(str(supply_requirement.get("sku",CUSTOMER_STOCK.SKU))).get("unit_cost",CUSTOMER_STOCK.UNIT_COST)) if not supply_requirement.is_empty() else 0
		state.offers.append({"id":"career-%d-%s" % [state.day,selected.id],"case_id":selected.id,"chapter":selected.chapter,"title":selected.title,"client":selected.client,"brief":selected.brief,"service":selected.service,"category":category,"grade":tier,"targets":sites,"target_specs":target_specs.duplicate(true),"reward":reward,"base_reward":reward,"required_credit":0,"required_level":needed_level,"required_rank":required_rank,"required_skills":required_skills,"work_family":str(selected.get("work_family","chapter-"+str(selected.chapter))),"supply_requirement":supply_requirement,"estimated_cost":700+supply_cost,"estimated_budget":estimated_budget,"deadline_text":_clock_text(BUSINESS_START_MINUTE+estimated_budget),"unlocked":_case_skills_met(selected,state.skills) and level>=needed_level,"market_available":false,"market_day":int(state.day),"retired_from_new_offers":bool(selected.get("retired_from_new_offers",false))})
		state.offers[-1].advanced_work_minutes = int(selected.get("advanced_work_minutes", 0))
		if str(selected.id) == SAAS_PARTNER.CASE_ID:
			var previous: Dictionary = previous_saas_offers.get(str(state.offers[-1].id), {})
			var partner_payload: Dictionary = previous.get("saas_partner_payload", {}) if not previous.is_empty() else SAAS_PARTNER.payload(state, int(state.day))
			if not partner_payload.is_empty():
				state.offers[-1].saas_partner_payload = partner_payload.duplicate(true)
				state.offers[-1].title = SAAS_PARTNER.TITLE
				state.offers[-1].brief = SAAS_PARTNER.BRIEF
				state.offers[-1].target_specs = [{"chapter":3,"case_id":SAAS_PARTNER.CASE_ID,"name":"北斗物流・委託先送付の接続"}]
		if str(selected.id) == SAAS_AI.CASE_ID:
			var previous: Dictionary = previous_saas_offers.get(str(state.offers[-1].id), {})
			var ai_payload: Dictionary = previous.get("saas_ai_payload", {}) if not previous.is_empty() else SAAS_AI.payload(state, int(state.day))
			state.offers[-1].saas_ai_payload = ai_payload.duplicate(true)
		if str(selected.id) == SAAS_AI_HANDOFF.CASE_ID:
			var previous_handoff: Dictionary = previous_saas_offers.get(str(state.offers[-1].id), {})
			var handoff_payload: Dictionary = previous_handoff.get("saas_ai_handoff_payload", {}) if not previous_handoff.is_empty() else SAAS_AI_HANDOFF.payload(state, int(state.day))
			state.offers[-1].saas_ai_handoff_payload = handoff_payload.duplicate(true)
			state.offers[-1].brief = SAAS_AI_HANDOFF.brief(handoff_payload)
			state.offers[-1].target_specs = [{"chapter":3,"case_id":SAAS_AI_HANDOFF.CASE_ID,"name":"北斗物流・ミナト配送"}]
		if str(selected.id) == "advanced-saas-watch":
			var incident: Dictionary = saas_incidents[0]
			state.offers[-1].saas_watch_source_contract_id = str(incident.source_contract_id)
			state.offers[-1].saas_watch_payload = incident.payload.duplicate(true)
			state.offers[-1].retired_from_new_offers = false
		if HOTEL_HANDOFF.is_case(str(selected.id)):
			var recovery: Dictionary = hotel_recoveries[0]
			state.offers[-1].hotel_recovery_source_contract_id = str(recovery.source_contract_id)
			state.offers[-1].target_specs = [{"chapter":4,"case_id":HOTEL_HANDOFF.CASE_ID,"name":"予約端末・PC-A","scenario":HOTEL_HANDOFF.scenario(recovery.handoff, int(state.day))}]
			state.offers[-1].retired_from_new_offers = false
		if selected.has("engagement_brief"): state.offers[-1].brief = str(selected.engagement_brief)
		if ENDPOINT_ENGAGEMENT.containment_case(str(selected.id)):
			var generated: Dictionary = state.offers[-1]
			var previous_offer: Dictionary = previous_endpoint_offers.get(str(generated.id), {})
			if not previous_offer.is_empty():
				for field in ["targets", "target_specs", "reward", "base_reward", "estimated_budget", "deadline_text", "brief"]:
					if previous_offer.has(field):
						var value: Variant = previous_offer[field]
						generated[field] = value.duplicate(true) if value is Array or value is Dictionary else value
			else:
				generated.target_specs = ENDPOINT_ENGAGEMENT.containment_specs(selected, sites)
				if not generated.target_specs.is_empty(): generated.brief = str(generated.target_specs[0].scenario.brief)
	var candidate_offers: Array = []
	var carried_cases: Array = []
	var completed_cases: Dictionary = {}
	var canceled_today: Dictionary = {}
	var canceled_today_cases: Dictionary = {}
	var canceled_yesterday: Array[String] = []
	for receipt in state.get("history", []):
		if receipt is Dictionary and str(receipt.get("kind", "")).is_empty():
			var completed_case_id := str(receipt.get("case_id", ""))
			if not completed_case_id.is_empty(): completed_cases[completed_case_id] = true
		elif receipt is Dictionary and str(receipt.get("kind", "")) == "cancellation":
			var canceled_case_id := str(receipt.get("case_id", ""))
			if int(receipt.get("day", -1)) == int(state.day) and not str(receipt.get("id", "")).is_empty():
				canceled_today[str(receipt.id)] = true
				if not canceled_case_id.is_empty(): canceled_today_cases[canceled_case_id] = true
			if int(receipt.get("day", -1)) == int(state.day) - 1 and not canceled_case_id.is_empty() and canceled_case_id not in canceled_yesterday: canceled_yesterday.append(canceled_case_id)
	# Cancellation archives outlive the rolling history, so they remain the
	# source of truth for today's exact-ID block and yesterday's retry priority.
	for archive in state.get("contract_closeouts", {}).values():
		if not archive is Dictionary: continue
		var record: Variant = archive.get("record", {})
		if not record is Dictionary: continue
		var archived_case_id := str(record.get("case_id", archive.get("context", {}).get("contract", {}).get("case_id", "")))
		var archived_id := str(record.get("id", archive.get("id", "")))
		if int(record.get("day", archive.get("day", -1))) == int(state.day) and not archived_id.is_empty():
			canceled_today[archived_id] = true
			if not archived_case_id.is_empty(): canceled_today_cases[archived_case_id] = true
		if int(record.get("day", archive.get("day", -1))) == int(state.day) - 1 and not archived_case_id.is_empty() and archived_case_id not in canceled_yesterday:
			canceled_yesterday.append(archived_case_id)
	for context_id in state.get("contract_contexts", {}):
		var context: Dictionary = state.contract_contexts[context_id]
		var contract: Dictionary = context.get("contract", {})
		if not bool(context.get("completed", false)) and str(context_id) != "career-%d-%s" % [state.day, str(contract.get("case_id", ""))]:
			carried_cases.append(str(contract.get("case_id", "")))
	var recovery_blocks: Array = canceled_today_cases.keys(); recovery_blocks.append_array(carried_cases)
	var recovery_work: Dictionary = COMPANY_CYCLE.recovery_work(state, state.offers, recovery_blocks)
	var recovery_cases: Array = recovery_work.values().map(func(offer): return str(offer.case_id))
	var care_replacement_cases: Dictionary = {}
	var offer_category_by_case: Dictionary = {}
	var fresh_category_counts: Dictionary = {}
	var quoted_case_ids: Dictionary = {}
	for candidate in state.offers:
		var candidate_case_id := str(candidate.get("case_id", ""))
		var candidate_client := str(candidate.get("client", ""))
		var candidate_category := str(candidate.get("category", ""))
		offer_category_by_case[candidate_case_id] = candidate_category
		if state.get("offer_quotes", {}).has(str(candidate.get("id", ""))): quoted_case_ids[candidate_case_id] = true
		var candidate_supply: Variant = candidate.get("supply_requirement", {})
		var special_route: bool = (candidate_supply is Dictionary and not candidate_supply.is_empty()) or candidate_case_id == "endpoint-recovery"
		if bool(candidate.get("unlocked", false)) and not completed_cases.has(candidate_case_id) and not bool(candidate.get("retired_from_new_offers", false)) and not special_route:
			fresh_category_counts[candidate_category] = int(fresh_category_counts.get(candidate_category, 0)) + 1
		if bool(state.get("care_agreements", {}).get(candidate_client, {}).get("active", false)) and not candidate_case_id.is_empty():
			care_replacement_cases[candidate_case_id] = true
	var existing_leads: Array = state.get("market_leads", []) if int(state.get("market_day", -1)) == int(state.day) else []
	var partner_pending := candidate_payload_available(state.offers)
	var ai_pending: bool = state.offers.any(func(offer): return str(offer.get("case_id", "")) == SAAS_AI.CASE_ID and SAAS_AI.matches_available(state, offer.get("saas_ai_payload", {}), int(state.day)))
	var ai_handoff_pending: bool = state.offers.any(func(offer): return str(offer.get("case_id", "")) == SAAS_AI_HANDOFF.CASE_ID and SAAS_AI_HANDOFF.matches_available(state, offer.get("saas_ai_handoff_payload", {}), int(state.day)))
	if not existing_leads.is_empty(): existing_leads = existing_leads.filter(func(raw_id): return not canceled_today_cases.has(str(raw_id)))
	if not existing_leads.is_empty():
		existing_leads = existing_leads.filter(func(raw_id):
			var lead_id := str(raw_id)
			var lead_category := str(offer_category_by_case.get(lead_id, ""))
			return (lead_id == SAAS_PARTNER.CASE_ID and partner_pending) or (lead_id == SAAS_AI.CASE_ID and ai_pending) or (lead_id == SAAS_AI_HANDOFF.CASE_ID and ai_handoff_pending) or not completed_cases.has(lead_id) or care_replacement_cases.has(lead_id) or quoted_case_ids.has(lead_id) or int(fresh_category_counts.get(lead_category, 0)) == 0)
	for candidate in state.offers:
		var case_id := str(candidate.get("case_id", ""))
		var retired := bool(candidate.get("retired_from_new_offers", false))
		var care_replacement := care_replacement_cases.has(case_id)
		var completed_allowed := (case_id == SAAS_PARTNER.CASE_ID and partner_pending) or (case_id == SAAS_AI.CASE_ID and ai_pending) or (case_id == SAAS_AI_HANDOFF.CASE_ID and ai_handoff_pending) or not completed_cases.has(case_id) or care_replacement or quoted_case_ids.has(case_id) or case_id in recovery_cases or int(fresh_category_counts.get(str(candidate.get("category", "")), 0)) == 0
		if candidate.has("saas_partner_payload") and not SAAS_PARTNER.matches_available(state, candidate.saas_partner_payload, int(state.day)): completed_allowed = false
		if case_id == SAAS_AI.CASE_ID and not SAAS_AI.matches_available(state, candidate.get("saas_ai_payload", {}), int(state.day)): completed_allowed = false
		if case_id == SAAS_AI_HANDOFF.CASE_ID and not SAAS_AI_HANDOFF.matches_available(state, candidate.get("saas_ai_handoff_payload", {}), int(state.day)): completed_allowed = false
		# Preserve a lead already shown this day, including a quoted/awaiting
		# retired case. Retirement only affects fresh market generation.
		if bool(candidate.get("unlocked", false)) and not canceled_today.has(str(candidate.get("id", ""))) and case_id not in carried_cases and completed_allowed and (not retired or case_id in existing_leads): candidate_offers.append(candidate)
	var recent_case_ids: Array = []
	for receipt in state.get("history", []):
		if receipt is Dictionary and int(receipt.get("day", -1)) == int(state.day) - 1 and str(receipt.get("kind", "")).is_empty():
			var recent_case_id := str(receipt.get("case_id", ""))
			if not recent_case_id.is_empty() and recent_case_id not in recent_case_ids: recent_case_ids.append(recent_case_id)
	var priority_ids: Array = []
	# Reserve one ordinary demand slot on a fresh board. This keeps the first
	# hands-on engagement visible without expanding daily category limits.
	if existing_leads.is_empty() and not completed_cases.has("advanced-portal") and candidate_offers.any(func(candidate): return str(candidate.get("case_id", "")) == "advanced-portal"):
		existing_leads.append("advanced-portal")
	if not previous_skills.is_empty():
		var promoted: Array = candidate_offers.filter(func(candidate): return not _case_skills_met(candidate,previous_skills))
		promoted.sort_custom(func(a,b):
			var af := str(a.case_id).begins_with("firm-"); var bf := str(b.case_id).begins_with("firm-")
			if af != bf: return af
			if a.required_skills.size() != b.required_skills.size(): return a.required_skills.size() > b.required_skills.size()
			return str(a.case_id) < str(b.case_id))
		for candidate in promoted: priority_ids.append(str(candidate.case_id))
	for canceled_case_id in canceled_yesterday:
		if canceled_case_id not in priority_ids: priority_ids.append(canceled_case_id)
	state.market_leads=MARKET_DEMAND.select_by_category(candidate_offers,int(state.day),recent_case_ids,existing_leads,state.skills,priority_ids)
	# Keep progression moving when demand selection is saturated by a special
	# route (hardware, endpoint recovery, or advanced work). Prefer a fresh
	# ordinary single-service case; when that category has no fresh ordinary
	# case left, rotate a completed ordinary case back into the board. Existing
	# same-day leads remain intact so quoted choices do not disappear.
	for category in ["advisory", "operations", "response"]:
		var ordinary_lead := false
		for lead_id in state.market_leads:
			for candidate in candidate_offers:
				if str(candidate.get("case_id", "")) != str(lead_id) or str(candidate.get("category", "")) != category: continue
				var candidate_supply: Variant = candidate.get("supply_requirement", {})
				var candidate_case := str(candidate.get("case_id", ""))
				if (not candidate_supply is Dictionary or candidate_supply.is_empty()) and candidate_case != "endpoint-recovery" and not candidate_case.begins_with("advanced-") and not candidate_case.begins_with("composite-"):
					ordinary_lead = true
					break
			if ordinary_lead: break
		if ordinary_lead: continue
		var category_lead_count := 0
		for lead_id in state.market_leads:
			for candidate in candidate_offers:
				if str(candidate.get("case_id", "")) == str(lead_id) and str(candidate.get("category", "")) == category:
					category_lead_count += 1
					break
		if category_lead_count >= [2, 3, 4][MARKET_DEMAND.phase(int(state.day), ["advisory", "operations", "response"].find(category))]: continue
		var ordinary_candidates: Array = candidate_offers.filter(func(candidate):
			var candidate_supply: Variant = candidate.get("supply_requirement", {})
			var candidate_case := str(candidate.get("case_id", ""))
			return str(candidate.get("category", "")) == category and (not candidate_supply is Dictionary or candidate_supply.is_empty()) and candidate_case != "endpoint-recovery" and not candidate_case.begins_with("advanced-") and not candidate_case.begins_with("composite-")
		)
		ordinary_candidates.sort_custom(func(a,b):
			var a_done := completed_cases.has(str(a.get("case_id", "")))
			var b_done := completed_cases.has(str(b.get("case_id", "")))
			if a_done != b_done: return not a_done
			return int(a.get("reward", 0)) > int(b.get("reward", 0))
		)
		for fallback in ordinary_candidates:
			var fallback_id := str(fallback.get("case_id", ""))
			if fallback_id not in state.market_leads:
				state.market_leads.append(fallback_id)
				break
	var protected_leads: Array = quoted_case_ids.keys()
	protected_leads.append_array(carried_cases)
	var relationship_priorities: Array = COMPANY_CYCLE.priority_case_ids(self); relationship_priorities.append_array(recovery_cases)
	# A successfully supported SaaS customer brings a more detailed access
	# investigation from the next business day. Read the saved delivery;
	# never rewrite its observations or upgrade an already-issued contract.
	if not completed_cases.has("advanced-saas-sessions"):
		for delivery in state.get("history", []):
			if not delivery is Dictionary or not str(delivery.get("kind", "")).is_empty(): continue
			if str(delivery.get("case_id", "")) != "advanced-saas-watch" or int(delivery.get("day", 0)) >= int(state.day): continue
			var source_checks: Array = delivery.get("checks", [])
			if str(delivery.get("id", "")) in state.get("completed_ids", []) and str(delivery.get("rating", "")) == "on_time" and int(delivery.get("satisfaction_after", 0)) >= 40 and not source_checks.is_empty() and source_checks.all(func(row): return row is Dictionary and bool(row.get("passed", false))):
				relationship_priorities.push_front("advanced-saas-sessions")
				break
	if not hotel_recoveries.is_empty(): relationship_priorities.push_front(HOTEL_HANDOFF.CASE_ID)
	if not saas_incidents.is_empty(): relationship_priorities.push_front("advanced-saas-watch")
	if partner_pending: relationship_priorities.push_front(SAAS_PARTNER.CASE_ID)
	if ai_pending: relationship_priorities.push_front(SAAS_AI.CASE_ID)
	if ai_handoff_pending: relationship_priorities.push_front(SAAS_AI_HANDOFF.CASE_ID)
	state.market_leads = MARKET_DEMAND.prioritize_relationships(candidate_offers, state.market_leads, relationship_priorities, protected_leads, int(state.day))
	state.market_day=int(state.day)
	var lead_set: Dictionary = {}
	for lead in state.get("market_leads", []): lead_set[str(lead)] = true
	for offer in state.offers:
		offer.market_day = int(state.market_day)
		offer.market_available = bool(offer.get("unlocked", false)) and lead_set.has(str(offer.get("case_id", offer.id)))
	state.offers.sort_custom(func(a,b):
		if a.market_available != b.market_available: return a.market_available
		if a.unlocked != b.unlocked: return a.unlocked
		if a.required_level != b.required_level: return a.required_level < b.required_level
		return a.case_id < b.case_id)
	# Quotes belong to the day's offers. Accepted prices live in the contract.
	var current_ids: Array = state.offers.map(func(offer): return str(offer.id))
	for quote_id in state.offer_quotes.keys():
		if quote_id not in current_ids: state.offer_quotes.erase(quote_id)

func candidate_payload_available(offers: Array) -> bool:
	for offer in offers:
		if offer is Dictionary and str(offer.get("case_id", "")) == SAAS_PARTNER.CASE_ID and SAAS_PARTNER.matches_available(state, offer.get("saas_partner_payload", {}), int(state.day)): return true
	return false

func market_summary() -> Dictionary:
	var result: Dictionary = {}
	for offer in state.get("offers", []):
		var category := str(offer.get("category", "advisory"))
		if not result.has(category): result[category] = {"phase":str(_market_demand(offer).label),"count":0,"available":0}
		result[category].count = int(result[category].count) + 1
		if bool(offer.get("market_available", false)): result[category].available = int(result[category].available) + 1
	return result

func company_cycle_view() -> Dictionary:
	var cycle: Dictionary = COMPANY_CYCLE.view(self)
	var opportunities: Array = cycle.get("leads", []).duplicate(true)
	var partner_lead: Dictionary = SAAS_PARTNER.lead(self)
	if not partner_lead.is_empty():
		opportunities = opportunities.filter(func(item): return str(item.get("client", "")) != SAAS_PARTNER.CLIENT)
		opportunities.append(partner_lead)
	var ai_lead: Dictionary = SAAS_AI.lead(self)
	if not ai_lead.is_empty():
		opportunities = opportunities.filter(func(item): return str(item.get("client", "")) != SAAS_AI.CLIENT)
		opportunities.append(ai_lead)
	var ai_handoff_lead: Dictionary = SAAS_AI_HANDOFF.lead(self)
	if not ai_handoff_lead.is_empty():
		opportunities = opportunities.filter(func(item): return str(item.get("client", "")) != SAAS_AI_HANDOFF.CLIENT)
		opportunities.append(ai_handoff_lead)
	for lead in opportunities:
		if str(lead.get("case_id", "")) == BRANCH_HANDOFF.CASE_ID and str(lead.get("status", "")) not in ["paused", "fulfilled"] and not BRANCH_HANDOFF.available(state):
			lead.status = "locked"; lead.handoff_unavailable = true
			lead.locked_reason = "引継ぎ元の受注表または納品評価の保存記録がありません。代用データでは受注できません。"
			continue
		# Ready is eligibility; an unoffered consultation waits for the ordinary
		# daily market slot instead of pretending it can already be accepted.
		if bool(state.get("career_mode", false)) and str(lead.get("status", "")) == "ready" and not bool(lead.get("market_available", false)):
			lead.status = "locked"
			lead.locked_reason = "今日の相談枠は提示済みです。翌日の営業で確認できます。"
	var ledger := day_preview()
	var billing := billing_summary()
	cycle.opportunities = opportunities
	cycle.goals = COMPANY_ROADMAP.goals(state)
	var unpaid_care_cost := int(ledger.get("care_cost", 0)) if int(state.get("retainer_settled_day", -1)) != int(state.get("day", 1)) else 0
	cycle.economy = {"cash":int(state.get("cash",0)),"due_next_day":int(billing.get("due_next_day",0)),"draft_total":int(billing.get("draft_total",0)),"receivable_total":int(billing.get("receivable_total",0)),"care_net":int(ledger.get("care_net",0)),"day_cash_after":int(ledger.get("cash_after",state.get("cash",0))),"payroll_outstanding":int(ledger.get("payroll_outstanding",0)),"payroll_arrears_after":int(ledger.get("arrears",0)),"settlement_costs":unpaid_care_cost+int(ledger.get("paid_wages",0))}
	return cycle

func offer_operations_preview(offer: Dictionary) -> Dictionary:
	var requirement: Variant = offer.get("supply_requirement", {}) if offer is Dictionary else {}
	var sku := str(requirement.get("sku", "")) if requirement is Dictionary else ""
	var own_required := maxi(0,int(requirement.get("quantity",1))) if requirement is Dictionary and not requirement.is_empty() and not sku.is_empty() else 0
	var stock := customer_stock_summary(sku) if not sku.is_empty() else {"available":0,"inbound":0,"reserved":0}
	var available := int(stock.get("available",0)); var inbound := int(stock.get("inbound",0)); var reserved := int(stock.get("reserved",0))
	# The summary already includes every accepted contract.  Add a preview's
	# requirement only when this offer is not in that accepted portfolio, so a
	# second preview cannot promise the same units twice.
	var offer_id := str(offer.get("id", "")) if offer is Dictionary else ""
	var already_accepted := bool(state.get("accepted",false)) and str(state.get("current_contract_id", "")) == offer_id and not current_done()
	if not already_accepted and state.get("contract_contexts",{}).has(offer_id):
		var context: Variant = state.contract_contexts.get(offer_id,{})
		already_accepted = context is Dictionary and bool(context.get("accepted",true)) and not bool(context.get("completed",false))
	if already_accepted: own_required = 0
	var portfolio_required := int(stock.get("required",0)) + own_required
	var shortage := maxi(0,portfolio_required-available-inbound)
	var unit_cost := int(CUSTOMER_STOCK.product(sku).get("unit_cost",0)) if not sku.is_empty() and CUSTOMER_STOCK.known_sku(sku) else 0
	var staffing := staff_summary()
	var capacity := contract_capacity(); var open_contracts := _open_contract_count()
	return {"sku":sku,"required":portfolio_required,"own_required":own_required,"portfolio_required":portfolio_required,"available":available,"inbound":inbound,"reserved":reserved,"shortage":shortage,"purchase_cost":shortage*unit_cost,"cash_after_purchase":int(state.get("cash",0))-shortage*unit_cost,"open_contracts":open_contracts,"contract_capacity":capacity,"free_contract_slots":maxi(0,capacity-open_contracts),"staff_count":team_members().size(),"extra_staff_count":int(staffing.get("count",0)),"staff_capacity":int(staffing.get("capacity",0)),"workforce_capacity":2+int(staffing.get("capacity",0)),"payroll_due":int(staffing.get("due",0))}

func start_free_career() -> bool:
	if state.get("career_mode",false): return false
	if state.strategy == "" or (state.accepted and not current_done()): return false
	var previous_state: Dictionary = state.duplicate(true)
	var previous_assignments: Dictionary = _assignments.duplicate(true)
	if current_done():
		var closing_preview := DAY_LEDGER.preview(self)
		_apply_retainer(); _settle_staff_payroll(); DAY_LEDGER.settle(self, closing_preview)
		state.day += 1; state.clock_minutes = BUSINESS_START_MINUTE
	state.career_mode = true; state.game_complete = false; state.awaiting_contract = true; state.staff_payroll.enabled = true
	state.accepted = false; state.inspected = false; state.current_contract_id = ""; state.contract = {}; state.targets = []; state.target_index = 0
	state.checks = []; state.validated_revision = -1; _retain_maintenance_assignments()
	_make_offers()
	if not save_game(): state = previous_state; _assignments = previous_assignments; return false
	changed.emit(); return true

func _scenario(index: int = -1) -> Dictionary:
	var target_index := int(state.get("target_index", 0)) if index < 0 else index
	var targets: Array = state.get("targets", [])
	var case_id := ""
	if target_index >= 0 and target_index < targets.size() and targets[target_index] is Dictionary:
		if targets[target_index].get("scenario", null) is Dictionary: return targets[target_index].scenario.duplicate(true)
		case_id = str(targets[target_index].get("case_id", ""))
	if case_id.is_empty(): case_id = str(state.get("contract",{}).get("case_id",""))
	return CASES.by_id(case_id) if not case_id.is_empty() else {}

func _case_skill_requirements(item: Dictionary) -> Dictionary:
	if item.get("required_skills", {}) is Dictionary and not item.get("required_skills", {}).is_empty():
		return item.required_skills.duplicate(true)
	return {str(item.get("category","advisory")):int(item.get("required_rank",item.get("tier",1)))}

func _case_skills_met(item: Dictionary, skills: Dictionary) -> bool:
	var requirements := _case_skill_requirements(item)
	for skill_id in requirements:
		if int(skills.get(skill_id,0)) < int(requirements[skill_id]): return false
	return true

func skill_case_unlocks(id: String) -> Array:
	var raised: Dictionary = state.skills.duplicate(true)
	raised[id] = mini(10,int(raised.get(id,0))+1)
	var cases: Array = []
	for item in CASES.all():
		if bool(item.get("retired_from_new_offers", false)): continue
		if int(item.required_level) <= int(company_level().level) and _case_skills_met(item,raised) and not _case_skills_met(item,state.skills):
			cases.append(str(item.title))
	cases.sort()
	return cases

func contract_eligibility(offer: Dictionary) -> Array:
	var reasons: Array = []
	if bool(offer.get("unlocked", false)) and not bool(offer.get("market_available", true)):
		reasons.append(UI_COPY.copy("market_not_requested"))
		return reasons
	var level := int(company_level().level)
	var required_level := int(offer.get("required_level", 1))
	if level < required_level: reasons.append("会社Lv.%dが必要（現在Lv.%d）" % [required_level,level])
	var requirements := _case_skill_requirements(offer)
	for skill_id in requirements:
		var rank := int(state.skills.get(skill_id,0))
		if rank < int(requirements[skill_id]):
			reasons.append(UI_COPY.copy("firm_skill_requirement") % [UI_COPY.copy("market_"+str(skill_id)),int(requirements[skill_id]),rank])
	if reasons.is_empty(): reasons.append("受注可能")
	return reasons

func care_case_reason(offer: Dictionary) -> String:
	return CARE_SUPPORT.reason(offer)

func care_conversion_offer() -> Dictionary:
	return CARE_SUPPORT.conversion(self)

func convert_current_care_to_standard() -> bool:
	return CARE_SUPPORT.convert(self)

func choose_contract(id: String) -> bool:
	if not state.career_mode or state.game_complete or (not state.awaiting_contract and not state.accepted): return false
	if state.get("contract_closeouts", {}).has(id): return false
	if _open_contract_count() >= contract_capacity(): return false
	var previous_state: Dictionary = state.duplicate(true)
	var previous_assignments: Dictionary = _assignments.duplicate(true)
	var previous_machine = _machine; var previous_machine_key := _machine_key
	_sync_contract_context()
	for offer in state.offers:
		if offer.id == id and offer.unlocked and _case_skills_met(offer,state.skills) and bool(offer.get("market_available", true)) and int(state.credit) >= int(offer.required_credit) and int(company_level().level) >= int(offer.get("required_level",1)):
			if str(offer.get("case_id", "")) == SAAS_AI.CASE_ID and not SAAS_AI.matches_available(state, offer.get("saas_ai_payload", {}), int(state.day)):
				state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
			if str(offer.get("case_id", "")) == SAAS_AI_HANDOFF.CASE_ID and not SAAS_AI_HANDOFF.matches_available(state, offer.get("saas_ai_handoff_payload", {}), int(state.day)):
				state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
			if offer.has("saas_partner_payload") and not SAAS_PARTNER.matches_available(state, offer.saas_partner_payload, int(state.day)):
				state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
			var handoff_scenario: Dictionary = {}
			if HOTEL_HANDOFF.is_case(str(offer.get("case_id", ""))):
				var recovery_source := str(offer.get("hotel_recovery_source_contract_id", ""))
				var recovery: Dictionary = state.get("company_cycle", {}).get("hotel_recoveries", {}).get(recovery_source, {})
				handoff_scenario = HOTEL_HANDOFF.scenario(recovery.get("handoff", {}), int(state.day))
				if handoff_scenario.is_empty() or str(recovery.get("status", "")) != "pending":
					state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key
					return false
			if str(offer.get("case_id", "")) == BRANCH_HANDOFF.CASE_ID:
				handoff_scenario = BRANCH_HANDOFF.scenario(state, CASES.by_id(BRANCH_HANDOFF.CASE_ID))
				if handoff_scenario.is_empty():
					state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key
					return false
			if id in state.get("completed_ids",[]): return false
			if state.contract_contexts.has(id): return false
			for context_id in state.contract_contexts.keys():
				var existing_context: Dictionary = state.contract_contexts[context_id]
				if not bool(existing_context.get("completed",false)) and str(existing_context.get("contract",{}).get("client","")) == str(offer.get("client","")) and str(existing_context.get("contract",{}).get("case_id",existing_context.get("contract",{}).get("id",""))) == str(offer.get("case_id",offer.get("id",""))): return false
			var quote := contract_quote(offer)
			var plan_id := str(quote.selected_plan)
			if plan_id == "care" and not care_case_reason(offer).is_empty():
				state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key
				return false
			var quoted_fee := int(quote.quoted_fee)
			var duplicate_decline := false
			for decision in state.quote_decisions:
				if str(decision.get("offer_id", "")) == id and str(decision.get("plan", "")) == plan_id and int(decision.get("amount", -1)) == quoted_fee and str(decision.get("decision", "")) == "declined": duplicate_decline = true; break
			if not bool(quote.affordable):
				if not duplicate_decline:
					state.quote_decisions.append({"offer_id":id,"plan":plan_id,"amount":quoted_fee,"decision":"declined","reason":str(quote.reason),"day":int(state.day)})
					if state.quote_decisions.size() > 100: state.quote_decisions = state.quote_decisions.slice(-100)
					if not save_game(): state = previous_state; _assignments = previous_assignments
				return false
			if plan_id == "care" and not _agree_care(str(offer.get("client", ""))): state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
			if HOTEL_HANDOFF.is_case(str(offer.get("case_id", ""))) and not COMPANY_CYCLE.mark_hotel_recovery_working(state, str(offer.get("hotel_recovery_source_contract_id", "")), id, int(state.day)):
				state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
			state.chapter = int(offer.chapter); state.current_contract_id = id; state.awaiting_contract = false
			if str(offer.get("case_id", "")) == "advanced-saas-watch" and not SAAS_WATCH.accept(state, str(offer.get("saas_watch_source_contract_id", "")), id):
				state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
			state.contract = offer.duplicate(true); state.contract.agreed_fee = quoted_fee; state.contract.agreed_budget = float(quote.budget); state.contract.reference_fee = int(quote.reference_fee); state.contract.budget_limit = int(quote.budget_limit); state.contract.market_label = str(quote.market_label); state.contract.price_reaction = str(quote.price_reaction); state.targets = []; state.target_index = 0
			state.contract.billing_version = 1; state.contract.payment_days = int(BILLING.terms(offer).days)
			var specs: Array = offer.get("target_specs", [])
			if specs.is_empty():
				for i in int(offer.targets): specs.append({"chapter":state.chapter,"case_id":offer.case_id,"name":"拠点%d" % (i+1)})
			for spec in specs:
				var target_chapter := int(spec.get("chapter",state.chapter))
				state.targets.append({"chapter":target_chapter,"case_id":str(spec.get("case_id",offer.case_id)),"name":str(spec.get("name","拠点")),"config":_default_fields(target_chapter),"inspected":false,"checks":[],"revision":0,"validated_revision":-1,"baseline_recorded":false,"baseline_locked":false,"baseline_config":"","baseline_sha":"","baseline_report":"","baseline_report_content":""})
				if spec.get("scenario", null) is Dictionary: state.targets[-1].scenario = spec.scenario.duplicate(true)
			var selected_case_id := str(offer.get("case_id", ""))
			if not handoff_scenario.is_empty():
				state.targets[0].scenario = handoff_scenario
				if handoff_scenario.has("handoff"): state.contract.handoff = handoff_scenario.handoff.duplicate(true)
			state.advanced = _advanced_engine(selected_case_id).create(selected_case_id) if _advanced_case_id(selected_case_id) else {}
			if offer.has("saas_partner_payload"):
				state.advanced = _advanced_engine(selected_case_id).create_partner_followup(offer.saas_partner_payload)
				if state.advanced.is_empty():
					state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
			if selected_case_id == SAAS_AI.CASE_ID:
				state.advanced = _advanced_engine(selected_case_id).create_followup(offer.get("saas_ai_payload", {}))
				if state.advanced.is_empty():
					state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
			if selected_case_id == SAAS_AI_HANDOFF.CASE_ID:
				state.advanced = _advanced_engine(selected_case_id).create_followup(offer.get("saas_ai_handoff_payload", {}))
				if state.advanced.is_empty():
					state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
			if selected_case_id == "advanced-saas-watch":
				state.advanced = _advanced_engine(selected_case_id).create_followup(offer.get("saas_watch_payload", {}))
				if state.advanced.is_empty():
					state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
			if not state.advanced.is_empty(): state.targets[0].advanced = state.advanced.duplicate(true)
			_prepare_linked_identity_contract()
			_prepare_linked_business_contract()
			# Only the new frozen hotel scope owns a front-desk dataset. Old offers
			# and loaded contracts have no marker and never acquire a new folio.
			for index in state.targets.size():
				var hotel_scenario: Dictionary = state.targets[index].get("scenario", {})
				if int(hotel_scenario.get("hotel_workflow_version", 0)) not in [1, 2]: continue
				var hotel_vm = SERVICE_MONITOR_VM.new()
				hotel_vm.setup(4, {}, hotel_scenario)
				state.vm_states[_vm_key(index)] = hotel_vm.export_state()
			state.accepted = true; state.inspected = false; state.diagnostics_required = true; state.config = _default_fields(state.chapter); state.revision += 1; state.checks = []; state.validated_revision = -1
			state.contract_plan = plan_id
			state.work = {"minutes":0.0,"started_at":int(state.clock_minutes),"started_day":int(state.day),"restarts_failed":0,"resets":0,"incident_cost":0,"plan":state.contract_plan}
			for field in ["baseline_recorded","baseline_locked","baseline_config","baseline_sha","baseline_report","baseline_report_content"]:
				state[field] = false if field in ["baseline_recorded","baseline_locked"] else ""
			state.restore_preview = 0; state.last_receipt = {}
			_machine = null; _machine_key = ""
			_sync_contract_context()
			state.quote_decisions.append({"offer_id":id,"plan":plan_id,"amount":quoted_fee,"decision":"accepted","reference_fee":int(quote.reference_fee),"budget_limit":int(quote.budget_limit),"day":int(state.day)})
			if state.quote_decisions.size() > 100: state.quote_decisions = state.quote_decisions.slice(-100)
			if not save_game(): state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
			changed.emit(); return true
	return false

func _sync_target() -> void:
	if state.get("targets", []).is_empty() or state.get("awaiting_contract", false): return
	var target: Dictionary = state.targets[int(state.target_index)].duplicate(true)
	target["config"] = state.config.duplicate(true); target["inspected"] = state.inspected; target["checks"] = state.checks.duplicate(true); target["revision"] = state.revision; target["validated_revision"] = state.validated_revision; target["advanced"] = state.get("advanced", {}).duplicate(true)
	for key in ["baseline_recorded","baseline_locked","baseline_config","baseline_sha","baseline_report","baseline_report_content"]:
		if not target.has(key): target[key] = false if key in ["baseline_recorded","baseline_locked"] else ""
	state.targets[int(state.target_index)] = target

func select_target(index: int) -> bool:
	if index < 0 or index >= state.get("targets", []).size() or current_done(): return false
	var previous_state := state.duplicate(true); var previous_assignments := _assignments.duplicate(true); var previous_machine = _machine; var previous_key := _machine_key
	_sync_target()
	state.target_index = index
	var target: Dictionary = state.targets[index]
	if target.has("chapter"): state.chapter = int(target.chapter)
	for key in ["config", "inspected", "checks", "revision", "validated_revision", "advanced", "baseline_recorded", "baseline_locked", "baseline_config", "baseline_sha", "baseline_report", "baseline_report_content"]:
		if not target.has(key): target[key] = false if key in ["baseline_recorded","baseline_locked"] else ([] if key == "checks" else ({} if key in ["config","advanced"] else (0 if key == "revision" else (-1 if key == "validated_revision" else ""))))
		state[key] = target[key].duplicate(true) if target[key] is Dictionary or target[key] is Array else target[key]
	if not save_game(): state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_key; return false
	changed.emit(); return true

func lab_snapshot() -> Array:
	return _vm().snapshot()

func _delivery_results() -> Array:
	# Preserve only measurements already made. Receipt rendering must never evaluate
	# a live machine or invent an earlier observation for an older save.
	var results: Array = []
	for index in maxi(1, state.get("targets", []).size()):
		var target: Dictionary = state.targets[index] if index < state.get("targets", []).size() else {}
		var current := index == int(state.get("target_index", 0))
		var machine_state: Dictionary = _machine.export_state() if current and _machine != null else state.get("vm_states", {}).get(_vm_key(index), {})
		var scenario: Dictionary = machine_state.get("scenario", {})
		var probes: Array = []
		for probe in scenario.get("probes", []) if not scenario.is_empty() else machine_state.get("probes", []):
			if not bool(probe.get("recorded", false)): continue
			var saved: Dictionary = {}
			for field in ["id", "label", "command", "recorded", "passed", "result", "initial_result"]:
				if probe.has(field): saved[field] = probe[field]
			probes.append(saved)
		results.append({"target":str(target.get("name", "")), "host":str(machine_state.get("host", "")), "checks":(state.get("checks", []) if current else target.get("checks", [])).duplicate(true), "probes":probes})
	return results

func _hotel_workflow_outcome() -> Dictionary:
	var sites: Array = []
	for index in state.get("targets", []).size():
		var key := _vm_key(index)
		var saved: Dictionary = _machine.state if _machine != null and _machine_key == key else state.get("vm_states", {}).get(key, {})
		var outcome: Dictionary = HOTEL_FRONTDESK.outcome(saved)
		if outcome.is_empty(): continue
		outcome.target = str(state.targets[index].get("name", ""))
		sites.append(outcome)
	return {"version":1,"sites":sites} if not sites.is_empty() else {}

func deliver() -> bool:
	if not can_deliver(): return false
	if state.get("contract", {}).has("maintenance_incident_id"): return CARE.finish_ticket(self)
	var previous_state: Dictionary = state.duplicate(true)
	var previous_assignments: Dictionary = _assignments.duplicate(true)
	var id: String = String(state.current_contract_id) if state.career_mode else String(mission().get("id", ""))
	if id in state.completed_ids: return false
	state.completed_ids.append(id)
	if state.get("career_mode", false): state.contracts_completed = int(state.get("contracts_completed",0)) + 1
	var status := work_status()
	var fee: int = int(status.estimated_fee)
	var bonus := 0
	if status.quality == "on_time": bonus = roundi(fee * 0.1)
	elif status.quality == "late": fee = roundi(fee * maxf(0.8, 1.0 - minf(0.2, float(status.get("elapsed_minutes",status.minutes) - status.budget) / maxf(status.budget, 1.0) * 0.2)))
	var review := case_review()
	var baseline_bonus := int(review.get("bonus", 0))
	bonus += baseline_bonus
	var material_cost := int(status.get("material_cost",0))
	var invoiced := bool(state.get("career_mode", false)) and int(state.contract.get("billing_version", 0)) == 1
	var net: int = fee + bonus + (material_cost if invoiced else 0) - int(status.costs)
	var client: String = str(mission().get("client", ""))
	var relation: Dictionary = state.customer_relations.get(client, {"satisfaction":70,"completed_count":0,"last_quality":"","last_day":0})
	var satisfaction_before := clampi(int(relation.get("satisfaction",70)), 0, 100)
	var quality_satisfaction_delta := 5 if status.quality == "on_time" else (-8 if status.quality == "rework" else -15)
	var reference_fee := int(state.contract.get("reference_fee", status.estimated_fee)) if state.get("contract", {}) is Dictionary else int(status.estimated_fee)
	var agreed_fee := int(state.contract.get("agreed_fee", status.estimated_fee)) if state.get("contract", {}) is Dictionary else int(status.estimated_fee)
	var price_satisfaction_delta := 3 if agreed_fee < roundi(reference_fee * 0.9) else (-3 if agreed_fee > roundi(reference_fee * 1.1) else 0)
	var endpoint_impact: Dictionary = state.work.get("endpoint_impact", {})
	var endpoint_satisfaction_delta := ENDPOINT_ENGAGEMENT.satisfaction_delta(endpoint_impact)
	var endpoint_containment := endpoint_impact.values().any(func(item): return item is Dictionary and item.has("uncontained_minutes"))
	var saas_outcome := _saas_outcome()
	var saas_satisfaction_delta := -mini(9, saas_outcome.get("egress", {}).get("exported_rows", []).size())
	var saas_business_satisfaction_delta := 0
	for job in saas_outcome.get("session_case", {}).get("business", {}).get("jobs", []):
		if int(job.get("loss_amount", 0)) > 0: saas_business_satisfaction_delta -= 3
	if str(saas_outcome.get("model_version", "")) == SAAS_AI.MODEL and int(saas_outcome.get("ai_preflight", {}).get("business", {}).get("loss_cost", 0)) > 0: saas_business_satisfaction_delta -= 3
	if str(saas_outcome.get("model_version", "")) == SAAS_AI_HANDOFF.MODEL and int(saas_outcome.get("handoff", {}).get("business", {}).get("loss_cost", 0)) > 0: saas_business_satisfaction_delta -= 3
	var satisfaction_delta := quality_satisfaction_delta + price_satisfaction_delta + endpoint_satisfaction_delta + saas_satisfaction_delta + saas_business_satisfaction_delta
	relation.satisfaction = clampi(satisfaction_before + satisfaction_delta, 0, 100)
	relation.completed_count = int(relation.get("completed_count",0)) + 1
	relation.last_quality = str(status.quality); relation.last_day = int(state.day)
	state.customer_relations[client] = relation
	if int(relation.satisfaction) < 40: _suspend_care(client)
	elif state.contract_plan == "care": _activate_care(client)
	var captured_targets := _capture_maintenance_targets(client) if state.contract_plan == "care" else []
	if state.contract_plan == "care" and captured_targets.is_empty():
		state = previous_state; _assignments = previous_assignments
		return false
	if state.contract_plan == "care" and not captured_targets.is_empty():
		var agreement_for_targets: Dictionary = state.care_agreements.get(client, {})
		agreement_for_targets.erase("maintenance_legacy")
		agreement_for_targets.next_incident_day = CARE._next_day(self, client)
		state.care_agreements[client] = agreement_for_targets
	var credit_before := int(state.credit)
	var level_before := int(company_level().level)
	var delivery_cash := -int(status.costs) + material_cost if invoiced else net + material_cost
	state.cash = int(state.cash) + delivery_cash
	state.profit = int(state.profit) + net
	_update_growth()
	var renewal_outcome := "none"
	if state.care_agreements.has(client): renewal_outcome = "active" if bool(state.care_agreements[client].get("active",false)) else "suspended"
	state.last_receipt = {"day":int(state.day),"client":mission().client,"title":mission().title,"fee":fee,"bonus":bonus,"baseline_bonus":baseline_bonus,"quality_score":int(review.get("score",0)),"grade":str(review.get("grade","C")),"baseline_sites":int(review.get("recorded_sites",0)),"baseline_total_sites":int(review.get("total_sites",1)),"cost":int(status.costs),"material_cost":material_cost,"material_billable":invoiced and material_cost > 0,"hardware_serial":str(_customer_hardware().get("serial","")),"net":net,"minutes":status.minutes,"elapsed_minutes":status.get("elapsed_minutes",status.minutes),"budget":status.budget,"rating":status.quality,"credit_gain":int(state.credit)-credit_before,"credit_before":credit_before,"credit_after":state.credit,"checks":state.checks.duplicate(true),"plan":state.contract_plan,"level_before":level_before,"level_after":int(company_level().level),"xp_gain":maxi(net,0),"satisfaction_before":satisfaction_before,"satisfaction_after":int(relation.satisfaction),"renewal_outcome":renewal_outcome,"price_satisfaction_delta":price_satisfaction_delta,"quality_satisfaction_delta":quality_satisfaction_delta,"agreed_fee":agreed_fee,"reference_fee":reference_fee}
	state.last_receipt.case_id = str(state.contract.get("case_id", ""))
	if not saas_outcome.is_empty():
		state.last_receipt.saas_outcome = saas_outcome.duplicate(true)
		state.last_receipt.saas_satisfaction_delta = saas_satisfaction_delta
		if saas_outcome.get("session_case", {}).has("business") or saas_outcome.get("ai_preflight", {}).has("business") or saas_outcome.get("handoff", {}).has("business"): state.last_receipt.saas_business_satisfaction_delta = saas_business_satisfaction_delta
	if str(state.get("advanced", {}).get("kind", "")) == "advanced-pentest" and not state.advanced.get("world", {}).get("remediation", {}).get("requests", []).is_empty():
		state.last_receipt.pentest_changes = {"cost_total":int(state.work.get("pentest_change_cost", 0)),"requests":state.advanced.world.remediation.requests.duplicate(true),"revision":int(state.advanced.world.get("change_revision", 0)),"retests":state.advanced.world.get("retests", {}).duplicate(true)}
		if str(state.advanced.get("engagement", "")) == "relay-v1":
			state.last_receipt.pentest_changes["engagement"] = "relay-v1"
			state.last_receipt.pentest_changes["shipping"] = state.advanced.world.get("shipping", {}).duplicate(true)
	if state.work.has("endpoint_impact"): state.last_receipt.endpoint_impact = state.work.endpoint_impact.duplicate(true)
	if endpoint_containment: state.last_receipt.endpoint_satisfaction_delta = endpoint_satisfaction_delta
	var hotel_outcome := _hotel_workflow_outcome()
	if not hotel_outcome.is_empty(): state.last_receipt.hotel_workflow = hotel_outcome
	if HOTEL_HANDOFF.is_case(str(state.contract.get("case_id", ""))):
		state.last_receipt.hotel_recovery_source_contract_id = str(state.contract.get("hotel_recovery_source_contract_id", ""))
	state.last_receipt.delivery_results = _delivery_results()
	if invoiced:
		var draft: Dictionary = BILLING.create_draft(state, id, state.contract, state.last_receipt)
		if not bool(draft.get("ok", false)):
			state = previous_state; _assignments = previous_assignments; return false
		state.last_receipt.invoice_id = str(draft.invoice.id)
		state.last_receipt.billing_version = 1
	state.history.append({"id":id,"case_id":state.contract.get("case_id",""),"copy_id":mission().id,"title":mission().title,"day":state.day,"reward":fee,"bonus":bonus,"expense":int(status.costs),"material_cost":int(status.get("material_cost",0)),"hardware_serial":str(_customer_hardware().get("serial","")),"profit":net,"cash_delta":delivery_cash,"billing_version":1 if invoiced else 0,"retainer":0,"checks":state.checks.duplicate(true),"grade":str(review.get("grade","C")),"quality_score":int(review.get("score",0)),"baseline_bonus":baseline_bonus,"satisfaction_before":satisfaction_before,"satisfaction_after":int(relation.satisfaction),"renewal_outcome":renewal_outcome})
	var delivered_case: Dictionary = CASES.by_id(str(state.contract.get("case_id", "")))
	state.history[-1].client = client
	state.history[-1].rating = str(status.quality)
	state.history[-1].chapter = _current_chapter()
	state.history[-1].work_family = str(delivered_case.get("work_family", COMPANY_CYCLE.FAMILIES[_current_chapter()]))
	# Keep this delivery's existing observations after dispatch contexts retire.
	state.history[-1].delivery_results = state.last_receipt.delivery_results.duplicate(true)
	if state.last_receipt.has("pentest_changes"): state.history[-1].pentest_changes = state.last_receipt.pentest_changes.duplicate(true)
	if state.last_receipt.has("saas_outcome"):
		state.history[-1].saas_outcome = state.last_receipt.saas_outcome.duplicate(true)
		state.history[-1].saas_satisfaction_delta = saas_satisfaction_delta
		if state.last_receipt.has("saas_business_satisfaction_delta"): state.history[-1].saas_business_satisfaction_delta = saas_business_satisfaction_delta
	if state.last_receipt.has("endpoint_impact"): state.history[-1].endpoint_impact = state.last_receipt.endpoint_impact.duplicate(true)
	if endpoint_containment: state.history[-1].endpoint_satisfaction_delta = endpoint_satisfaction_delta
	if state.last_receipt.has("hotel_workflow"): state.history[-1].hotel_workflow = state.last_receipt.hotel_workflow.duplicate(true)
	if state.last_receipt.has("hotel_recovery_source_contract_id"): state.history[-1].hotel_recovery_source_contract_id = state.last_receipt.hotel_recovery_source_contract_id
	state.history[-1].request_mail = preload("res://scripts/mail_request_record.gd").capture(mission(),str(state.contract.get("case_id","")),str(mission().get("id","" )).begins_with("service-4-case-") and int(_vm().state.get("edr_model_version",1))>=2)
	state.clients[id] = {"title":mission().title,"debrief":mission().debrief,"config":_vm().state.get("applied", {}).duplicate(true),"evidence":mission().evidence.duplicate(true),"checks":state.checks.duplicate(true)}
	COMPANY_CYCLE.record_delivery(self, id, state.last_receipt)
	if str(state.contract.get("case_id", "")) == "advanced-saas-watch":
		SAAS_WATCH.finish(state, str(state.contract.get("saas_watch_source_contract_id", "")), id, false)
	if state.get("career_mode", false): _sync_contract_context(); state.contract_contexts[id].completed = true; _make_offers()
	if state.contract_plan == "care" and not captured_targets.is_empty():
		MAINTENANCE_SCOPE.retain_delivery(self,client,captured_targets)
	if not save_game():
		state = previous_state; _assignments = previous_assignments
		return false
	changed.emit(); return true

func current_done() -> bool:
	var id: String = String(state.current_contract_id) if state.career_mode else String(mission().get("id", ""))
	return id in state.completed_ids

func _ensure_staff_wage(id: String) -> void:
	var worker: Dictionary = state.staff.get(id,{})
	if not bool(worker.get("active",false)): return
	var amount := staff_daily_wage(id,str(worker.get("shift","day")))
	for entry in state.staff_payroll.due:
		if int(entry.get("day",-1)) != int(state.day) or str(entry.get("staff_id","")) != id: continue
		var increase := maxi(0,amount-int(entry.get("amount",0)))
		entry.amount = maxi(amount,int(entry.get("amount",0)))
		entry.paid = int(entry.get("paid_amount",0)) >= int(entry.amount)
		if increase > 0 and bool(entry.get("expense_recorded",false)):
			state.profit -= increase
			state.history.append({"kind":"payroll","day":int(state.day),"staff_id":id,"amount":increase,"expense":increase})
		return
	state.staff_payroll.due.append({"day":int(state.day),"staff_id":id,"amount":amount,"paid_amount":0,"paid":false,"expense_recorded":false})

func _settle_staff_payroll() -> void:
	if not bool(state.get("staff_payroll",{}).get("enabled",false)): return
	for id in state.staff: _ensure_staff_wage(str(id))
	var available := maxi(0,int(state.cash))
	for entry in state.staff_payroll.due:
		if int(entry.get("day",-1)) > int(state.day): continue
		if not bool(entry.get("expense_recorded",false)):
			state.profit -= int(entry.amount); entry.expense_recorded = true
			state.history.append({"kind":"payroll","day":int(entry.day),"staff_id":str(entry.staff_id),"amount":int(entry.amount),"expense":int(entry.amount)})
		var owed := maxi(0,int(entry.amount)-int(entry.get("paid_amount",0)))
		var payment := mini(available,owed)
		available -= payment; state.cash -= payment
		if payment > 0: state.history.append({"kind":"wage_payment","day":int(state.day),"staff_id":str(entry.get("staff_id","")),"amount":payment})
		entry.paid_amount = int(entry.get("paid_amount",0)) + payment
		entry.paid = int(entry.paid_amount) >= int(entry.amount)
	state.staff_payroll.last_settled_day = int(state.day)

func end_day() -> bool:
	if state.game_complete or not end_day_reason().is_empty(): return false
	_crew_runtime_registered.clear()
	if state.get("career_mode", false):
		var career_before: Dictionary = state.duplicate(true); var career_assignments := _assignments.duplicate(true); var career_machine = _machine; var career_machine_key := _machine_key
		_sync_contract_context()
		var before_settlement := DAY_LEDGER.preview(self)
		_apply_retainer(); _settle_staff_payroll(); DAY_LEDGER.settle(self,before_settlement)
		state.day += 1; _complete_office_expansion(); state.clock_minutes = BUSINESS_START_MINUTE; state.accepted = false; state.inspected = false; state.awaiting_contract = true; state.current_contract_id = ""; state.contract = {}; state.targets = []; state.target_index = 0; state.checks = []; state.validated_revision = -1; _assignments = {}; state.assignments = {}; CARE.advance_day(self); _prepare_maintenance_day(); _make_offers()
		var receipts: Dictionary = BILLING.settle_due(state, int(state.day))
		if not bool(receipts.get("ok", false)):
			state = career_before; _assignments = career_assignments; _machine = career_machine; _machine_key = career_machine_key; return false
		for staff_id in state.staff:
			var staff_item: Dictionary = state.staff[staff_id]
			if not bool(staff_item.get("active",false)): continue
			var pending := str(staff_item.get("pending_shift",""))
			if STAFF_SHIFTS.has(pending): staff_item.shift = pending
			staff_item.pending_shift = ""; staff_item.minutes_used = 0.0; staff_item.minutes_day = int(state.day)
			_ensure_staff_wage(str(staff_id))
		for context_id in state.contract_contexts.keys():
			if bool(state.contract_contexts[context_id].get("completed", false)): state.contract_contexts.erase(context_id)
		var resume_id := ""
		for context_id in state.contract_contexts.keys():
			if not bool(state.contract_contexts[context_id].get("completed", false)): resume_id = str(context_id); break
		if not resume_id.is_empty():
			_activate_contract_context(resume_id); state.awaiting_contract = false
		if not save_game(): state = career_before; _assignments = career_assignments; _machine = career_machine; _machine_key = career_machine_key; return false
		changed.emit(); return true
	if not current_done(): return false
	var previous_state: Dictionary = state.duplicate(true)
	var previous_assignments: Dictionary = _assignments.duplicate(true); var previous_machine = _machine; var previous_machine_key := _machine_key
	_apply_retainer()
	_assignments = {}; state.assignments = {}
	if state.career_mode:
		state.accepted = false; state.inspected = false; state.day += 1; state.clock_minutes = BUSINESS_START_MINUTE; state.awaiting_contract = true; state.current_contract_id = ""; state.checks = []; state.validated_revision = -1; state.targets = []; state.contract = {}; _prepare_maintenance_day(); _make_offers()
		if not save_game(): state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
		changed.emit(); return true
	if int(state.chapter) >= RULES.size() - 1:
		state.game_complete = true
		_assignments = {}
		state.assignments = {}
		changed.emit()
		if not save_game(): state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
		return true
	state.chapter = int(state.chapter) + 1
	state.day = int(state.day) + 1
	state.clock_minutes = BUSINESS_START_MINUTE
	state.accepted = false; state.inspected = false; state.config = _default_fields(state.chapter); _prepare_maintenance_day()
	state.revision = int(state.revision) + 1; state.validated_revision = -1; state.checks = []; state.targets = []; _assignments = {}; state.assignments = {}
	if not save_game(): state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
	changed.emit(); return true

func _apply_retainer() -> void:
	if int(state.get("retainer_settled_day", -1)) == int(state.day): return
	_prepare_maintenance_day()
	var portfolio := care_portfolio()
	var service_cost := int(portfolio.service_cost_daily)
	var active_clients: Array[String] = []
	for account in portfolio.clients:
		if str(account.status) == "active": active_clients.append(str(account.client))
	var earned := 0; var missed := 0; var verified_jobs := 0
	for legacy_client in state.get("care_agreements", {}).keys():
		var legacy_agreement: Dictionary = state.care_agreements[legacy_client]
		var legacy_name := str(legacy_client)
		if (bool(legacy_agreement.get("maintenance_legacy", false)) or _maintenance_targets_for(legacy_name).is_empty()) and legacy_name in active_clients:
			earned += int(legacy_agreement.get("fee", 150))
	for item in state.get("maintenance_jobs", []):
		var job_day := int(item.get("day", -1))
		if job_day != int(state.day): continue
		var item_client := str(item.get("client", ""))
		if item_client not in active_clients: continue
		if str(item.get("status", "")) == "done" and not bool(item.get("paid", false)):
			earned += int(item.get("fee", 0)); item.paid = true; verified_jobs += 1
		elif str(item.get("status", "")) in ["pending", "working", "failed", "queued", "paused"]:
			if str(item.status) not in ["queued","paused"]: item.status="failed"; item.remaining=0.0
			item.missed_day = int(state.day); missed += 1
			var missed_client := str(item.get("client", "")); var relation: Dictionary = state.customer_relations.get(missed_client, {"satisfaction":70,"completed_count":0,"last_quality":"","last_day":0})
			var last_penalty := int(relation.get("maintenance_missed_day", -1))
			if last_penalty != int(state.day):
				relation.satisfaction = clampi(int(relation.get("satisfaction",70)) - 8, 0, 100); relation.maintenance_missed_day = int(state.day); state.customer_relations[missed_client] = relation
				if int(relation.satisfaction) < 40: _suspend_care(missed_client)
	var income := earned - service_cost
	state.cash += income
	state.profit += income
	state.strategy_income += income
	state.retainer_settled_day = int(state.day)
	if not state.has("retainer_daily") or not state.retainer_daily is Dictionary: state.retainer_daily = {}
	state.retainer_daily[str(int(state.day))] = {"day":int(state.day),"retainer":income,"retainer_gross":earned,"retainer_cost":service_cost,"retainer_net":income,"maintenance_earned":earned,"maintenance_missed":missed}
	state.retainer_daily[str(int(state.day))].maintenance_completed = verified_jobs
	state.history.append({"id":"retainer-day-%d" % int(state.day),"day":int(state.day),"retainer":income,"retainer_gross":earned,"retainer_cost":service_cost,"retainer_net":income,"maintenance_earned":earned,"maintenance_missed":missed,"maintenance_completed":verified_jobs})
	if state.history.size() > 100:
		# Keep every current-day cash row for DayLedger's opening/closing
		# reconciliation, while retaining the normal recent-history window.
		var first_current_day := -1
		for i in state.history.size():
			if int(state.history[i].get("day", -1)) == int(state.day): first_current_day = i; break
		var recent_start := maxi(0, state.history.size() - 100)
		var keep_from := recent_start if first_current_day < 0 else mini(recent_start, first_current_day)
		state.history = state.history.slice(keep_from)
	var last_receipt: Dictionary = state.get("last_receipt", {})
	if not last_receipt.is_empty() and int(last_receipt.get("day", -1)) == int(state.day):
		last_receipt.retainer = income
		last_receipt.retainer_gross = earned
		last_receipt.retainer_cost = service_cost
		last_receipt.retainer_net = income
		last_receipt.maintenance_earned = earned
		last_receipt.maintenance_missed = missed
		state.last_receipt = last_receipt
	_update_growth()

func recurring_income() -> int:
	return int(care_portfolio().net_daily)

func staff_candidates() -> Array:
	var out: Array = []
	for id in STAFF_CANDIDATES:
		var c: Dictionary = STAFF_CANDIDATES[id]
		out.append({"id":id,"name":UI_COPY.copy("staff_name_"+id),"role":str(c.role),"hire_fee":int(c.hire_fee),"daily_wage":int(c.daily_wage)})
	return out

func staff_shift_catalog() -> Array:
	return [{"id":"day","label":UI_COPY.copy("staffing_shift_day"),"start":540,"end":1080},{"id":"morning","label":UI_COPY.copy("staffing_shift_morning"),"start":540,"end":780},{"id":"afternoon","label":UI_COPY.copy("staffing_shift_afternoon"),"start":780,"end":1080}]

func staff_daily_wage(id: String, shift: String = "day") -> int:
	var base := int(STAFF_CANDIDATES.get(id,{}).get("daily_wage", state.get("staff",{}).get(id,{}).get("daily_wage",0)))
	return ceili(base * float(STAFF_SHIFTS.get(shift, STAFF_SHIFTS.day).fraction))

func staff_capacity() -> int:
	var capacity := 1 if "teamdesk" in state.get("equipment",[]) else 0
	if "annexdesk_a" in state.get("equipment",[]): capacity += 1
	if "annexdesk_b" in state.get("equipment",[]): capacity += 1
	return capacity

func staff_workplace(id: String) -> String:
	if id in ["aya","ren"]: return id
	var item: Dictionary = state.get("staff",{}).get(id,{})
	var workplace := str(item.get("workplace",""))
	return workplace if workplace in state.get("equipment",[]) else ""

func team_members() -> Array:
	var out: Array = [{"id":"aya","name":member_name("aya"),"role":"aya","hired":false,"shift":"day","daily_wage":0,"result_path":colleague_result_path("aya"),"workplace":staff_workplace("aya")},{"id":"ren","name":member_name("ren"),"role":"ren","hired":false,"shift":"day","daily_wage":0,"result_path":colleague_result_path("ren"),"workplace":staff_workplace("ren")}]
	for id in state.get("staff",{}):
		var item: Dictionary = state.staff[id]
		if not bool(item.get("active",false)): continue
		out.append({"id":str(id),"name":UI_COPY.copy("staff_name_"+str(id)),"role":str(item.get("role","")),"hired":bool(item.get("active",false)),"shift":str(item.get("shift","day")),"daily_wage":staff_daily_wage(str(id),str(item.get("shift","day"))),"result_path":colleague_result_path(str(id)),"workplace":staff_workplace(str(id))})
	return out

func staff_summary() -> Dictionary:
	var count := 0; var due := 0; var arrears := 0
	for item in state.get("staff",{}).values():
		if bool(item.get("active",false)): count += 1
	for item in state.get("staff_payroll",{}).get("due",[]):
		if bool(item.get("paid",false)): continue
		var remaining := maxi(0,int(item.get("amount",0))-int(item.get("paid_amount",0)))
		if int(item.get("day",-1)) == int(state.day): due += remaining
		else: arrears += remaining
	return {"count":count,"capacity":staff_capacity(),"due":due,"arrears":arrears}

func company_operating_summary() -> Dictionary:
	var draft_invoices: Array = []
	var draft_total := 0
	for invoice in BILLING.list(state):
		if str(invoice.get("status", "")) != "draft": continue
		draft_invoices.append(invoice.duplicate(true)); draft_total += int(invoice.get("amount",0))
	var stock_shortages: Array = []
	var stock_shortage_total := 0
	var stock_summary := customer_stock_summary()
	for sku in stock_summary.get("by_sku", {}).keys():
		var item: Dictionary = stock_summary.by_sku[sku]
		if int(item.get("shortage",0)) > 0:
			stock_shortages.append(item.duplicate(true)); stock_shortage_total += int(item.get("shortage",0))
	var receiving_count := 0
	var incoming_count := 0
	for unit in customer_stock_units():
		if str(unit.get("status", "")) == "ready": receiving_count += 1
		elif str(unit.get("status", "")) == "queued": incoming_count += 1
	for order in state.get("delivery_orders", []):
		if str(order.get("status", "")) == "ready": receiving_count += 1
		elif str(order.get("status", "")) == "queued": incoming_count += 1
	var pending_equipment := 0
	for order in state.get("delivery_orders", []):
		if str(order.get("status", "")) != "installed": pending_equipment += 1
	var maintenance_pending := 0
	for job in state.get("maintenance_jobs", []):
		if int(job.get("day",state.day)) == int(state.day) and str(job.get("status", "")) in ["pending", "queued", "paused", "failed"]: maintenance_pending += 1
	var staffing := staff_summary()
	var capacity := contract_capacity(); var open_contracts := _open_contract_count()
	var billing := billing_summary()
	var total_staff := team_members().size()
	return {"cash":int(state.get("cash",0)),"draft_invoices":draft_invoices,"draft_invoice_count":draft_invoices.size(),"draft_invoice_total":draft_total,"draft_count":draft_invoices.size(),"draft_total":draft_total,"receivable_total":int(billing.get("receivable_total",0)),"paid_today":int(billing.get("paid_today",0)),"due_next_day":int(billing.get("due_next_day",0)),"stock_shortages":stock_shortages,"stock_shortage_total":stock_shortage_total,"stock_shortage_count":stock_shortage_total,"receiving_count":receiving_count,"incoming_count":incoming_count,"installed_equipment_count":state.get("equipment",[]).size(),"pending_equipment_count":pending_equipment,"staff_count":total_staff,"extra_staff_count":int(staffing.get("count",0)),"staff_capacity":int(staffing.get("capacity",0)),"workforce_capacity":2+int(staffing.get("capacity",0)),"contracts":open_contracts,"open_contracts":open_contracts,"contract_capacity":capacity,"free_contract_slots":maxi(0,capacity-open_contracts),"payroll_due":int(staffing.get("due",0)),"payroll_arrears":int(staffing.get("arrears",0)),"maintenance_pending":maintenance_pending}

func colleague_role(id: String) -> String:
	if id in ["aya","ren"]: return id
	return str(state.get("staff",{}).get(id,{}).get("role",""))

func colleague_result_path(id: String) -> String:
	if id == "aya": return "/home/operator/aya-inspection.txt"
	if id == "ren": return "/home/operator/ren-verification.txt"
	return "/home/operator/%s-result.txt" % id

func staff_availability(id: String, kind: String = "normal", target_chapter: int = -1, check_hardware: bool = true) -> String:
	if check_hardware and kind=="normal" and not _customer_hardware_connected(): return UI_COPY.copy("stock_error_hardware")
	var role := colleague_role(id)
	if role.is_empty(): return UI_COPY.copy("staffing_inactive")
	if _assignments.get(id,{}).get("status","") == "working": return UI_COPY.copy("staffing_busy")
	if kind=="normal" and role=="ren" and (target_chapter if target_chapter>=0 else _current_chapter()) not in [1,4]: return UI_COPY.copy("investigation_role_mismatch")
	if id in ["aya","ren"]: return ""
	if not bool(state.get("career_mode",false)): return UI_COPY.copy("staffing_career_only")
	if not bool(state.staff.get(id,{}).get("active",false)): return UI_COPY.copy("staffing_inactive")
	if role == "maintenance" and kind != "maintenance": return UI_COPY.copy("staffing_role_mismatch")
	if int(staff_summary().arrears) > 0: return UI_COPY.copy("staffing_arrears_block")
	var item: Dictionary = state.staff[id]
	var shift: Dictionary = STAFF_SHIFTS.get(str(item.get("shift","day")),STAFF_SHIFTS.day)
	var duration := (8.0 if role == "maintenance" else 12.0) if kind == "maintenance" else team_work_duration(id)
	if _dispatch_start_member == id and _dispatch_start_remaining >= 0.0: duration = _dispatch_start_remaining
	var used := float(item.get("minutes_used",0.0)) if int(item.get("minutes_day",-1)) == int(state.day) else 0.0
	if used + duration > float(int(shift.end)-int(shift.start)): return UI_COPY.copy("staffing_capacity_used")
	if clock_minutes() < int(shift.start) or clock_minutes() + duration > int(shift.end): return UI_COPY.copy("staffing_off_shift")
	return ""

func hire_staff(id: String, shift: String = "day") -> bool:
	if not staff_hire_reason(id,shift).is_empty(): return false
	var c: Dictionary = STAFF_CANDIDATES[id]
	var previous := state.duplicate(true); var assignments_before := _assignments.duplicate(true)
	var old: Dictionary = state.staff.get(id,{})
	var used := float(old.get("minutes_used",0.0)) if int(old.get("minutes_day",-1)) == int(state.day) else 0.0
	state.cash -= int(c.hire_fee); state.profit -= int(c.hire_fee)
	state.staff[id] = {"active":true,"role":str(c.role),"shift":shift,"pending_shift":"","hired_day":int(state.day),"minutes_used":used,"minutes_day":int(state.day),"daily_wage":int(c.daily_wage),"hire_fee":int(c.hire_fee)}
	var occupied: Array[String] = []
	for existing_id in state.staff:
		if str(existing_id) == id or not bool(state.staff[existing_id].get("active",false)): continue
		var existing_workplace := str(state.staff[existing_id].get("workplace",""))
		if not existing_workplace.is_empty(): occupied.append(existing_workplace)
	for workplace in ["teamdesk","annexdesk_a","annexdesk_b"]:
		if workplace in state.equipment and workplace not in occupied:
			state.staff[id].workplace = workplace
			break
	state.staff_payroll.enabled = true; _ensure_staff_wage(id)
	_assignments.erase(id); state.assignments = _assignments.duplicate(true)
	state.history.append({"kind":"staff_cost","day":int(state.day),"staff_id":id,"amount":int(c.hire_fee),"expense":int(c.hire_fee)})
	if not save_game(): state = previous; _assignments = assignments_before; notified.emit(UI_COPY.copy("staffing_save_failed")); return false
	changed.emit(); return true

func staff_hire_reason(id: String, shift: String = "day") -> String:
	if not state.get("career_mode",false): return UI_COPY.copy("staffing_career_only")
	if not STAFF_CANDIDATES.has(id) or not STAFF_SHIFTS.has(shift): return UI_COPY.copy("staffing_invalid_shift")
	if state.staff.has(id) and bool(state.staff[id].get("active",false)): return UI_COPY.copy("staffing_already")
	var active_extra := 0
	for item in state.staff.values(): if bool(item.get("active",false)): active_extra += 1
	if staff_capacity() == 0: return UI_COPY.copy("staffing_no_desk")
	if active_extra >= staff_capacity(): return UI_COPY.copy("staffing_full")
	var c: Dictionary = STAFF_CANDIDATES[id]
	if int(staff_summary().arrears) > 0: return UI_COPY.copy("staffing_arrears_block")
	if clock_minutes() >= int(STAFF_SHIFTS[shift].end): return UI_COPY.copy("staffing_off_shift")
	if int(state.cash) < int(c.hire_fee)+staff_daily_wage(id,shift): return UI_COPY.copy("staffing_funds")
	return ""

func release_staff(id: String) -> bool:
	if not state.staff.has(id) or not bool(state.staff[id].get("active",false)) or _assignments.get(id,{}).get("status","") == "working" or _dispatch_has_queued(id): return false
	var previous := state.duplicate(true); state.staff[id].active = false; state.staff[id].workplace = ""
	for agreement in state.care_agreements.values():
		if str(agreement.get("maintenance_owner",""))==id:agreement.erase("maintenance_owner")
	if not save_game(): state = previous; notified.emit(UI_COPY.copy("staffing_save_failed")); return false
	changed.emit(); return true

func set_staff_shift(id: String, shift: String) -> bool:
	if not state.staff.has(id) or not STAFF_SHIFTS.has(shift) or not bool(state.staff[id].get("active",false)): return false
	var previous := state.duplicate(true); state.staff[id].pending_shift = "" if shift == str(state.staff[id].shift) else shift
	if not save_game(): state = previous; notified.emit(UI_COPY.copy("staffing_save_failed")); return false
	changed.emit(); return true

func pay_staff_arrears() -> bool:
	var remaining := mini(int(staff_summary().arrears),maxi(0,int(state.cash)))
	if remaining <= 0: return false
	var previous := state.duplicate(true)
	state.cash -= remaining
	for item in state.staff_payroll.due:
		if remaining <= 0: break
		if int(item.get("day",-1)) >= int(state.day): continue
		var owed := maxi(0,int(item.amount)-int(item.get("paid_amount",0)))
		var payment := mini(remaining,owed)
		item.paid_amount = int(item.get("paid_amount",0)) + payment; remaining -= payment
		if payment > 0: state.history.append({"kind":"wage_payment","day":int(state.day),"staff_id":str(item.get("staff_id","")),"amount":payment})
		item.paid = int(item.paid_amount) >= int(item.amount)
	if not save_game(): state = previous; notified.emit(UI_COPY.copy("staffing_save_failed")); return false
	changed.emit(); return true

func team_work_duration(id: String) -> float:
	var role := colleague_role(id)
	var duration := 8.0 if role == "aya" else (15.0 if role == "ren" else 8.0)
	if "backup" in state.equipment: duration -= 1.0
	if "monitor" in state.equipment: duration -= 1.0
	if "teamdesk" in state.equipment: duration -= 2.0
	return maxf(3.0, duration)

func team_work_effects(id: String) -> Dictionary:
	# Lock attribution with the same installed equipment used to price this job.
	# Later purchases must not claim a saving on work already queued or started.
	var effects := {}
	if colleague_role(id) not in ["aya", "ren"]: return effects
	if "monitor" in state.get("equipment", []):
		var duration := team_work_duration(id)
		var without_monitor := 15.0 if colleague_role(id) == "ren" else 8.0
		if "backup" in state.equipment: without_monitor -= 1.0
		if "teamdesk" in state.equipment: without_monitor -= 2.0
		without_monitor = maxf(3.0, without_monitor)
		if without_monitor > duration:
			effects.monitor = {"base_minutes":without_monitor,"actual_minutes":duration,"saved_minutes":without_monitor-duration}
	return effects

func equipment_work_id(member_id: String) -> String:
	return "%s:%d:%d" % [member_id, Time.get_ticks_usec(), int(state.day)]

func operations_assign(member_id: String, contract_id: String, target_index: int) -> bool:
	return OPERATIONS.assign(self,member_id,contract_id,target_index)

func _dispatch_queue_map() -> Dictionary:
	if not state.has("dispatch_queues") or not state.dispatch_queues is Dictionary: state.dispatch_queues={}
	if not state.has("dispatch_holds") or not state.dispatch_holds is Dictionary: state.dispatch_holds={}
	return state.dispatch_queues

func _dispatch_id(member_id: String, job: Dictionary) -> String:
	if str(job.get("kind","normal")) == "maintenance": return "maintenance|"+str(job.get("client",""))
	return "normal|%s|%d|%s" % [str(job.get("contract_id","")),int(job.get("target_index",0)),colleague_role(member_id)]

func _dispatch_duplicate(member_id: String, kind: String, contract_id: String, target_index: int, client: String = "") -> bool:
	var candidates: Array=[]
	for owner in _assignments:
		var active: Dictionary=_assignments[owner]
		if str(active.get("status","")) != "working": continue
		var item:=active.duplicate(); item.member_id=str(owner); candidates.append(item)
	for owner in _dispatch_queue_map():
		for raw in state.dispatch_queues[owner]:
			var item: Dictionary=raw.duplicate(); item.member_id=str(owner); candidates.append(item)
	for item in candidates:
		if str(item.get("kind","normal")) != kind: continue
		if kind == "maintenance" and str(item.get("client","")) == client: return true
		if kind == "normal" and colleague_role(str(item.member_id)) == colleague_role(member_id) and str(item.get("contract_id","")) == contract_id and int(item.get("target_index",-1)) == target_index: return true
	return false

func _dispatch_reason(item: Dictionary, for_start: bool = true) -> String:
	var member_id:=str(item.get("member_id","")); var kind:=str(item.get("kind","normal")); var role:=colleague_role(member_id)
	if role.is_empty() or (member_id not in ["aya","ren"] and not bool(state.get("staff",{}).get(member_id,{}).get("active",false))): return UI_COPY.copy("staffing_inactive")
	if kind == "normal" and role == "maintenance": return UI_COPY.copy("staffing_role_mismatch")
	if member_id not in ["aya","ren"] and int(staff_summary().arrears)>0: return UI_COPY.copy("staffing_arrears_block")
	var chapter: int=-1
	if kind == "normal":
		var target_info:=OPERATIONS._target_context(self,str(item.get("contract_id","")),int(item.get("target_index",-1)),str(item.get("status",""))=="paused")
		if not bool(target_info.get("ok",false)): return UI_COPY.copy("dispatch_invalid")
		chapter=int(target_info.target.get("chapter",target_info.context.get("chapter",0)))
		var queued_contract: Dictionary = target_info.context.get("contract",{})
		if _advanced_case_id(str(queued_contract.get("case_id",""))): return UI_COPY.copy("adv_manual_only","Advanced missions require the operator console.")
		if role == "ren" and chapter not in [1,4]: return UI_COPY.copy("investigation_role_mismatch")
		if for_start and not _colleague_hardware_connected(item): return UI_COPY.copy("stock_error_hardware")
	else:
		var client:=str(item.get("client","")); var job:=_maintenance_job_for(client)
		if job.is_empty() or str(job.get("status","")) not in ["pending","queued","paused"] or _maintenance_targets_for(client).is_empty(): return UI_COPY.copy("dispatch_invalid")
		if CARE._busy_client(self,client) or str(state.care_incidents.get(client,{}).get("status",""))=="working": return UI_COPY.copy("care_incident_working")
		if not bool(state.care_agreements.get(client,{}).get("active",false)) and str(state.care_incidents.get(client,{}).get("status",""))!="recheck" and str(item.get("status",""))!="paused": return UI_COPY.copy("dispatch_invalid")
	if for_start and member_id not in ["aya","ren"]:
		var staff_item: Dictionary=state.staff[member_id]; var shift: Dictionary=STAFF_SHIFTS.get(str(staff_item.get("shift","day")),STAFF_SHIFTS.day)
		var duration:=_crew_minutes(item)*float(item.get("remaining",0.0))/maxf(0.001,float(item.get("total",1.0)))
		var used:=float(staff_item.get("minutes_used",0.0)) if int(staff_item.get("minutes_day",-1))==int(state.day) else 0.0
		if used+duration > int(shift.end)-int(shift.start): return UI_COPY.copy("staffing_capacity_used")
		if clock_minutes()<int(shift.start) or clock_minutes()+duration>int(shift.end): return UI_COPY.copy("staffing_off_shift")
	return ""

func _dispatch_display(member_id: String, item: Dictionary) -> Dictionary:
	var result:=item.duplicate(true); result.member_id=member_id
	result.reason=_dispatch_reason(result) if str(item.get("status","")) in ["queued","paused"] else ""
	if str(item.get("kind","normal"))=="maintenance":
		result.client=str(item.get("client","")); result.title=UI_COPY.copy("dispatch_maintenance"); result.target_name=""
	else:
		var context: Dictionary=state.get("contract_contexts",{}).get(str(item.get("contract_id","")),{})
		if str(item.get("contract_id",""))==str(state.get("current_contract_id","")): context=_context_from_projection()
		var contract: Dictionary=context.get("contract",{}); result.client=str(contract.get("client","")); result.title=str(contract.get("title",""))
		var targets: Array=context.get("targets",[]); var index:=int(item.get("target_index",-1))
		result.target_name=str(targets[index].get("name","")) if index>=0 and index<targets.size() else ""
	return result

func dispatch_queue(member_id: String) -> Array:
	var result: Array=[]
	for item in _dispatch_queue_map().get(member_id,[]): result.append(_dispatch_display(member_id,item))
	return result

func _dispatch_has_queued_maintenance(client: String) -> bool:
	for queue in _dispatch_queue_map().values():
		for item in queue:
			if str(item.get("kind","normal"))=="maintenance" and str(item.get("client",""))==client: return true
	return false

func _dispatch_has_queued(member_id: String) -> bool:
	return not _dispatch_queue_map().get(member_id,[]).is_empty()

func _dispatch_save(previous: Dictionary, previous_assignments: Dictionary, previous_machine, previous_key: String) -> bool:
	state.assignments=_assignments.duplicate(true)
	if save_game(): changed.emit(); return true
	state=previous; _assignments=previous_assignments; _machine=previous_machine; _machine_key=previous_key
	return false

func dispatch_enqueue(member_id: String, contract_id: String, target_index: int) -> bool:
	_dispatch_queue_map()
	if _dispatch_duplicate(member_id,"normal",contract_id,target_index): return false
	var duration:=team_work_duration(member_id)
	var item: Dictionary={"kind":"normal","status":"queued","member_id":member_id,"role":colleague_role(member_id),"contract_id":contract_id,"target_index":target_index,"remaining":duration,"total":duration,"work_minutes":duration,"work_minutes_accounted":0.0,"queued_day":int(state.day)}
	item.equipment_effects = team_work_effects(member_id)
	item.equipment_work_id = equipment_work_id(member_id)
	if not _dispatch_reason(item,false).is_empty(): return false
	item.id=_dispatch_id(member_id,item)
	var previous:=state.duplicate(true); var before:=_assignments.duplicate(true); var machine=_machine; var key:=_machine_key
	if not state.dispatch_queues.has(member_id): state.dispatch_queues[member_id]=[]
	state.dispatch_queues[member_id].append(item)
	return _dispatch_save(previous,before,machine,key)

func dispatch_enqueue_maintenance(member_id: String, client: String) -> bool:
	_dispatch_queue_map(); client=client.strip_edges()
	if _dispatch_duplicate(member_id,"maintenance","",-1,client): return false
	var duration:=8.0 if colleague_role(member_id)=="maintenance" else 12.0
	var item: Dictionary={"kind":"maintenance","status":"queued","member_id":member_id,"role":colleague_role(member_id),"client":client,"remaining":duration,"total":duration,"minutes":duration,"work_minutes_accounted":0.0,"queued_day":int(state.day)}
	if not _dispatch_reason(item,false).is_empty(): return false
	item.id=_dispatch_id(member_id,item)
	var previous:=state.duplicate(true); var before:=_assignments.duplicate(true); var machine=_machine; var key:=_machine_key
	var job:=_maintenance_job_for(client); job.status="queued"; job.assignee=member_id
	item.maintenance_job_id=str(job.id)
	if not state.dispatch_queues.has(member_id): state.dispatch_queues[member_id]=[]
	state.dispatch_queues[member_id].append(item)
	return _dispatch_save(previous,before,machine,key)

func dispatch_start(member_id: String, job_id: String) -> bool:
	if _assignments.get(member_id,{}).get("status","")=="working": return false
	var queue: Array=_dispatch_queue_map().get(member_id,[]); var index: int=-1
	for i in queue.size():
		if str(queue[i].get("id",""))==job_id: index=i; break
	if index<0: return false
	var item: Dictionary=queue[index].duplicate(true); item.member_id=member_id
	if not _dispatch_reason(item).is_empty(): return false
	var previous:=state.duplicate(true); var before:=_assignments.duplicate(true); var machine=_machine; var key:=_machine_key
	queue.remove_at(index); state.dispatch_queues[member_id]=queue; state.dispatch_holds[member_id]=false
	var paused:=str(item.get("status",""))=="paused"
	var started:=paused
	if paused:
		# Keep the original job and its accounted minutes; resuming is not a new assignment.
		item.status="working"; item.phase=UI_COPY.copy("dispatch_active")
		if str(item.get("kind","normal"))=="maintenance":
			item.targets=_maintenance_targets_for(str(item.client)).duplicate(true)
			var stored:=_maintenance_job_for(str(item.client)); stored.status="working"; stored.assignee=member_id; stored.remaining=float(item.remaining); item.maintenance_job_id=str(stored.id)
		_assignments[member_id]=item
	else:
		_dispatch_start_remaining=float(item.remaining); _dispatch_start_member=member_id; _dispatch_transaction=true
		if str(item.get("kind","normal"))=="maintenance":
			var stored:=_maintenance_job_for(str(item.client)); stored.status="pending"
			started=assign_maintenance(str(item.client),member_id)
		else: started=operations_assign(member_id,str(item.contract_id),int(item.target_index))
		_dispatch_transaction=false; _dispatch_start_remaining=-1.0; _dispatch_start_member=""
	if not started:
		state=previous; _assignments=before; _machine=machine; _machine_key=key; return false
	var active: Dictionary=_assignments[member_id]
	if str(active.get("kind","normal"))=="maintenance": active.maintenance_job_id=str(active.get("maintenance_job_id",active.get("id","")))
	active.id=job_id; active.member_id=member_id; active.kind=str(item.get("kind","normal")); active.role=colleague_role(member_id)
	active.total=float(item.total); active.remaining=float(item.remaining); active.work_minutes_accounted=float(item.get("work_minutes_accounted",0.0))
	# The queue owns the original duration and its provenance, including an empty
	# snapshot for a job reserved before equipment installation or in an old save.
	active.equipment_effects = item.get("equipment_effects", {}).duplicate(true) if item.get("equipment_effects", {}) is Dictionary else {}
	active.equipment_work_id = str(item.get("equipment_work_id", ""))
	if active.kind=="normal": active.work_minutes=float(item.get("work_minutes",item.total))
	else: active.minutes=float(item.get("minutes",item.total)); active.targets=_maintenance_targets_for(str(item.client)).duplicate(true)
	active.erase("work_started_at"); active.erase("work_started_day"); active.erase("segment_minutes")
	return _dispatch_save(previous,before,machine,key)

func dispatch_pause(member_id: String) -> bool:
	var job: Dictionary=_assignments.get(member_id,{})
	if str(job.get("status",""))!="working": return false
	var previous:=state.duplicate(true); var before:=_assignments.duplicate(true); var machine=_machine; var key:=_machine_key
	_account_crew_minutes(member_id,job,false)
	job.erase("work_started_at"); job.erase("work_started_day"); job.erase("segment_minutes")
	if str(job.get("kind","normal"))=="maintenance":
		job.maintenance_job_id=str(job.get("maintenance_job_id",job.get("id","")))
		var stored:=_maintenance_job_for(str(job.client)); stored.status="paused"; stored.remaining=float(job.remaining)
	job.id=_dispatch_id(member_id,job); job.member_id=member_id; job.kind=str(job.get("kind","normal")); job.role=colleague_role(member_id); job.status="paused"; job.phase=UI_COPY.copy("dispatch_paused")
	var queue: Array=_dispatch_queue_map().get(member_id,[]); queue.push_front(job.duplicate(true)); state.dispatch_queues[member_id]=queue; state.dispatch_holds[member_id]=true
	_assignments.erase(member_id)
	return _dispatch_save(previous,before,machine,key)

func dispatch_move(member_id: String, job_id: String, offset: int) -> bool:
	var queue: Array=_dispatch_queue_map().get(member_id,[]); var index: int=-1
	for i in queue.size():
		if str(queue[i].get("id",""))==job_id: index=i; break
	if index<0: return false
	var destination:=clampi(index+offset,0,queue.size()-1)
	if destination==index: return true
	var previous:=state.duplicate(true); var before:=_assignments.duplicate(true); var machine=_machine; var key:=_machine_key
	var moved: Dictionary=queue[index]; queue.remove_at(index); queue.insert(destination,moved)
	return _dispatch_save(previous,before,machine,key)

func dispatch_remove(member_id: String, job_id: String) -> bool:
	var queue: Array=_dispatch_queue_map().get(member_id,[]); var index: int=-1
	for i in queue.size():
		if str(queue[i].get("id",""))==job_id: index=i; break
	if index<0 or str(queue[index].get("status",""))!="queued": return false
	var previous:=state.duplicate(true); var before:=_assignments.duplicate(true); var machine=_machine; var key:=_machine_key
	var item: Dictionary=queue[index]
	if str(item.get("kind","normal"))=="maintenance":
		var stored:=_maintenance_job_for(str(item.client)); stored.status="pending"; stored.assignee=""
	queue.remove_at(index)
	return _dispatch_save(previous,before,machine,key)

func _dispatch_auto_start() -> void:
	for member in _dispatch_queue_map().keys():
		if bool(state.dispatch_holds.get(member,false)) or _assignments.get(member,{}).get("status","")=="working": continue
		var queue: Array=state.dispatch_queues[member]
		if not queue.is_empty(): dispatch_start(str(member),str(queue[0].get("id","")))

func operations_quote(member_id: String, contract_id: String, target_index: int) -> Dictionary:
	var result := OPERATIONS.quote(self,member_id,contract_id,target_index)
	result.reason = UI_COPY.copy(str(result.reason),str(result.reason))
	return result

func staff_workload(member_id: String) -> Dictionary:
	return DISPATCH_FORECAST.workload(self, member_id.strip_edges())

func dispatch_quote_forecast(member_id: String, contract_id: String, target_index: int) -> Dictionary:
	return DISPATCH_FORECAST.quote(self, member_id.strip_edges(), contract_id.strip_edges(), target_index, "normal", "")

func maintenance_quote_forecast(member_id: String, client: String) -> Dictionary:
	return DISPATCH_FORECAST.quote(self, member_id.strip_edges(), "", 0, "maintenance", client.strip_edges())

func prioritize_maintenance(client: String) -> bool:
	return preload("res://scripts/maintenance_dispatch.gd").prioritize(self,client)

func day_preview() -> Dictionary:
	return DAY_LEDGER.preview(self)

func last_day_ledger() -> Dictionary:
	return DAY_LEDGER.latest(self)

func assign_colleague(id: String) -> void:
	var contract_id := str(state.get("current_contract_id",""))
	if state.get("career_mode",false) or not contract_id.is_empty():
		operations_assign(id,contract_id,int(state.get("target_index",0)))
		return
	# Story mode predates the career contract queue and has no contract id.
	# Keep that public action working with the same assignment record consumed
	# by _process/_finish_colleague, without inventing a queue context.
	if not state.get("accepted",false) or current_done() or id.is_empty() or colleague_role(id).is_empty() or _assignments.get(id,{}).get("status","") == "working": return
	if not staff_availability(id,"normal",_current_chapter(),true).is_empty() or not _customer_hardware_connected(): return
	var previous_state := state.duplicate(true); var previous_assignments := _assignments.duplicate(true)
	var duration := team_work_duration(id); var vm: Variant = _vm(); var config_before := ""
	if vm != null:
		var machine_state: Variant = vm.get("state")
		if machine_state is Dictionary:
			var files: Variant = machine_state.get("fs", {})
			var config_path := str(machine_state.get("config_path", ""))
			if files is Dictionary: config_before = str(files.get(config_path, ""))
	_assignments[id] = {"status":"working","remaining":duration,"total":duration,"work_minutes":duration,"work_minutes_accounted":0.0,"revision":int(state.get("revision",0)),"chapter":int(state.get("chapter",0)),"contract_id":"","target_index":int(state.get("target_index",0)),"vm_key":_vm_key(),"role":colleague_role(id),"result_path":colleague_result_path(id),"config_before":config_before,"phase":UI_COPY.copy("care_maintenance_working", "working"),"result":""}
	_assignments[id].equipment_effects = team_work_effects(id)
	_assignments[id].equipment_work_id = equipment_work_id(id)
	state.assignments = _assignments.duplicate(true)
	if not save_game():
		state = previous_state; _assignments = previous_assignments
		return
	changed.emit()

func equipment_catalog() -> Array:
	var items: Array = [{"id":"backup","title":"バックアップ装置","price":3000,"effect":UI_COPY.copy("staffing_effect_backup"),"description":"復旧用の退避・確認をすばやく進める","physical":"共有ラックに設置"},{"id":"monitor","title":"監視モニター","price":4000,"effect":UI_COPY.copy("staffing_effect_monitor"),"description":"設置効果：診断確認時間短縮・保守枠増加","physical":"復旧担当の机に設置"},{"id":"plant","title":"観葉植物","price":1000,"effect":"常設の装飾（作業速度への影響なし）","description":"作業速度影響なし（常設装飾）","physical":"自由に配置"},{"id":"workstation","title":"高速ワークステーション","price":8000,"effect":"設定の保存・編集を8分から6分に短縮","description":"自席PC編集作業短縮","physical":"自席PCを更新"},{"id":"diagnostic","title":"診断コンソール","price":12000,"effect":"検証を6分から4分に短縮・個別の計測 -1分","description":"実測結果の整理を効率化する","physical":"自席PCに診断画面を追加"},{"id":"teamdesk","title":"チーム作業デスク","price":16000,"effect":UI_COPY.copy("staffing_effect_teamdesk"),"description":"設置効果：共同作業時間短縮・保守枠増加","physical":"チーム机を拡張"},{"id":"annexdesk_a","title":UI_COPY.copy("expansion_desk_a"),"price":10000,"effect":UI_COPY.copy("expansion_desk_effect"),"description":UI_COPY.copy("expansion_desk_location"),"physical":UI_COPY.copy("expansion_desk_location")},{"id":"annexdesk_b","title":UI_COPY.copy("expansion_desk_b"),"price":10000,"effect":UI_COPY.copy("expansion_desk_effect"),"description":UI_COPY.copy("expansion_desk_location"),"physical":UI_COPY.copy("expansion_desk_location")}]
	for item in items:
		item.physical = UI_COPY.copy("equipment_monitor_fixed" if str(item.id)=="monitor" else "equipment_free_placement")
		if str(item.id) in ["annexdesk_a","annexdesk_b"]: item.description = item.physical
	return items

func equipment_price(id: String) -> int:
	for item in equipment_catalog():
		if str(item.id) == id:
			var price := int(item.price)
			if int(state.skills.operations) > 0 and id in ["backup", "monitor"]: price = roundi(price * 0.8)
			return price
	return 0

func equipment_unavailable_reason(id: String) -> String:
	if id in ["annexdesk_a","annexdesk_b"] and not office_expanded(): return UI_COPY.copy("expansion_desk_requires_room")
	return ""

func equipment_effect(id: String) -> String:
	for item in equipment_catalog():
		if str(item.id) == id: return str(item.get("effect", item.get("description", "")))
	return ""

func _delivery_box_position(id: String = "") -> Array:
	# Receiving point near the office entrance. World scripts may override the
	# rendered point, but this value is persisted so a save never loses a box.
	# Use the inward row for annex orders; a third outward row clips the wall.
	if id == "annexdesk_a": return [2.7, 0.26, 2.65]
	if id == "annexdesk_b": return [3.4, 0.26, 2.65]
	var ids := ["backup", "monitor", "plant", "workstation", "diagnostic", "teamdesk", "annexdesk_a", "annexdesk_b"]
	var index := ids.find(id)
	if index < 0: index = 0
	var col := index % 3
	var row := int(index / 3)
	return [3.4 + (float(col) - 1.0) * 0.7, 0.26, 3.7 + (float(row) - 0.5) * 0.7]

func equipment_slot(id: String) -> int:
	return int(EQUIPMENT_SLOTS.get(id,-1))

func _new_delivery_order(id: String, price: int, status: String = "queued") -> Dictionary:
	return {"order_id":"delivery-%s-%d" % [id, Time.get_ticks_msec()], "id":id, "price":price,
		"status":status, "elapsed_seconds":0.0, "ordered_at_seconds":0.0,
		"box_position":_delivery_box_position(id), "install_slot":-1, "rotation_y":(-0.25 if id=="monitor" else PI if id=="teamdesk" else 0.0)}

func delivery_orders() -> Array:
	return state.get("delivery_orders", []).duplicate(true) + customer_stock_boxes()

func delivery_for(id: String) -> Dictionary:
	if id.begins_with("stock-"):
		for box in customer_stock_boxes():
			if str(box.id) == id: return box
		return {}
	for order in state.get("delivery_orders", []):
		if str(order.get("id", "")) == id and str(order.get("status", "")) != "installed":
			return order
	return {}

func customer_stock_catalog() -> Array:
	return CUSTOMER_STOCK.catalog()

func customer_stock_units() -> Array:
	return CUSTOMER_STOCK.units(state)

func customer_stock_for(id: String) -> Dictionary:
	return CUSTOMER_STOCK.unit(state, id).duplicate(true)

func _accepted_stock_requirements() -> Array:
	var result: Array = []
	var seen_contracts: Dictionary = {}
	var current_id := str(state.get("current_contract_id", ""))
	if bool(state.get("accepted", false)) and not current_id.is_empty() and not current_done():
		var current_contract: Variant = state.get("contract", {})
		if current_contract is Dictionary:
			var current_requirement: Variant = current_contract.get("supply_requirement", {})
			if current_requirement is Dictionary and not current_requirement.is_empty():
				result.append({"contract_id":current_id,"target_index":int(current_requirement.get("target_index",0)),"sku":str(current_requirement.get("sku",CUSTOMER_STOCK.SKU)),"quantity":maxi(1,int(current_requirement.get("quantity",1)))})
		seen_contracts[current_id] = true
	for raw_id in state.get("contract_contexts", {}).keys():
		var contract_id := str(raw_id)
		if seen_contracts.has(contract_id) or contract_id in state.get("completed_ids", []): continue
		var context: Variant = state.contract_contexts[raw_id]
		if not context is Dictionary or not bool(context.get("accepted", true)) or bool(context.get("completed", false)): continue
		var contract: Variant = context.get("contract", {})
		if not contract is Dictionary: continue
		var requirement: Variant = contract.get("supply_requirement", {})
		if requirement is Dictionary and not requirement.is_empty():
			result.append({"contract_id":contract_id,"target_index":int(requirement.get("target_index",0)),"sku":str(requirement.get("sku",CUSTOMER_STOCK.SKU)),"quantity":maxi(1,int(requirement.get("quantity",1)))})
		seen_contracts[contract_id] = true
	return result

func _customer_stock_sku_summary(sku: String, requirements: Array) -> Dictionary:
	var result := {"ok":true,"error":"","sku":sku,"capacity":CUSTOMER_STOCK.MAX_CAPACITY,"used":0,"cash":int(state.get("cash",0)),"inbound":0,"reserved":0,"reserved_inbound":0,"available":0,"delivered":0,"required":0,"shortage":0}
	var units := customer_stock_units()
	for unit in units:
		if str(unit.get("sku", "")) != sku: continue
		var status := str(unit.get("status", "")); var assigned := not str(unit.get("contract_id", "")).is_empty()
		if status not in ["shipping", "delivered"]: result.used = int(result.used) + 1
		if status == "queued" and not assigned: result.inbound = int(result.inbound) + 1
		if status == "queued" and assigned: result.reserved_inbound = int(result.reserved_inbound) + 1
		if status == "delivered": result.delivered = int(result.delivered) + 1
		if assigned and status != "delivered": result.reserved = int(result.reserved) + 1
		if not assigned and status in ["ready", "stored", "carried"]: result.available = int(result.available) + 1
	for requirement in requirements:
		if str(requirement.get("sku", "")) != sku: continue
		var needed := maxi(1,int(requirement.get("quantity",1)))
		var assigned_count := 0
		for unit in units:
			if str(unit.get("sku", "")) == sku and str(unit.get("contract_id", "")) == str(requirement.get("contract_id", "")) and int(unit.get("target_index",-1)) == int(requirement.get("target_index",0)):
				assigned_count += 1
		result.required = int(result.required) + maxi(0,needed-assigned_count)
	result.shortage = maxi(0,int(result.required)-int(result.available)-int(result.inbound))
	return result

func customer_stock_summary(sku: String = "") -> Dictionary:
	if not sku.is_empty() and not CUSTOMER_STOCK.known_sku(sku): return {"ok":false,"error":"sku","sku":sku}
	var requirements := _accepted_stock_requirements()
	var products: Array = [sku] if not sku.is_empty() else [CUSTOMER_STOCK.SKU,CUSTOMER_STOCK.BACKUP_SKU]
	var by_sku: Dictionary = {}
	for product_sku in products:
		by_sku[product_sku] = _customer_stock_sku_summary(product_sku,requirements)
	if not sku.is_empty(): return by_sku[sku]
	var summary := {"ok":true,"error":"","sku":"","capacity":CUSTOMER_STOCK.MAX_CAPACITY,"used":0,"cash":int(state.get("cash",0)),"inbound":0,"reserved":0,"reserved_inbound":0,"available":0,"delivered":0,"required":0,"shortage":0,"by_sku":by_sku}
	for product_sku in by_sku:
		var item: Dictionary = by_sku[product_sku]
		for key in ["used","inbound","available","reserved","reserved_inbound","delivered","required","shortage"]: summary[key] = int(summary[key]) + int(item.get(key,0))
	return summary

func customer_stock_boxes() -> Array:
	var result: Array = []
	for unit in customer_stock_units():
		if str(unit.status) not in ["ready","carried","stored","staged"]: continue
		var product := CUSTOMER_STOCK.product(str(unit.sku))
		result.append({"id":unit.id,"status":"carried" if str(unit.status)=="carried" else "ready","stock_state":unit.status,"visual_id":str(product.get("icon","backup")),"sku":unit.sku,"model":unit.model,"serial":unit.serial,"box_position":unit.box_position.duplicate(),"rotation_y":0.0})
	return result

func _customer_requirement(index: int = -1) -> Dictionary:
	var requirement: Dictionary = state.get("contract", {}).get("supply_requirement", {})
	var target := int(state.get("target_index",0)) if index < 0 else index
	return requirement if int(requirement.get("target_index",-1)) == target else {}

func _customer_hardware(index: int = -1) -> Dictionary:
	if _customer_requirement(index).is_empty(): return {}
	return CUSTOMER_STOCK.assigned(state, str(state.current_contract_id), int(state.get("target_index",0)) if index < 0 else index)

func _customer_hardware_connected(index: int = -1) -> bool:
	return _customer_requirement(index).is_empty() or str(_customer_hardware(index).get("status","")) in ["staged","delivered"]

func _customer_material_cost() -> int:
	var total := 0
	for unit in customer_stock_units():
		if not str(state.current_contract_id).is_empty() and str(unit.contract_id) == str(state.current_contract_id): total += int(unit.unit_cost)
	if total==0 and not state.get("contract",{}).get("supply_requirement",{}).is_empty():
		return int(CUSTOMER_STOCK.product(str(state.contract.supply_requirement.get("sku",CUSTOMER_STOCK.SKU))).get("unit_cost",CUSTOMER_STOCK.UNIT_COST))
	return total

func _colleague_hardware_connected(job: Dictionary) -> bool:
	var contract_id := str(job.get("contract_id",state.current_contract_id))
	var contract: Dictionary = state.get("contract",{}) if contract_id==str(state.current_contract_id) else state.get("contract_contexts",{}).get(contract_id,{}).get("contract",{})
	var requirement: Dictionary = contract.get("supply_requirement",{})
	if requirement.is_empty() or int(requirement.get("target_index",-1))!=int(job.get("target_index",0)): return true
	return str(CUSTOMER_STOCK.assigned(state,contract_id,int(requirement.target_index)).get("status","")) in ["staged","delivered"]

func _stock_transaction(action: Callable) -> Dictionary:
	var before := state.duplicate(true)
	var result: Dictionary = action.call()
	if not bool(result.get("ok",false)):
		state = before
		return result
	if not save_game():
		state = before; _machine = null; _machine_key = ""
		return {"ok":false,"error":"save"}
	changed.emit()
	return result

func _stock_preparation_transaction(action: Callable) -> Dictionary:
	# Preparation is a multi-step state transition: pickup, contract staging, and
	# saving the connected VM snapshot must succeed or roll back as one action.
	var prior_state: Dictionary = state.duplicate(true)
	var prior_assignments: Dictionary = _assignments.duplicate(true)
	var prior_machine = _machine
	var prior_machine_state: Dictionary = _machine.export_state() if _machine != null else {}
	var prior_machine_key: String = str(_machine_key)
	var result: Dictionary = action.call()
	if not bool(result.get("ok", false)):
		state = prior_state
		_assignments = prior_assignments
		_machine = prior_machine
		_machine_key = prior_machine_key
		if prior_machine != null: prior_machine.state = prior_machine_state.duplicate(true)
		return result
	if not save_game():
		state = prior_state
		_assignments = prior_assignments
		_machine = prior_machine
		_machine_key = prior_machine_key
		if prior_machine != null: prior_machine.state = prior_machine_state.duplicate(true)
		return {"ok":false,"error":"save"}
	changed.emit()
	return result

func _stock_held_by_other_unit(id: String) -> bool:
	for unit in customer_stock_units():
		if str(unit.get("status", "")) == "carried" and str(unit.get("id", "")) != id: return true
	for order in state.get("delivery_orders", []):
		if order is Dictionary and str(order.get("status", "")) in ["carried", "placing"]: return true
	return false

func procurement_cart() -> Dictionary:
	var cart := CUSTOMER_STOCK.empty_cart()
	var saved: Variant = state.get("procurement_cart", {})
	if saved is Dictionary:
		for sku in cart.keys(): cart[sku] = clampi(int(saved.get(sku,0)),0,3)
	return cart

func customer_cart_review() -> Dictionary:
	var cart := procurement_cart()
	var lines: Array = []
	var quantity := 0
	var total := 0
	for sku in cart.keys():
		var count := int(cart[sku]); if count <= 0: continue
		var product := CUSTOMER_STOCK.product(str(sku)); var unit_cost := int(product.get("unit_cost",0)); var line_total := unit_cost * count
		lines.append({"sku":str(sku),"quantity":count,"unit_cost":unit_cost,"total":line_total}); quantity += count; total += line_total
	var free_capacity := CUSTOMER_STOCK.MAX_CAPACITY - CUSTOMER_STOCK.active_count(state) - quantity
	var cash_after := int(state.get("cash",0)) - total
	var error := ""
	if not bool(state.get("career_mode",false)): error = "career"
	elif quantity <= 0: error = "empty"
	elif free_capacity < 0: error = "capacity"
	elif cash_after < 0: error = "cash"
	return {"ok":error.is_empty(),"error":error,"lines":lines,"total":total,"quantity":quantity,"cash_after":cash_after,"free_capacity":free_capacity}

func set_customer_cart(sku: String, quantity: int) -> Dictionary:
	if not CUSTOMER_STOCK.known_sku(sku): return {"ok":false,"error":"sku","cart":procurement_cart()}
	if quantity < 0 or quantity > 3: return {"ok":false,"error":"quantity","cart":procurement_cart()}
	var previous := state.duplicate(true)
	var cart := procurement_cart(); cart[sku] = quantity; state.procurement_cart = cart
	if not save_game():
		state = previous
		return {"ok":false,"error":"save","cart":procurement_cart()}
	changed.emit()
	return {"ok":true,"error":"","cart":cart.duplicate(true),"review":customer_cart_review()}

func buy_customer_cart() -> Dictionary:
	var cart := procurement_cart()
	var result := _stock_transaction(func():
		var purchased: Dictionary = CUSTOMER_STOCK.purchase_cart(state,cart)
		if bool(purchased.get("ok",false)): state.procurement_cart = CUSTOMER_STOCK.empty_cart()
		return purchased)
	if bool(result.get("ok",false)): result["cart"] = procurement_cart()
	return result

func buy_customer_stock(quantity: int, sku: String = CUSTOMER_STOCK.SKU) -> Dictionary:
	return _stock_transaction(func(): return CUSTOMER_STOCK.purchase(state,quantity,sku))

func store_customer_stock(id: String) -> Dictionary:
	return _stock_transaction(func(): return CUSTOMER_STOCK.store(state,id))

func stage_customer_stock(id: String) -> Dictionary:
	if not state.accepted or current_done() or _customer_requirement().is_empty(): return {"ok":false,"error":"contract"}
	if str(customer_stock_for(id).get("sku","")) != str(_customer_requirement().get("sku","")): return {"ok":false,"error":"sku"}
	return _stock_transaction(func():
		var result: Dictionary = CUSTOMER_STOCK.stage(state,id,str(state.current_contract_id),int(state.target_index))
		if bool(result.ok):
			_vm(); state.vm_states[_vm_key()] = _machine.export_state()
		return result)

func prepare_customer_stock(id: String) -> Dictionary:
	if not state.accepted or current_done() or _customer_requirement().is_empty(): return {"ok":false,"error":"contract"}
	var requirement: Dictionary = _customer_requirement()
	var unit: Dictionary = customer_stock_for(id)
	if unit.is_empty(): return {"ok":false,"error":"unknown"}
	if str(unit.get("sku", "")) != str(requirement.get("sku", "")): return {"ok":false,"error":"sku"}
	if not str(unit.get("contract_id", "")).is_empty() and (str(unit.get("contract_id", "")) != str(state.current_contract_id) or int(unit.get("target_index", -1)) != int(state.target_index)): return {"ok":false,"error":"contract"}
	var status := str(unit.get("status", ""))
	if status == "staged":
		if str(unit.get("contract_id", "")) != str(state.current_contract_id) or int(unit.get("target_index", -1)) != int(state.target_index): return {"ok":false,"error":"contract"}
		return {"ok":false,"error":"status"}
	if status not in ["ready", "stored", "carried"]: return {"ok":false,"error":"status"}
	if _stock_held_by_other_unit(id): return {"ok":false,"error":"held"}
	return _stock_preparation_transaction(func() -> Dictionary:
		if str(CUSTOMER_STOCK.unit(state, id).get("status", "")) != "carried":
			var taken: Dictionary = CUSTOMER_STOCK.take(state, id)
			if not bool(taken.get("ok", false)): return taken
		var staged: Dictionary = CUSTOMER_STOCK.stage(state, id, str(state.current_contract_id), int(state.target_index))
		if not bool(staged.get("ok", false)): return staged
		_vm()
		state.vm_states[_vm_key()] = _machine.export_state()
		return staged)

func dispatch_customer_stock(id: String) -> Dictionary:
	var unit := customer_stock_for(id)
	if not state.accepted or current_done() or _customer_requirement().is_empty() or str(unit.get("contract_id","")) != str(state.current_contract_id) or int(unit.get("target_index",-1)) != int(state.target_index): return {"ok":false,"error":"contract"}
	if not state.inspected or int(state.validated_revision) != int(state.revision) or state.checks.is_empty(): return {"ok":false,"error":"checks"}
	for job in _assignments.values():
		if str(job.get("status",""))=="working" and str(job.get("contract_id",""))==str(state.current_contract_id): return {"ok":false,"error":"checks"}
	for check in _vm_checks():
		if not bool(check.get("hardware",false)) and not bool(check.get("passed",false)): return {"ok":false,"error":"checks"}
	return _stock_transaction(func(): return CUSTOMER_STOCK.dispatch(state,id))

func ship_prepared_customer_stock(id: String) -> Dictionary:
	var requirement: Dictionary = _customer_requirement()
	var unit: Dictionary = customer_stock_for(id)
	if not state.accepted or current_done() or requirement.is_empty() or unit.is_empty(): return {"ok":false,"error":"contract"}
	if str(unit.get("sku", "")) != str(requirement.get("sku", "")): return {"ok":false,"error":"sku"}
	if str(unit.get("contract_id", "")) != str(state.current_contract_id) or int(unit.get("target_index", -1)) != int(state.target_index): return {"ok":false,"error":"contract"}
	if str(unit.get("status", "")) not in ["staged", "carried"]: return {"ok":false,"error":"status"}
	if _stock_held_by_other_unit(id): return {"ok":false,"error":"held"}
	if not state.inspected or int(state.validated_revision) != int(state.revision) or state.checks.is_empty(): return {"ok":false,"error":"checks"}
	for job in _assignments.values():
		if str(job.get("status", "")) == "working" and str(job.get("contract_id", "")) == str(state.current_contract_id): return {"ok":false,"error":"checks"}
	for check in _vm_checks():
		if not bool(check.get("hardware", false)) and not bool(check.get("passed", false)): return {"ok":false,"error":"checks"}
	return _stock_preparation_transaction(func() -> Dictionary:
		if str(CUSTOMER_STOCK.unit(state, id).get("status", "")) != "carried":
			var taken: Dictionary = CUSTOMER_STOCK.take(state, id)
			if not bool(taken.get("ok", false)): return taken
		return CUSTOMER_STOCK.dispatch(state, id))

func _stock_carried() -> bool:
	return customer_stock_units().any(func(unit): return str(unit.status)=="carried")

func _put_down_stock(id: String, position: Array) -> Dictionary:
	if position.size()!=3: return {"ok":false,"error":"position"}
	for coordinate in position:
		if typeof(coordinate) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(coordinate)): return {"ok":false,"error":"position"}
	if absf(float(position[0]))>6.0 or absf(float(position[2]))>4.6 or float(position[1])<0.0 or float(position[1])>2.0: return {"ok":false,"error":"position"}
	return _stock_transaction(func():
		var unit: Dictionary = CUSTOMER_STOCK.unit(state,id)
		if unit.is_empty() or str(unit.status)!="carried": return {"ok":false,"error":"status"}
		unit.status="ready"; unit.box_position=[float(position[0]),0.16,float(position[2])]
		return {"ok":true,"error":""})

func set_delivery_clock_enabled(enabled: bool) -> void:
	_delivery_clock_enabled = enabled

func set_delivery_clock_paused(paused: bool) -> void:
	_delivery_clock_paused = paused

func advance_delivery(delta_seconds: float) -> bool:
	if _delivery_clock_paused or not is_finite(delta_seconds) or delta_seconds <= 0.0: return false
	var old_orders: Array = state.get("delivery_orders", []).duplicate(true)
	var old_stock: Dictionary = state.get("customer_stock", {}).duplicate(true)
	var changed_order := false
	var progress_saved := false
	for order in state.get("delivery_orders", []):
		if str(order.get("status", "")) != "queued": continue
		var previous_second := int(floor(float(order.get("elapsed_seconds", 0.0))))
		order.elapsed_seconds = minf(DELIVERY_WAIT_SECONDS, float(order.get("elapsed_seconds", 0.0)) + delta_seconds)
		if int(floor(float(order.elapsed_seconds))) > previous_second: progress_saved = true
		if float(order.elapsed_seconds) >= DELIVERY_WAIT_SECONDS:
			order.status = "ready"
			order.box_position = _delivery_box_position(str(order.get("id", "")))
			order.ordered_at_seconds = Time.get_ticks_msec() / 1000.0
			changed_order = true
	var stock_result: Dictionary = CUSTOMER_STOCK.advance(state,delta_seconds)
	changed_order = changed_order or bool(stock_result.arrived)
	if bool(stock_result.progressed):
		for index in state.customer_stock.units.size():
			if int(floor(float(state.customer_stock.units[index].elapsed_seconds))) != int(floor(float(old_stock.units[index].elapsed_seconds))): progress_saved = true
	if changed_order or progress_saved:
		if not save_game():
			state.delivery_orders = old_orders; state.customer_stock = old_stock
			return false
		if changed_order:
			notified.emit(UI_COPY.copy("delivery_arrived")); changed.emit()
	return changed_order

func _has_uninstalled_order(id: String) -> bool:
	for order in state.get("delivery_orders", []):
		if str(order.get("id", "")) == id and str(order.get("status", "")) in ["queued", "ready", "carried", "placing"]:
			return true
	return false

func care_portfolio() -> Dictionary:
	var capacity := 2 + int(state.skills.get("operations", 0))
	if "monitor" in state.equipment: capacity += 2
	if "teamdesk" in state.equipment: capacity += 2
	if "annexdesk_a" in state.equipment: capacity += 1
	if "annexdesk_b" in state.equipment: capacity += 1
	var clients: Array = []
	var gross := 0
	var active_count := 0
	var pending_count := 0
	for client in state.get("care_agreements", {}).keys():
		var name := str(client)
		var agreement: Dictionary = state.care_agreements[name]
		var relation: Dictionary = state.customer_relations.get(name, {"satisfaction":70})
		var satisfaction := clampi(int(relation.get("satisfaction", 70)), 0, 100)
		var active := bool(agreement.get("active", true)) and satisfaction >= 40
		var fee := int(agreement.get("fee", 150))
		var status := "active" if active else ("pending" if bool(agreement.get("pending",false)) else "suspended")
		clients.append({"client":name,"fee":fee,"cost":100,"satisfaction":satisfaction,"status":status})
		if active: active_count += 1; gross += fee
		elif status == "pending": pending_count += 1
	return {"capacity":capacity,"active_count":active_count,"pending_count":pending_count,"reserved_count":active_count + pending_count,"gross_daily":gross,"service_cost_daily":active_count * 100,"net_daily":gross - active_count * 100,"clients":clients}

func _maintenance_job_for(client: String, day: int = -1) -> Dictionary:
	var wanted_day := int(state.day) if day < 0 else day
	for item in state.get("maintenance_jobs", []):
		if str(item.get("client", "")) == client and int(item.get("day", -1)) == wanted_day: return item
	return {}

func _maintenance_targets_for(client: String) -> Array:
	var value = state.get("maintenance_targets", {}).get(client, [])
	return MAINTENANCE_SCOPE.normalize(value) if value is Array else []

func maintenance_owner(client: String) -> String:
	return MAINTENANCE_DISPATCH.owner(self,client)

func maintenance_owner_candidates() -> Array:
	return MAINTENANCE_DISPATCH.candidates(self)

func set_maintenance_owner(client: String,member_id: String) -> bool:
	var saved:=MAINTENANCE_DISPATCH.set_owner(self,client,member_id)
	if not saved:notified.emit(UI_COPY.copy("staffing_save_failed"))
	return saved

func _capture_maintenance_targets(client: String) -> Array:
	_sync_target()
	var targets: Array = []
	for index in state.get("targets", []).size():
		var key := _vm_key(index)
		var saved: Dictionary = state.get("vm_states", {}).get(key, {}).duplicate(true)
		if index == int(state.get("target_index", 0)) and _machine != null and _machine_key == key: saved = _machine.export_state()
		if saved.is_empty(): return []
		targets.append({"asset_id":str(state.targets[index].get("maintenance_asset_id","")),"chapter":_current_chapter(index),"vm_key":key,"vm_state":saved,"scenario":_scenario(index).duplicate(true)})
	return MAINTENANCE_SCOPE.normalize(targets)

func _ensure_maintenance_job(client: String, day: int = -1) -> Dictionary:
	var wanted_day := int(state.day) if day < 0 else day
	var existing := _maintenance_job_for(client, wanted_day)
	if not existing.is_empty(): return existing
	var agreement: Dictionary = state.care_agreements.get(client, {})
	var fee := int(agreement.get("fee", 150))
	var job := {"id":"maintenance-%s-%d" % [client,wanted_day],"client":client,"day":wanted_day,"status":"pending","assignee":"","remaining":12.0,"total":12.0,"fee":fee,"cost":100,"minutes":12.0,"result":"","paid":false,"missed_day":-1,"targets":_maintenance_targets_for(client)}
	state.maintenance_jobs.append(job)
	return job

func _prepare_maintenance_day() -> void:
	# An unfinished inspection carries its remaining effort forward. The previous
	# day was settled as missed; only the day it actually finishes can earn a fee.
	for queue in _dispatch_queue_map().values():
		for queued in queue:
			if str(queued.get("kind","normal")) != "maintenance": continue
			var source_id:=str(queued.get("maintenance_job_id",""))
			for stored in state.get("maintenance_jobs",[]):
				if str(stored.get("id",""))!=source_id or int(stored.get("day",state.day))>=int(state.day): continue
				stored.day=int(state.day); stored.paid=false; stored.status=str(queued.status)
				stored.targets=_maintenance_targets_for(str(stored.client)).duplicate(true)
				stored.remaining=float(queued.remaining); stored.fee=int(state.care_agreements.get(str(stored.client),{}).get("fee",stored.get("fee",0)))
	for account in care_portfolio().clients:
		var name := str(account.client)
		if (str(account.status) == "active" or str(state.care_incidents.get(name,{}).get("status","")) == "recheck") and not _maintenance_targets_for(name).is_empty(): _ensure_maintenance_job(name)

func maintenance_jobs() -> Array:
	_prepare_maintenance_day()
	var out: Array = []
	for item in state.get("maintenance_jobs", []):
		if int(item.get("day", -1)) != int(state.day) and str(item.get("status", "")) != "legacy": continue
		out.append({"id":str(item.get("id","")),"client":str(item.get("client","")),"status":str(item.get("status","")),"assignee":str(item.get("assignee","")),"remaining":float(item.get("remaining",0.0)),"total":float(item.get("total",12.0)),"fee":int(item.get("fee",0)),"cost":int(item.get("cost",100)),"minutes":float(item.get("minutes",12.0)),"result":str(item.get("result",""))})
	for client in state.get("care_agreements", {}).keys():
		var name := str(client); var agreement: Dictionary = state.care_agreements[name]
		if bool(agreement.get("maintenance_legacy", false)) and bool(agreement.get("active", false)) and _maintenance_job_for(name).is_empty():
			out.append({"id":"maintenance-legacy-"+name,"client":name,"status":"legacy","assignee":"","remaining":0.0,"total":0.0,"fee":int(agreement.get("fee",150)),"cost":100,"minutes":0.0,"result":UI_COPY.copy("care_status_legacy")})
	return out

func maintenance_summary() -> Dictionary:
	_prepare_maintenance_day()
	var pending := 0; var working := 0; var done := 0; var failed := 0; var legacy := 0; var earned := 0; var cost := 0
	var active_clients: Array[String] = []
	for account in care_portfolio().clients:
		if str(account.status) == "active": active_clients.append(str(account.client))
	for item in state.get("maintenance_jobs", []):
		if int(item.get("day", -1)) != int(state.day): continue
		if str(item.get("client", "")) not in active_clients: continue
		match str(item.get("status", "")):
			"pending", "queued", "paused": pending += 1
			"working": working += 1
			"done":
				done += 1; earned += int(item.get("fee",0))
			"failed": failed += 1
			"legacy": legacy += 1
	for client in state.get("care_agreements", {}).keys():
		var agreement: Dictionary = state.care_agreements[client]
		if str(client) not in active_clients: continue
		cost += 100
		if bool(agreement.get("maintenance_legacy", false)) or _maintenance_targets_for(str(client)).is_empty():
			legacy += 1; earned += int(agreement.get("fee",150))
	return {"pending":pending,"working":working,"done":done,"failed":failed,"legacy":legacy,"earned":earned,"service_cost":cost,"net":earned-cost}

func maintenance_end_day_reason() -> String:
	for item in _assignments.values():
		if str(item.get("status","")) == "working" and str(item.get("kind","normal")) == "maintenance": return UI_COPY.copy("care_end_day_busy")
	return ""

func _run_maintenance_job(job: Dictionary) -> Dictionary:
	var lines: Array[String] = []
	var all_passed := true; var targets: Array = job.get("targets", [])
	if targets.is_empty(): return {"passed":false,"log":"NO_TARGETS"}
	for target in targets:
		var machine = load("res://scripts/virtual_machine.gd").new()
		machine.setup(int(target.get("chapter",0)), target.get("vm_state",{}).duplicate(true), target.get("scenario",{}).duplicate(true))
		_bind_maintenance_business(machine, targets)
		if machine.has_method("set_identity"): machine.set_identity(profile())
		lines.append("["+str(target.get("vm_key","site"))+"] $ ssh client")
		lines.append(str(machine.run("ssh client")))
		var target_passed := false
		for round_index in 3:
			var probes: Array = machine.probes()
			probes.sort_custom(func(a,b):
				var ac := str(a.get("command", "")).to_lower(); var bc := str(b.get("command", "")).to_lower()
				var am := ac.contains(" put ") or ac.contains(" backup ") or ac.contains(" restore ") or ac.begins_with("cp ")
				var bm := bc.contains(" put ") or bc.contains(" backup ") or bc.contains(" restore ") or bc.begins_with("cp ")
				return am and not bm)
			for probe in probes:
				var command := str(probe.get("command", "")); var response: String = str(machine.run(command))
				lines.append("$ "+command); lines.append(response)
			target_passed = true
			for probe_after in machine.probes():
				if not (bool(probe_after.get("recorded", false)) and bool(probe_after.get("fresh", false)) and bool(probe_after.get("passed", false))): target_passed = false
			for result in machine.evaluate():
				if not bool(result): target_passed = false; break
			if target_passed: break
		target.vm_state = machine.export_state()
		if not target_passed: all_passed = false
	var passed := all_passed
	return {"passed":passed,"log":"%s\n%s" % ["PASS" if passed else "FAIL", "\n".join(lines)]}

func _finish_maintenance(member_id: String, job: Dictionary) -> void:
	var previous_state: Dictionary = state.duplicate(true); var previous_assignments := _assignments.duplicate(true)
	var result := _run_maintenance_job(job)
	var job_id := str(job.get("maintenance_job_id", job.get("id", ""))); var stored: Dictionary = job
	for candidate in state.maintenance_jobs:
		if str(candidate.get("id", "")) == job_id: stored = candidate; break
	stored.targets = job.get("targets", []).duplicate(true)
	CARE.record_check(self, stored, result)
	stored.status = "done" if bool(result.passed) else "failed"; stored.remaining = 0.0; stored.result = str(result.log); stored.assignee = member_id; stored.phase = UI_COPY.copy("care_maintenance_done") if bool(result.passed) else UI_COPY.copy("care_maintenance_failed")
	_account_crew_minutes(member_id,job,true)
	_assignments[member_id] = {"status":str(stored.status),"kind":"maintenance","client":str(stored.get("client","")),"remaining":0.0,"total":float(stored.get("total",12.0)),"work_minutes":float(stored.get("minutes",12.0)),"phase":str(stored.get("phase","")),"result":str(stored.get("result","")),"job_id":job_id}
	state.assignments = _assignments.duplicate(true)
	if not save_game(): state = previous_state; _assignments = previous_assignments; return
	changed.emit()

func _advance_maintenance_clock(minutes: float) -> void:
	state.clock_minutes = clock_minutes() + int(round(minutes))

func care_incident(client: String) -> Dictionary:
	return CARE.visible(self, client.strip_edges())

func maintenance_incident_reason(client: String) -> String:
	return CARE.reason(self, client.strip_edges())

func open_maintenance_incident(client: String) -> bool:
	return CARE.open_ticket(self, client.strip_edges())

func can_run_maintenance(client: String) -> bool:
	var name := client.strip_edges()
	var job := _maintenance_job_for(name)
	var status := str(state.care_incidents.get(name, {}).get("status", ""))
	if job.is_empty() or str(job.get("status", "")) != "pending" or _maintenance_targets_for(name).is_empty() or status == "working": return false
	return status == "recheck" or (bool(state.care_agreements.get(name, {}).get("active", false)) and int(state.customer_relations.get(name, {}).get("satisfaction", 70)) >= 40)

func run_maintenance(client: String) -> bool:
	_prepare_maintenance_day()
	var name := client.strip_edges(); var job := _maintenance_job_for(name)
	if not can_run_maintenance(name): return false
	if job.is_empty() or str(job.get("status","")) != "pending" or _maintenance_targets_for(name).is_empty(): return false
	var previous_state := state.duplicate(true); var previous_assignments := _assignments.duplicate(true); var previous_machine = _machine; var previous_machine_key := _machine_key
	job.status = "working"; job.assignee = "player"; job.remaining = 0.0
	var result := _run_maintenance_job(job); job.status = "done" if bool(result.passed) else "failed"; job.result = str(result.log); job.phase = UI_COPY.copy("care_maintenance_done") if bool(result.passed) else UI_COPY.copy("care_maintenance_failed")
	CARE.record_check(self, job, result)
	_advance_maintenance_clock(float(job.minutes))
	if not save_game(): state = previous_state; _assignments = previous_assignments; _machine = previous_machine; _machine_key = previous_machine_key; return false
	changed.emit(); return true

func assign_maintenance(client: String, member_id: String) -> bool:
	if _dispatch_duplicate(member_id,"maintenance","",-1,client.strip_edges()): return false
	_prepare_maintenance_day()
	var name := client.strip_edges(); var job := _maintenance_job_for(name)
	if not can_run_maintenance(name): return false
	if job.is_empty() or str(job.get("status","")) != "pending" or not staff_availability(member_id,"maintenance").is_empty(): return false
	var previous_state := state.duplicate(true); var previous_assignments := _assignments.duplicate(true)
	var duration := 8.0 if colleague_role(member_id) == "maintenance" else 12.0
	job.status = "working"; job.assignee = member_id; job.remaining = duration; job.total = duration; job.minutes = duration; job.kind = "maintenance"
	_assignments[member_id] = job.duplicate(true); state.assignments = _assignments.duplicate(true)
	if _dispatch_transaction: return true
	if not save_game(): state = previous_state; _assignments = previous_assignments; return false
	changed.emit(); return true

func maintenance_result(client: String) -> String:
	var job := _maintenance_job_for(client.strip_edges())
	return str(job.get("result", "")) if not job.is_empty() else ""

func _retain_maintenance_assignments() -> void:
	var kept := {}
	for id in _assignments.keys():
		var item: Dictionary = _assignments[id]
		if str(item.get("kind", "normal")) == "maintenance" and str(item.get("status", "")) == "working": kept[id] = item
	_assignments = kept
	state.assignments = _assignments.duplicate(true)

func care_eligibility(client: String) -> String:
	var name := client.strip_edges()
	if str(state.get("care_incidents",{}).get(name,{}).get("status","")) in ["latent","detected","working","recheck"]: return UI_COPY.copy("care_incident_working")
	if name.is_empty(): return "顧客名未設定"
	if state.care_agreements.has(name):
		var relation: Dictionary = state.customer_relations.get(name, {"satisfaction":70})
		if int(relation.get("satisfaction", 70)) < 40: return "顧客満足度が40未満のため、満足度回復まで保守契約を再開できません。"
		if bool(state.care_agreements[name].get("active", false)) or bool(state.care_agreements[name].get("pending", false)): return ""
	var portfolio := care_portfolio()
	if int(portfolio.reserved_count) >= int(portfolio.capacity): return "保守契約枠が上限です。設備または運用スキルで枠を増やしてください。"
	return ""

func care_terms(client: String) -> Dictionary:
	var name := client.strip_edges()
	var existing: Dictionary = state.care_agreements.get(name, {})
	var fee := int(existing.get("fee", 150 + 600 * int(state.skills.operations)))
	return {"fee":fee,"cost":100,"net":fee - 100,"active":bool(existing.get("active",false)),"reason":care_eligibility(name)}

func _agree_care(client: String) -> bool:
	var terms := care_terms(client)
	var reason := str(terms.reason)
	if not reason.is_empty(): return false
	var relation: Dictionary = state.customer_relations.get(client, {"satisfaction":70,"completed_count":0,"last_quality":"","last_day":0})
	state.customer_relations[client] = relation
	var existing: Dictionary = state.care_agreements.get(client, {})
	var renewed := existing.duplicate(true)
	renewed["fee"] = int(terms.fee); renewed["active"] = bool(existing.get("active", false)); renewed["pending"] = true; renewed["agreed_day"] = int(existing.get("agreed_day", state.day)); renewed["grandfathered"] = bool(existing.get("grandfathered", false))
	state.care_agreements[client] = renewed
	return true

func _activate_care(client: String) -> void:
	if not state.care_agreements.has(client): return
	var agreement: Dictionary = state.care_agreements[client]
	agreement.active = true; agreement.pending = false
	state.care_agreements[client] = agreement
	if client not in state.recurring_clients: state.recurring_clients.append(client)

func _suspend_care(client: String) -> void:
	if not state.care_agreements.has(client): return
	var agreement: Dictionary = state.care_agreements[client]
	agreement.active = false; agreement.pending = false
	state.care_agreements[client] = agreement
	state.recurring_clients.erase(client)

func take_delivery(id: String) -> bool:
	if id.begins_with("stock-"): return bool(_stock_transaction(func(): return CUSTOMER_STOCK.take(state,id)).ok)
	if _stock_carried(): return false
	for existing in state.get("delivery_orders", []):
		if str(existing.get("status", "")) in ["carried", "placing"]: return false
	for order in state.get("delivery_orders", []):
		if str(order.get("id", "")) == id and str(order.get("status", "")) == "ready":
			var old: Array = state.delivery_orders.duplicate(true)
			order.status = "carried"
			if save_game():
				changed.emit(); return true
			state.delivery_orders = old
	return false

func begin_delivery_placement(id: String) -> bool:
	for order in state.get("delivery_orders", []):
		if str(order.get("id", "")) == id and str(order.get("status", "")) == "carried":
			order.status = "placing"
			if save_game(): changed.emit(); return true
			order.status = "carried"
	return false

func rotate_delivery(id: String, quarter_turns: float = 1.0) -> bool:
	for order in state.get("delivery_orders", []):
		if str(order.get("id", "")) == id and str(order.get("status", "")) == "placing":
			var previous_rotation := float(order.get("rotation_y",0.0))
			order.rotation_y = fposmod(float(order.get("rotation_y", 0.0)) + (PI / 2.0) * quarter_turns, TAU)
			if save_game(): changed.emit(); return true
			order.rotation_y = previous_rotation
	return false

func put_down_delivery(id: String, position: Array = []) -> bool:
	if id.begins_with("stock-"): return bool(_put_down_stock(id,position).ok)
	if bool(delivery_for(id).get("moving_installed",false)): return cancel_equipment_move(id)
	for order in state.get("delivery_orders", []):
		if str(order.get("id", "")) == id and str(order.get("status", "")) in ["carried", "placing"]:
			var old: Array = state.delivery_orders.duplicate(true)
			order.status = "ready"
			if not position.is_empty(): order.box_position = position.duplicate()
			if save_game():
				changed.emit(); return true
			state.delivery_orders = old
	return false

func place_delivery(id: String, slot: int, rotation_y: float = 0.0) -> bool:
	if not is_finite(rotation_y): return false
	if not equipment_unavailable_reason(id).is_empty(): return false
	if slot < 0 or slot >= 8 or slot != equipment_slot(id): return false
	if id == "monitor":
		var legacy_place := PLACEMENT_RULES.legacy_monitor_placement()
		return place_delivery_at(id,legacy_place.position,legacy_place.rotation_y)
	for order in state.get("delivery_orders", []):
		if str(order.get("id", "")) != id or str(order.get("status", "")) not in ["carried", "placing"]: continue
		for other in state.delivery_orders:
			if int(other.get("install_slot", -1)) == slot and str(other.get("status", "")) == "installed": return false
		var old_orders: Array = state.delivery_orders.duplicate(true)
		var old_equipment: Array = state.equipment.duplicate(true)
		order.status = "installed"; order.install_slot = slot; order.rotation_y = fposmod(rotation_y, TAU)
		var fixed: Vector2 = PLACEMENT_RULES.FIXED_SLOTS.get(id, Vector2.ZERO)
		order.install_position = [fixed.x, 0.0, fixed.y]
		order.erase("moving_installed"); order.erase("move_origin_rotation")
		if id not in state.equipment: state.equipment.append(id)
		if save_game():
			notified.emit(UI_COPY.copy("delivery_installed"))
			changed.emit(); return true
		state.delivery_orders = old_orders; state.equipment = old_equipment
	return false

func begin_equipment_move(id: String) -> bool:
	if _stock_carried(): return false
	if id not in state.equipment: return false
	if has_method("staff_workplace"):
		for member in team_members():
			if str(staff_workplace(str(member.get("id","")))) != id: continue
			var assignment: Dictionary = state.get("assignments",{}).get(str(member.get("id","")),{})
			if str(assignment.get("status","")) == "working": return false
			if bool(member.get("hired",false)):
				var shift: Dictionary=STAFF_SHIFTS.get(str(member.get("shift","day")),STAFF_SHIFTS.day)
				if clock_minutes()>=int(shift.start) and clock_minutes()<int(shift.end):return false
	for order in state.delivery_orders:
		if str(order.get("status","")) in ["carried","placing"]: return false
	var old_orders: Array = state.delivery_orders.duplicate(true)
	for order in state.delivery_orders:
		if str(order.get("id","")) != id or str(order.get("status","")) != "installed": continue
		order.status="placing"; order.moving_installed=true; order.move_origin_rotation=float(order.get("rotation_y",0.0))
		if save_game(): changed.emit(); return true
		state.delivery_orders=old_orders; return false
	return false

func cancel_equipment_move(id: String) -> bool:
	var old_orders: Array=state.delivery_orders.duplicate(true)
	for order in state.delivery_orders:
		if str(order.get("id","")) != id or not bool(order.get("moving_installed",false)): continue
		order.status="installed"; order.rotation_y=float(order.get("move_origin_rotation",0.0))
		order.erase("moving_installed"); order.erase("move_origin_rotation")
		if save_game(): changed.emit(); return true
		state.delivery_orders=old_orders; return false
	return false

func place_delivery_at(id: String, position: Array, rotation_y: float) -> bool:
	if not equipment_unavailable_reason(id).is_empty(): return false
	if id not in ["monitor","plant","backup","diagnostic","workstation","teamdesk","annexdesk_a","annexdesk_b"]: return false
	if not is_finite(rotation_y) or position.size() != 3: return false
	for coordinate in position:
		if typeof(coordinate) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(coordinate)): return false
	if id == "monitor":
		if not PLACEMENT_RULES.monitor_position_error(position,rotation_y,state.delivery_orders,office_expanded()).is_empty(): return false
	else:
		if absf(float(position[1])) > 0.01: return false
		if not PLACEMENT_RULES.position_error(id,position,rotation_y,state.delivery_orders,office_expanded()).is_empty(): return false
	var old_orders: Array=state.delivery_orders.duplicate(true); var old_equipment: Array=state.equipment.duplicate()
	for order in state.delivery_orders:
		if str(order.get("id","")) != id or str(order.get("status","")) not in ["carried","placing"]: continue
		order.status="installed"; order.install_slot=equipment_slot(id); order.install_position=[float(position[0]),float(position[1]) if id == "monitor" else 0.0,float(position[2])]; order.rotation_y=fposmod(rotation_y,TAU)
		order.erase("moving_installed"); order.erase("move_origin_rotation")
		if id not in state.equipment: state.equipment.append(id)
		if save_game(): changed.emit(); return true
		state.delivery_orders=old_orders; state.equipment=old_equipment; return false
	return false

func buy_equipment(id: String) -> bool:
	if not equipment_unavailable_reason(id).is_empty(): return false
	for item in equipment_catalog():
		var price := equipment_price(id)
		if item.id == id and id not in state.equipment and not _has_uninstalled_order(id) and int(state.cash) >= price:
			var old_cash := int(state.cash)
			var old_orders: Array = state.delivery_orders.duplicate(true)
			var old_history: Array = state.history.duplicate(true)
			state.cash = old_cash - price; state.delivery_orders.append(_new_delivery_order(id, price))
			state.history.append({"kind":"investment","day":int(state.day),"equipment_id":id,"amount":price})
			if save_game(): changed.emit(); return true
			state.cash = old_cash; state.delivery_orders = old_orders; state.history=old_history
			notified.emit("設備の購入を保存できませんでした。残高は元に戻しました。")
			return false
	return false

func export_report(dir: String = "user://reports") -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "/security-lab-report.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return ""
	f.store_string("WHITE HAT LAB / 営業記録\n会社: %s\n担当: %s\nチーム: %s / %s\n累計利益 ¥%d / 信用 %d\n専門分野 %s\n\n" % [company_name(),player_name(),member_name("aya"),member_name("ren"),state.profit, state.credit, JSON.stringify(state.skills)])
	for row in state.history:
		var title := str(row.get("title","")); var reward := int(row.get("reward",0)); var expense := int(row.get("expense",0)); var profit := int(row.get("profit",reward-expense))
		if str(row.get("kind","")) in ["staff_cost","payroll"]:
			title = UI_COPY.copy("staffing_hire") if str(row.kind)=="staff_cost" else UI_COPY.copy("staffing_daily_cost") % int(row.get("amount",0))
			title += " / "+member_name(str(row.get("staff_id","")))
		elif str(row.get("id","")).begins_with("retainer-day-"):
			title = UI_COPY.copy("care_title"); reward = int(row.get("retainer_gross",0)); expense = int(row.get("retainer_cost",0)); profit = int(row.get("retainer_net",reward-expense))
		f.store_string("Day %d / %s\n報酬 ¥%d / 経費 ¥%d / 利益 ¥%d / 継続収入 ¥%d\n" % [int(row.get("day",0)), title, reward, expense, profit, int(row.get("retainer",0))])
		for check in row.get("checks",[]): f.store_string("  %s %s\n" % ["PASS" if check.passed else "FAIL", check.label])
		f.store_string("\n")
	f.close()
	return ProjectSettings.globalize_path(path)
