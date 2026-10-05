extends "res://tests/test_daily_report_native.gd"
## Same genuine earned company; add the employee's real file/editor workflow.
var file_round := 0

func after_copy_saved() -> bool: return true
func after_transfer_persistence_failure() -> bool: return true
func after_transfer_saved() -> bool: return true
func employee_transfer_action() -> bool: return await press("SmbUpload")

func receipt_effect(receipt: Dictionary) -> bool:
	return expect(game.current_done() and str(receipt.rating) == "late" and int(receipt.fee) < int(receipt.agreed_fee) and int(receipt.satisfaction_after) < int(receipt.satisfaction_before), "real repeated employee work exceeds deadline, reducing fee and customer trust")

func native_method() -> String:
	return super.native_method() + " Employee file GET, actual multiline editor input, unsaved send rejection, copy save, ACL refusal, transfer checkpoint resume, failed transfer persistence rollback, successful retry and read-back use actual input. Drawing and copy-path inspection never request or rewrite. Repeated explicit work really exceeds deadline; lower fee and customer satisfaction persist after payment. The test does not reset clock or change terms to hide that consequence."

func document_visible() -> bool:
	var desk := control("SmbDocumentDesk")
	if not expect(desk != null, "Explorer presents actual document and copy objects"): return false
	for id in ["SmbDocumentName", "SmbPreview", "SmbDocumentSnapshot", "SmbCopyTitle", "SmbCopyState", "SmbEdit", "SmbUploadEdited"]:
		var object := control(id)
		if not expect(clipped_rect(object).grow(1).encloses(object.get_global_rect()), "whole document/copy object fits without test scrolling " + id): return false
	var paper := control("SmbPreview") as TextEdit
	var height := paper.get_theme_font("font").get_height(paper.get_theme_font_size("font_size"))
	return expect(paper.size.y >= height * 5 + 10, "whole authored daily report is visible inside the paper")

func edit_copy(value: String) -> bool:
	var editor: CodeEdit = ui.desktop.editor
	if not await press_control(editor, "edit downloaded actual report copy"): return false
	key(KEY_A, true, 0, true); key(KEY_A, false, 0, true); await tap(KEY_BACKSPACE)
	for index in value.length():
		if value.unicode_at(index) == 10: await tap(KEY_ENTER)
		else: key(KEY_NONE, true, value.unicode_at(index)); key(KEY_NONE, false, value.unicode_at(index))
	await frames(8)
	record("employee_editor_input", editor.text)
	return expect(editor.text == value, "actual key events change the editable copy draft")

func employee_begin() -> bool:
	if not await press("SambaOpenShare_share") or not await press("SmbFile_report_txt") or not await document_visible(): return false
	if not expect(control("SmbPreview").text == initial_report and control("SmbCopyState").text == "✓ 取得時と同じ", "actual previous-day report is shown as fetched snapshot"): return false
	await capture("employee-01-before-report-paper")
	if not await keyboard_activate("SmbEdit") or not await edit_copy(daily_report): return false
	var before_return: Dictionary = game._vm().export_state(); var minutes := int(game.state.clock_minutes)
	if not await route("files") or not expect(same_values(game._vm().export_state(), before_return) and int(game.state.clock_minutes) == minutes, "returning to copy desk redraws without requesting or spending work time"): return false
	if not expect(control("SmbCopyState").text == "● 未保存の編集" and control("SmbPreview").text == initial_report, "draft changes copy state without rewriting captured share specimen"): return false
	if not await press("SmbUploadEdited") or not expect(control("SmbUpload").disabled and control("SmbSourceDraft").visible, "unsaved actual report copy cannot be sent"): return false
	if not await route("editor") or not await press("EditorSave") or not await after_copy_saved() or not await route("files"): return false
	if not await employee_transfer_action() or not expect(str(ui.desktop.samba_ui.access_output) == "NT_STATUS_ACCESS_DENIED" and game.vm_read("/srv/share/report.txt") == initial_report, "saved employee copy still encounters real server permission refusal"): return false
	await capture("employee-02-real-copy-save-denied")
	var machine: Dictionary = game._vm().export_state()
	var session: Dictionary = ui.desktop.samba_ui.duplicate(true)
	if not expect(ui.desktop._save_session() and game.save_game(), "save actual employee refusal, report copy and transfer fields"): return false
	ui.queue_free(); await frames(6)
	if not expect(game.load_game() and same_values(game._vm().export_state(), machine), "employee interruption retains exact copy and unchanged shared report"): return false
	game.set_process(false); await build_ui()
	if not await route("files") or not expect(str(control("SmbSource").text) == str(session.access_source) and str(control("SmbRemoteName").text) == "report.txt", "resume retains same failed transfer's real inputs"): return false
	return await route("browser")

func employee_retry() -> bool:
	if not await route("files"): return false
	var before: Dictionary = game._vm().export_state(); var path: String = game.save_path
	game.save_path = "user://missing-employee-transfer/save.json"
	var clicked := await press("SmbUpload"); game.save_path = path
	if not clicked or not expect(same_values(game._vm().export_state(), before) and str(ui.desktop.samba_ui.access_output).contains("save_failed") and ui.desktop.status.text.contains("保存失敗"), "failed actual transfer persistence restores report/copy bytes and visible failure"): return false
	if not await after_transfer_persistence_failure(): return false
	if not await press("SmbUpload") or not expect(game.vm_read("/srv/share/report.txt") == daily_report and ui.desktop.status.text == "転送保存済み", "same employee transfer succeeds and replaces failure after real permission repair"): return false
	if not await after_transfer_saved(): return false
	if not await press("SmbFile_report_txt") or not await document_visible(): return false
	if not expect(control("SmbPreview").text == daily_report and control("SmbCopyState").text == "✓ 取得時と同じ", "real read-back shows today's report through the consumer software"): return false
	await capture("employee-03-read-back-current-report")
	var before_inspection: Dictionary = game._vm().export_state()
	var minutes := int(game.state.clock_minutes)
	var details := find_text_button(ui, "取得先・接続の詳細")
	if not await press_control(details, "inspect fetched-copy address"): return false
	if not expect(control("SmbPreviewPath").text.contains("/home/operator/report.txt") and same_values(game._vm().export_state(), before_inspection) and int(game.state.clock_minutes) == minutes, "copy path details do not request, rewrite, measure or spend work time"): return false
	return await route("browser")

func probe_all() -> bool:
	file_round += 1
	if file_round == 1 and not await employee_begin(): return false
	if file_round == 3 and not await employee_retry(): return false
	return await super.probe_all()
