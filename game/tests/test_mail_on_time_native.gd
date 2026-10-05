extends "res://tests/test_daily_report_native.gd"
## Actual shorter work path earns an on-time reply; no clock/answer injection.
func native_method() -> String:
	return super.native_method()+" Read the customer reply after the real on-time delivery, then return to the invoice and actual payment. The reply's scores and consultation status come from this delivery's saved history/event."
func receipt_effect(receipt: Dictionary) -> bool:
	if not super.receipt_effect(receipt) or not await route("mail"): return false
	if bool(ui.desktop.widgets.mail.reading) and not ui.desktop.widgets.mail.list_panel.is_visible_in_tree():
		if not await press("MailBack"): return false
	if not await press("MailContract_"+str(game.state.current_contract_id).validate_node_name()): return false
	var reply: Dictionary=control("MailDeliveryThread").get_meta("delivery")
	if not expect(str(reply.rating)=="on_time" and str(reply.id)==str(game.state.current_contract_id) and int(reply.after)>int(reply.before) and str(control("MailCustomerReply").text).contains("予定に間に合いました"),"actual on-time work earns a positive customer reply and recorded score gain"): return false
	if not expect(str(reply.event.get("kind","")) in ["requested","resumed","fulfilled"] and not str(control("MailNextContact").text).contains("保留"),"on-time delivery records the next consultation instead of a late hold"): return false
	for id in ["MailCustomerReply","MailReceivedSheet","MailReceivedAttachment","MailCustomerRoute","MailReceiptAction"]:
		var node:=control(id)
		if not expect(clipped_rect(node).grow(1).encloses(node.get_global_rect()),"whole on-time reply object visible "+id): return false
	await capture("mail-on-time-earned-reply")
	return await keyboard_activate("MailReceiptAction")
