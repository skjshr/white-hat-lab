extends RefCounted
## A conversation projected from this exact saved delivery. Never reads a VM.
const UI = preload("res://scripts/ui_theme.gd")
const BLUE := Color("0f6cbd")
const INK := Color("243641")
const MUTED := Color("64777b")

static func project(state: Dictionary, record: Dictionary) -> Dictionary:
	var id := str(record.get("id", ""))
	var own := delivery_for(state,id)
	var identity: bool = not own.is_empty() and (str(own.get("client","" )).is_empty() or str(own.get("client","")) == str(record.get("client",""))) and str(own.get("case_id",own.get("copy_id",""))) == str(record.get("case_id",record.get("copy_id","")))
	var completed: bool = identity and not id.is_empty() and id in state.get("completed_ids", []) and str(record.get("kind", "delivery")) == "delivery"
	var checks: Array = record.get("checks", []).duplicate(true)
	var confirmed := completed and not checks.is_empty() and checks.all(func(row): return row is Dictionary and bool(row.get("passed",false)))
	var reply := {"id":id,"completed":completed,"confirmed":confirmed,"client":str(record.get("client","")),"day":int(record.get("day",0)),"case_id":str(record.get("case_id",record.get("copy_id",""))),"rating":str(record.get("rating","")),"checks":checks,"before":record.get("satisfaction_before",null),"after":record.get("satisfaction_after",null),"event":{},"report_write_confirmed":false,"evidence_source":"none","body":"納品の記録を受け取りました。確認の内訳は記録されていません。" if completed else "返答の記録がありません。"}
	var results: Array=own.get("delivery_results",[])
	if completed and own.has("delivery_results"): reply.evidence_source="delivery-history"
	elif completed:
		var context: Dictionary=state.get("contract_contexts",{}).get(id,{})
		var receipt: Dictionary=context.get("last_receipt",{})
		if bool(context.get("completed",false)) and str(receipt.get("client",""))==str(reply.client) and str(receipt.get("case_id",""))==str(reply.case_id):
			results=receipt.get("delivery_results",[]); reply.evidence_source="own-retained-receipt"
	if completed:
		for site in results:
			for probe in site.get("probes",[]):
				if str(probe.get("id",""))=="staff-write" and bool(probe.get("recorded",false)) and bool(probe.get("passed",false)) and str(probe.get("command","" )).contains("/srv/data/report.txt") and str(probe.get("result",""))=="putting file report.txt: OK": reply.report_write_confirmed=true
	if confirmed:
		reply.body = "対応内容の受取を確認しました。"
		var saas: Dictionary = own.get("saas_outcome", {})
		if str(reply.case_id) == "advanced-saas-response" and not saas.is_empty():
			var lost: int = saas.get("egress", {}).get("exported_rows", []).size()
			var invoice: Dictionary = saas.get("invoice", {})
			reply.body = "連携の同意と発行済み接続の取消、既存接続からの取得拒否を確認しました。"
			reply.body += "\n予定同期による持出しはありませんでした。" if lost == 0 else "\n外部へ持ち出された延べ%d行の記録は消せません。補償費用¥%dと影響報告を受領しました。" % [lost, int(saas.get("costs", {}).get("impact_cost", 0))]
			reply.body += "\n請求 %s / 受付 %s を確認しました。" % [str(invoice.get("id", "")), str(invoice.get("receipt_id", ""))]
			if invoice.get("attempts", []).any(func(attempt): return int(attempt.get("status", 0)) >= 400): reply.body += "\n途中で未受付になった請求も、同じ原票から復旧できています。"
		var pentest_changes: Dictionary = own.get("pentest_changes", {})
		if str(reply.case_id) == "advanced-pentest" and not pentest_changes.get("requests", []).is_empty():
			var requests: Array = pentest_changes.requests
			reply.body = "%sまでの変更依頼%d件を確認しました。公開設定の閲覧制限と旧資格情報の失効、日報を利用できることを再診断いただきました。\n変更作業費は合計¥%sです。" % [str(requests.back().get("id", "")), requests.size(), str(int(pentest_changes.get("cost_total", 0)))]
			if requests.any(func(change): return str(change.get("change", "")) == "isolate_share"):
				reply.body += "\n途中で共有全体を停止したため、日報も利用できない時間がありました。"
		if str(reply.case_id) == "advanced-pentest-relay" and str(pentest_changes.get("engagement", "")) == "relay-v1":
			var requests: Array = pentest_changes.get("requests", [])
			var shipping: Dictionary = pentest_changes.get("shipping", {})
			var accepted: Array[String] = []
			var delayed: Array[String] = []
			for order in shipping.get("orders", []):
				if bool(order.get("delivered", false)):
					var receipt_id := str(order.get("receipt", {}).get("id", ""))
					accepted.append(str(order.get("id", "")) + ("（" + receipt_id + "）" if not receipt_id.is_empty() else ""))
				if order.get("attempts", []).any(func(attempt): return int(attempt.get("status", 0)) == 503): delayed.append(str(order.get("id", "")))
			reply.body = "中継サーバーから内部へ届く経路の報告と、修正後の再診断を受領しました。"
			if not accepted.is_empty(): reply.body += "\n出荷受付の控え: " + "・".join(accepted) + "。"
			if not requests.is_empty(): reply.body += "\n変更依頼は%sまでの%d件、作業費は合計¥%sです。" % [str(requests.back().get("id", "")), requests.size(), str(int(pentest_changes.get("cost_total", 0)))]
			if not delayed.is_empty(): reply.body += "\n" + "・".join(delayed) + "が中継停止で受付できなかった記録も残っています。"
		if str(reply.case_id) == "service-0-case-0" and bool(reply.report_write_confirmed): reply.body = "日報の保存を確認しました。締めの作業を再開します。"
		for site in own.get("hotel_workflow", {}).get("sites", []):
			if str(site.get("status", "")) != "received": continue
			if int(site.get("workflow_version", 1)) == 2:
				var reservation: Dictionary = site.get("reservation", {})
				if str(reservation.get("status", "")) == "imported":
					reply.body = "予約端末が復旧し、DAY %02d到着の%s様の予約が台帳に入りました。予約番号 %s。\n前回の精算控え %s と証拠原本も引き継げています。" % [int(reservation.get("arrival_day", 0)), str(reservation.get("guest", "")), str(reservation.get("bookingno", "")), str(site.get("receipt", {}).get("number", ""))]
				continue
			reply.body = "%s号室の精算票を受け取りました。受付番号 %s、残高は0円です。" % [str(site.get("room", "")), str(site.get("receipt", {}).get("number", ""))]
			if bool(site.get("reservation_isolated", false)): reply.body += "\n予約端末PC-Aは隔離したまま、後続の調査担当へ引き継ぎます。"
		if str(reply.rating) == "late": reply.body += "\nただ、予定していた時刻を超えてしまいました。"
		elif str(reply.rating) == "rework": reply.body += "\n手戻りがあり、次回は事前の確認をお願いします。"
		elif str(reply.rating) == "on_time": reply.body += "\n予定に間に合いました。ありがとうございました。"
		var stop_minutes:=0.0
		for impact in own.get("endpoint_impact",{}).values():
			if impact is Dictionary and impact.has("uncontained_minutes"):stop_minutes+=float(impact.get("stop_minutes",0))
		if stop_minutes>0:
			reply.body+="\nただ、調査中に正常な業務が%d分止まりました。次回は必要な端末だけを止めてください。" % roundi(stop_minutes)
	for event in state.get("company_cycle",{}).get("events",[]):
		if completed and event is Dictionary and str(event.get("contract_id","")) == id and str(event.get("client","")) == str(reply.client): reply.event = event.duplicate(true)
	return reply

static func delivery_for(state: Dictionary, id: String) -> Dictionary:
	for raw in state.get("history",[]):
		if raw is Dictionary and str(raw.get("id","")) == id and str(raw.get("kind","delivery")) == "delivery": return raw.duplicate(true)
	return {}

static func request_for(state: Dictionary, record: Dictionary) -> Dictionary:
	var own:=delivery_for(state,str(record.get("id","")))
	if own.get("request_mail",{}) is Dictionary and not own.get("request_mail",{}).is_empty():
		var mail: Dictionary=own.request_mail.duplicate(true); mail.source="saved-request"; return mail
	var contract: Dictionary=state.get("contract_contexts",{}).get(str(record.get("id","")),{}).get("contract",{})
	var brief:=str(own.get("brief",contract.get("brief","")))
	return {"subject":str(own.get("title","納品の確認")),"company":str(own.get("client",contract.get("client",record.get("client","")))),"sender":"担当者 · 依頼の控え","body":brief if not brief.is_empty() else "? 依頼本文の記録なし","source":"accepted-brief" if not brief.is_empty() else "unknown"}

static func build(d, parent: VBoxContainer, mail: Dictionary, record: Dictionary, footer: Container) -> void:
	var data := project(d.game.state,record)
	var request_mail:=request_for(d.game.state,record)
	var thread := VBoxContainer.new(); thread.name = "MailDeliveryThread"; thread.set_meta("delivery",data.duplicate(true)); thread.add_theme_constant_override("separation",4); parent.add_child(thread)
	var subject: Label = d._label(("Re: " if bool(data.completed) else "納品記録 · ") + str(request_mail.get("subject",record.get("title","確認"))),18,INK); subject.name = "MailReplySubject"; thread.add_child(subject)
	var sender: HBoxContainer = d._row(thread,9)
	var avatar := PanelContainer.new(); avatar.custom_minimum_size=Vector2(32,32); avatar.add_theme_stylebox_override("panel",UI.style(Color("d8eafa"),Color.TRANSPARENT,5,3,20)); sender.add_child(avatar)
	var initial: Label = d._label(str(data.client).left(1),15,BLUE); initial.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; avatar.add_child(initial)
	var name: Label = d._label(str(data.client)+" · "+str(request_mail.get("sender","担当者")),13,INK); name.size_flags_horizontal=Control.SIZE_EXPAND_FILL; name.tooltip_text=name.text; name.autowrap_mode=TextServer.AUTOWRAP_OFF; name.clip_text=true; sender.add_child(name)
	sender.add_child(d._label("DAY %02d" % int(data.day) if int(data.day)>0 else "? 日付なし",12,MUTED))
	var message: Label = d._label(str(data.body),14,INK); message.name="MailCustomerReply"; thread.add_child(message)
	var graphic := preload("res://scripts/mail_received_sheet.gd").new(); graphic.setup(data,float(d.game.settings.get("text_scale",1.0))); thread.add_child(graphic)
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation",8); actions.add_theme_constant_override("v_separation",6); actions.size_flags_horizontal=Control.SIZE_EXPAND_FILL; footer.add_child(actions)
	var details := VBoxContainer.new(); details.name="MailReceivedDetails"; details.visible=false
	var attachment: Button = d._button("受取確認を開く",func(): details.visible=not details.visible); attachment.name="MailReceivedAttachment"; attachment.icon=UI.symbol("file"); attachment.add_theme_constant_override("icon_max_width",18); actions.add_child(attachment)
	var customer: Button = d._button("顧客との仕事",func():
		if d._save_session(): d.customer_requested.emit(str(data.client)))
	customer.name="MailCustomerRoute"; customer.disabled=not d.game.company_cycle_view().get("opportunities",[]).any(func(row): return str(row.get("client","")) == str(data.client)); actions.add_child(customer)
	var current_id: String = str(d.game.state.get("current_contract_id","")) if bool(d.game.state.get("career_mode",false)) else str(d.game.mission().get("id",""))
	if current_id == str(data.id):
		var receipt: Button = d._button("精算明細",d._show_app.bind("receipt")); receipt.name="MailReceiptAction"; actions.add_child(receipt)
	thread.add_child(details)
	details.add_child(d._label("納品時に保存した確認内訳",13,MUTED))
	for row in data.checks:
		var label: Label = d._label(("✓ " if bool(row.get("passed",false)) else "× ")+str(row.get("label","確認")),13,INK); details.add_child(label)
	if data.checks.is_empty(): details.add_child(d._label("? 確認の記録なし",13,MUTED))
	if not data.event.is_empty(): details.add_child(d._label(str(data.event.get("message","")),13,MUTED))
	var request: VBoxContainer = d._disclosure(thread,"元の依頼を見る")
	if str(request_mail.source)!="saved-request": request.add_child(d._label("依頼の控え" if str(request_mail.source)=="accepted-brief" else "? 依頼本文の記録なし",12,MUTED))
	var original: Label = d._label(str(request_mail.body).replace("\r\n","\n").strip_edges(),13,MUTED); original.name="MailOriginalRequest"; request.add_child(original)
