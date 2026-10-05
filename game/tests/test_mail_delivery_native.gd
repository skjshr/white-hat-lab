extends "res://tests/test_graphical_transfer_native.gd"
## Same earned intake journey; genuine delivery changes the customer's thread.
var original_request:=""
func native_method() -> String:
	return super.native_method()+" Read customer's request after real employee refusal, then read reply after real delivery. Inspect saved checks by Tab/Enter, follow the customer's CRM route and return to the saved thread. Customer reply is a projection of the exact persisted delivery, not remote measurements or an independent simulated email exchange."
func current_mail() -> bool:
	if not await route("mail"): return false
	if bool(ui.desktop.widgets.mail.reading) and not ui.desktop.widgets.mail.list_panel.is_visible_in_tree():
		if not await press("MailBack"): return false
	return await press("MailContract_"+str(game.state.current_contract_id).validate_node_name())
func employee_begin() -> bool:
	if not await super.employee_begin() or not await current_mail(): return false
	if not expect(control("MailDeliveryThread")==null and control("MailMessageBody")!=null and control("MailMessageBody").text.contains("保存できず"),"real employee refusal never creates a reply from older same-case deliveries"): return false
	original_request=control("MailMessageBody").text
	await capture("mail-01-still-awaiting-actual-delivery")
	return await route("browser")
func after_transfer_saved() -> bool:
	if not await super.after_transfer_saved() or not await current_mail(): return false
	if not expect(not game.current_done() and control("MailDeliveryThread")==null,"successful transfer alone is not customer's delivery acknowledgement"): return false
	return await route("files")
func receipt_effect(receipt: Dictionary) -> bool:
	if not await super.receipt_effect(receipt) or not await current_mail(): return false
	var reply: Dictionary=control("MailDeliveryThread").get_meta("delivery")
	var saved: Dictionary=preload("res://scripts/mail_delivery_thread.gd").delivery_for(game.state,str(game.state.current_contract_id))
	if not expect(saved.has("delivery_results") and same_values(saved.delivery_results,receipt.delivery_results) and str(reply.evidence_source)=="delivery-history" and bool(reply.report_write_confirmed),"customer's report recovery is backed by this delivery's durable actual PUT response"): return false
	if not expect(str(saved.get("request_mail",{}).get("body","" )).strip_edges()==original_request and str(control("MailOriginalRequest").text)==original_request,"delivery retains the actual request read before work instead of reconstructing it from a future catalog"): return false
	if not expect(str(reply.id)==str(game.state.current_contract_id) and bool(reply.confirmed) and same_values(reply.checks,receipt.checks) and str(reply.rating)==str(receipt.rating) and int(reply.before)==int(receipt.satisfaction_before) and int(reply.after)==int(receipt.satisfaction_after),"actual completed delivery changes only its own customer's thread"): return false
	for id in ["MailCustomerReply","MailReceivedSheet","MailReceivedAttachment","MailCustomerRoute","MailReceiptAction"]:
		var node:=control(id)
		if not expect(clipped_rect(node).grow(1).encloses(node.get_global_rect()),"whole customer reply object visible without scrolling "+id): return false
	if not expect(is_equal_approx(float(control("MailReceivedSheet").factor),1.3 if narrow else 1.0),"customer attachment honors actual text scale"): return false
	await capture("mail-02-actual-delivery-customer-reply")
	var before: Dictionary=game.state.duplicate(true); var machine: Dictionary=game._vm().export_state()
	if not await keyboard_activate("MailReceivedAttachment") or not expect(control("MailReceivedDetails").is_visible_in_tree(),"actual Tab and Enter open saved customer receipt attachment"): return false
	if not await press("MailReceivedAttachment"): return false
	if not expect(same_values(game.state.history,before.history) and same_values(game.state.company_cycle,before.company_cycle) and same_values(game.state.customer_relations,before.customer_relations) and int(game.state.cash)==int(before.cash) and int(game.state.clock_minutes)==int(before.clock_minutes) and same_values(game._vm().export_state(),machine),"attachment inspection never re-measures, rewards, advances work or changes customer reply"): return false
	if not await press("MailCustomerRoute"): return false
	var selected := str(ui.get_meta("cycle_customer","")); var own := false
	for item in game.company_cycle_view().get("opportunities",[]):
		if str(item.id)==selected and str(item.client)==str(receipt.client): own=true
	if not expect(ui.current_kind=="company" and own,"reply opens the exact customer's next work and recorded consequence"): return false
	await capture("mail-03-customer-work-route")
	if not await press_control(find_text_button(ui,"PC"),"return from customer's work to the saved mail window"): return false
	if not expect(ui.desktop.current_app=="mail" and str(control("MailDeliveryThread").get_meta("delivery").id)==str(reply.id),"cross-screen return retains exact completed thread"): return false
	if not await keyboard_activate("MailReceiptAction"): return false
	return expect(control("ReceiptFinanceTab")!=null,"mail attachment route returns to this delivery's actual accounting")
