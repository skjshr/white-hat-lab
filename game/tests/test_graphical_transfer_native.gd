extends "res://tests/test_taskbar_work_native.gd"
## Real earned company, actual request records and UI input through paid outcome.
const COPY := "/home/operator/report.txt"

func native_method() -> String:
	return super.native_method() + " Inspect the two transfer endpoints, actual refusal after resume, changed destination/source without reusing results, read-only detail inspection, actual persistence rollback and actual byte acknowledgement. No remote contents are read for display outside the recorded GET."

func document_visible() -> bool:
	if not await super.document_visible() or not await press_control(control("SmbPreview"),"focus actual retrieved read-only paper"): return false
	await tap(KEY_TAB)
	return expect(root.gui_get_focus_owner() == control("SmbEdit"),"Tab leaves the retrieved paper for the actual edit action")

func transfer_visible(expected: String) -> bool:
	var desk := control("SmbTransferDesk")
	if not expect(desk != null and str(desk.projected.state) == expected, "transfer surface shows actual state " + expected): return false
	for id in ["SmbTransferLocalTitle","SmbTransferRemoteTitle","SmbSourcePicker","SmbRemoteName","SmbTransferLocalPreview","SmbTransferRemotePreview","SmbTransferIdentity","SmbUpload","SmbTransferEdit","SmbTransferCancel"]:
		var object := control(id)
		if not expect(clipped_rect(object).grow(1).encloses(object.get_global_rect()), "whole transfer object visible without test scrolling " + id): return false
	var state := control("SmbSourceDraft") if expected == "draft" else control("SmbTransferState")
	if not expect(state.is_visible_in_tree() and clipped_rect(state).grow(1).encloses(state.get_global_rect()), "whole response visible " + expected): return false
	if not expect(not control("SmbSource").is_visible_in_tree() and not control("SmbOutput").is_visible_in_tree(), "paths and raw response stay behind explicit detail action"): return false
	for id in ["SmbTransferLocalPreview","SmbTransferRemotePreview"]:
		var paper := control(id) as TextEdit
		var height := paper.get_theme_font("font").get_height(paper.get_theme_font_size("font_size"))
		if not expect(paper.size.y >= height * 5 + 10, "transfer paper accommodates authored report lines " + id): return false
	return true

func after_copy_saved() -> bool:
	if not await super.after_copy_saved() or not await transfer_visible("unmeasured"): return false
	if not expect(control("SmbTransferLocalPreview").text == daily_report and control("SmbTransferRemotePreview").text == initial_report, "saved copy and actual earlier retrieved share differ visibly"): return false
	await capture("transfer-01-real-copy-and-shared-snapshot")
	return true

func choose_source(path: String) -> bool:
	var picker := control("SmbSourcePicker") as OptionButton
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == path: return await select_option("SmbSourcePicker",index)
	return expect(false,"actual source picker contains " + path)

func employee_transfer_action() -> bool:
	if "--external-drag" not in OS.get_cmdline_user_args(): return await keyboard_activate("SmbUpload")
	var attempt := int(ui.desktop.samba_ui.get("transfer_attempt",0))
	print("EXTERNAL_DRAG_READY attempt=",attempt," pixels=",root.size," grip=",control("SmbCopyGrip").get_global_rect())
	var deadline := Time.get_ticks_msec() + 90000
	while int(ui.desktop.samba_ui.get("transfer_attempt",0)) == attempt and Time.get_ticks_msec() < deadline:
		await process_frame
	await frames(8)
	record("external_drag","Physical window drag via sky; not Input.parse_input_event, not a model callback")
	return expect(root.gui_is_drag_successful() and int(ui.desktop.samba_ui.transfer_attempt) == attempt+1,"physical drop invokes exactly one real transfer request")

func employee_begin() -> bool:
	if not await super.employee_begin() or not await route("files") or not await transfer_visible("denied"): return false
	var record: Dictionary = ui.desktop.samba_ui.last_transfer.duplicate(true)
	if not expect(not bool(record.success) and int(record.bytes) == 0 and str(record.local_path) == COPY and str(record.user) == "staff" and str(record.filename) == "report.txt" and str(record.response) == "NT_STATUS_ACCESS_DENIED", "resumed refusal retains the actual request and claims no transferred bytes"): return false
	await capture("transfer-02-actual-refusal-after-resume")
	var machine: Dictionary = game._vm().export_state(); var minutes := int(game.state.clock_minutes)
	if not await edit("SmbRemoteName","other-report.txt") or not await transfer_visible("unmeasured"): return false
	if not expect(control("SmbTransferRemotePreview").text == "? 内容未取得", "unrequested target never borrows another file's retrieved contents"): return false
	await capture("transfer-03-new-target-has-no-result")
	if not await edit("SmbRemoteName","report.txt") or not await transfer_visible("denied"): return false
	if not await choose_source("/srv/data/report.txt") or not await transfer_visible("unmeasured"): return false
	if not expect(str(control("SmbSource").text) == "/srv/data/report.txt" and control("SmbTransferLocalPreview").text == daily_report, "same filename at a different actual source never inherits old refusal"): return false
	if not await choose_source(COPY) or not await transfer_visible("denied"): return false
	var details := find_text_button(ui,"パス・応答の詳細")
	if not await press_control(details,"inspect actual transfer paths and raw response"): return false
	if not expect(control("SmbSource").is_visible_in_tree() and str(control("SmbSource").text) == COPY and str(control("SmbOutput").text) == str(record.response), "explicit details show retained actual request"): return false
	if not await press_control(find_text_button(ui,"パス・応答の詳細"),"close transfer details"): return false
	ui.desktop._render_smb(); await frames(8)
	if not expect(same_values(game._vm().export_state(),machine) and int(game.state.clock_minutes) == minutes and same_values(ui.desktop.samba_ui.last_transfer,record), "target selection, detail and drawing never request or change work/last response"): return false
	return await route("browser")

func after_transfer_persistence_failure() -> bool:
	if not await super.after_transfer_persistence_failure() or not await transfer_visible("save_failed"): return false
	var record: Dictionary = ui.desktop.samba_ui.last_transfer
	if not expect(not bool(record.success) and int(record.bytes) == 0 and control("SmbTransferState").text.contains("転送を取り消し"), "actual rollback appears at storage with no successful bytes"): return false
	var mark := control("SmbTransferFailureMark")
	if not expect(mark.is_visible_in_tree() and clipped_rect(mark).grow(1).encloses(mark.get_global_rect()) and mark.get_index() > control("SmbTransferRemotePreview").get_index(), "storage failure stamp is visible above the remote paper"): return false
	await capture("transfer-04-actual-storage-rollback")
	return true

func after_transfer_saved() -> bool:
	var receipt := control("SmbTransferReceipt")
	if not expect(receipt != null and receipt.is_visible_in_tree(), "successful actual request displays its acknowledgement"): return false
	var record: Dictionary = receipt.get_meta("receipt")
	if not expect(bool(record.success) and str(record.filename) == "report.txt" and int(record.bytes) == daily_report.to_utf8_buffer().size() and game.vm_read("/srv/share/report.txt") == daily_report, "receipt count matches exact bytes really stored after retry"): return false
	if not expect(clipped_rect(receipt).grow(1).encloses(receipt.get_global_rect()), "whole actual byte acknowledgement visible after send"): return false
	await capture("transfer-05-actual-saved-byte-acknowledgement")
	return true
