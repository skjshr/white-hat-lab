extends Control
## A time ruler and payroll comparison. All values are supplied by the read model.
const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
const PREVIEW = preload("res://scripts/staffing_work_preview.gd")
var model: Dictionary = {}
var selected: Dictionary = {}
var factor := 1.0
var source: WeakRef
var refresh_action: Callable
var source_signature := ""
var refresh_pending := false

func watch(game, action: Callable) -> void:
	source = weakref(game); refresh_action = action
	source_signature = PREVIEW.signature(game)
	if not game.changed.is_connected(_source_changed): game.changed.connect(_source_changed)

func _source_changed() -> void:
	if source == null or not is_inside_tree(): return
	var game = source.get_ref()
	if game == null: return
	var signature := PREVIEW.signature(game)
	if signature == source_signature: return
	source_signature = signature
	if refresh_pending: return
	refresh_pending = true
	call_deferred("_refresh_source")

func _refresh_source() -> void:
	refresh_pending = false
	if is_inside_tree() and refresh_action.is_valid(): refresh_action.call()

func configure(value: Dictionary, job: Dictionary, scale: float) -> void:
	model = value.duplicate(true); selected = job.duplicate(true); factor = scale
	name = "StaffShiftCanvas"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 164 * factor
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(queue_redraw): resized.connect(queue_redraw)
	queue_redraw()

func _text(at: Vector2, value: String, font_size: int, color: Color, width: float = -1) -> void:
	var font: Font = UI.font(500)
	var shown := value
	if width > 0:
		while shown.length() > 1 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			shown = shown.left(shown.length() - 2) + "…"
	draw_string(font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	if model.is_empty() or size.x <= 0: return
	draw_set_transform(Vector2.ZERO, 0, Vector2(factor, factor))
	var width := size.x / factor
	var left := 12.0; var right := width - 12.0; var span := right - left
	var start := int(model.get("shift_start", 540)); var end := int(model.get("shift_end", 1080))
	var x_start := left + span * (start - 540) / 540.0
	var x_end := left + span * (end - 540) / 540.0
	draw_rect(Rect2(0, 0, width, 164), Color("F1F4EF"))
	_text(Vector2(left, 20), "勤務時間" + (" · 翌日の変更は下で予約" if bool(model.get("hired", false)) else " · 採用した場合"), 13, M.INK, span)
	draw_rect(Rect2(left, 47, span, 21), M.LINE)
	draw_rect(Rect2(x_start, 47, x_end - x_start, 21), M.SELECTED)
	draw_rect(Rect2(x_start, 47, x_end - x_start, 21), M.ACCENT, false, 1.5)
	for minute in [540, 780, 1080]:
		var x: float = left + span * (int(minute) - 540) / 540.0
		draw_line(Vector2(x, 44), Vector2(x, 70), M.MUTED, 1)
		_text(Vector2(clampf(x - 17, left, right - 36), 39), "%02d:00" % (minute / 60), 13, M.MUTED)
	var now := int(model.get("clock_minute", 540))
	if now >= 540 and now <= 1080:
		var now_x := left + span * (now - 540) / 540.0
		draw_line(Vector2(now_x, 45), Vector2(now_x, 72), M.INK, 2)
		draw_colored_polygon(PackedVector2Array([Vector2(now_x - 4, 71), Vector2(now_x + 4, 71), Vector2(now_x, 66)]), M.INK)
	var text := "担当する仕事を下で選択"
	var ink := M.MUTED
	if not selected.is_empty():
		if bool(selected.get("can_finish", false)):
			var finish_day := int(selected.get("finish_day", -1)); var finish := int(selected.get("finish_minute", 0))
			text = "この工程 → DAY%d %02d:%02d · %d分" % [finish_day, finish / 60, finish % 60, ceili(float(selected.get("duration_minutes", 0)))]
			if str(selected.get("risk", "")) == "late": text += " · 期限超過"
			ink = M.WARNING if str(selected.get("risk", "")) in ["late", "next_day"] else M.ACCENT
			if finish_day == int(model.get("current_day", -1)) and finish >= 540 and finish <= 1080:
				var finish_x := left + span * (finish - 540) / 540.0
				draw_circle(Vector2(finish_x, 57.5), 5, ink)
			else: text += " · 翌日以降"
		else:
			text = "× " + str(selected.get("reason", "この工程は担当できません")); ink = M.DANGER
	_text(Vector2(left, 91), text, 13, ink, span)
	draw_line(Vector2(left, 103), Vector2(right, 103), M.LINE, 1)
	var half := span * .5
	_text(Vector2(left, 122), "本日の会社給与", 13, M.MUTED, half - 8)
	var before := int(model.get("day_payroll_before", 0)); var after := int(model.get("day_payroll_after", before))
	_text(Vector2(left, 148), "¥%s → ¥%s" % [before, after] if not bool(model.get("hired", false)) else "¥%s" % before, 18, M.INK, half - 8)
	_text(Vector2(left + half, 122), "採用時 / この勤務帯の日給" if not bool(model.get("hired", false)) else "この人の日給", 13, M.MUTED, half)
	_text(Vector2(left + half, 148), "¥%d / ¥%d" % [int(model.get("hire_fee", 0)), int(model.get("wage", 0))] if not bool(model.get("hired", false)) else "¥%d" % int(model.get("wage", 0)), 18, M.INK, half)
