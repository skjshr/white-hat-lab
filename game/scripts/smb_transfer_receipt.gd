extends Control
## Compact actual upload acknowledgement; no new request or remote preview.
const UI = preload("res://scripts/ui_theme.gd")
var factor := 1.0
var items: Array[Label] = []

func setup(d, record: Dictionary) -> void:
	name = "SmbTransferReceipt"; factor = float(d.game.settings.get("text_scale",1.0)); custom_minimum_size.y = 50 * factor; size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var state: String = preload("res://scripts/smb_transfer_desk.gd").response_state(record)
	var saved := state == "saved"
	for value in [str(record.get("local_path","")).get_file(),str(record.get("share","share"))+" / "+str(record.get("filename","")),"#"+str(record.get("attempt",0))+"  "+("✓ 保存済み · "+str(record.get("bytes",0))+" B" if saved else "× 転送失敗")]:
		var label := Label.new(); label.text = value; label.tooltip_text = value; label.clip_text = true
		label.add_theme_font_override("font",UI.font(400)); label.add_theme_font_size_override("font_size",roundi(12*factor)); label.add_theme_color_override("font_color",Color("236854") if saved else Color("a82f33")); add_child(label); items.append(label)
	set_meta("receipt",record.duplicate(true)); resized.connect(_layout)

func _ready() -> void: _layout()
func _layout() -> void:
	if items.size() != 3: return
	for index in 2:
		items[index].position = Vector2(size.x*.58 if index == 1 else 26*factor,0)
		items[index].size = Vector2(size.x*.42-26*factor,22*factor)
	items[2].position = Vector2(0,25*factor); items[2].size = Vector2(size.x,24*factor); queue_redraw()
func _draw() -> void:
	var f := factor; var color := Color("7293a2")
	draw_rect(Rect2(3*f,2*f,14*f,18*f),color,false,f)
	for line in 3: draw_line(Vector2(6*f,(7+line*4)*f),Vector2(14*f,(7+line*4)*f),color,f)
	var start := Vector2(size.x*.42,11*f); var end := Vector2(size.x*.55,11*f)
	draw_line(start,end,color,2*f,true)
	draw_line(end,end+Vector2(-6,-4)*f,color,2*f,true); draw_line(end,end+Vector2(-6,4)*f,color,2*f,true)
