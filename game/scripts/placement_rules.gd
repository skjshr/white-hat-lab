extends RefCounted
class_name PlacementRules

const UI = preload("res://scripts/ui_theme.gd")
const FLOOR_IDS := ["plant","backup","diagnostic","workstation","teamdesk","annexdesk_a","annexdesk_b"]
const MOVABLE_IDS := ["monitor"]
const DESKS := ["teamdesk","annexdesk_a","annexdesk_b"]
const MONITOR_SURFACE_HEIGHT := 0.80
const MONITOR_HALF := Vector2(0.306907,0.081285)
const MONITOR_SURFACE_MARGIN := 0.02
const PLANT_HALF := Vector2(0.2751,0.3077)
const FIXED_SLOTS := {"backup":Vector2(0.7,-1.05),"monitor":Vector2(2.0,-2.8),"workstation":Vector2(4.1,-3.25),"diagnostic":Vector2(1.15,0.65),"teamdesk":Vector2(1.0,2.7),"plant":Vector2(-5.2,0.4),"annexdesk_a":Vector2(8.2,1.0),"annexdesk_b":Vector2(10.5,1.0)}
## These are the authoritative tabletop targets.  They describe the usable
## top surface, rather than the desk collision body, so a monitor must fit its
## complete footprint inside one of these rectangles.
const BUILTIN_MONITOR_SURFACES := [
	{"id":"builtin_terminal_desk","center":Vector3(-0.5,MONITOR_SURFACE_HEIGHT,-1.0),"size":Vector2(1.5094,0.8062),"rotation_y":0.0,"support_id":"terminal_desk"},
	{"id":"builtin_aya_desk","center":Vector3(-3.6,MONITOR_SURFACE_HEIGHT,-2.3),"size":Vector2(1.5094,0.8062),"rotation_y":0.20,"support_id":"aya_desk"},
	{"id":"builtin_ren_desk","center":Vector3(2.8,MONITOR_SURFACE_HEIGHT,-2.8),"size":Vector2(1.5094,0.8062),"rotation_y":-0.25,"support_id":"ren_desk"},
]
# Composite bounds measured from rendered, height-normalized GLBs. Off-center
# displays and desk chairs rotate around the equipment origin.
const LOCAL_BOUNDS := {
	"monitor":Rect2(-0.306907,-0.081285,0.613814,0.16257),
	"plant":Rect2(-0.2351,-0.2677,0.4702,0.5354),
	"backup":Rect2(-0.105,-0.13,0.21,0.292),
	"diagnostic":Rect2(-0.649627,-0.346981,1.299255,0.693961),
	"workstation":Rect2(-0.9634,-0.9634,1.9268,1.9268),
	"teamdesk":Rect2(-0.7548,-0.4032,1.5096,1.3871),
	"annexdesk_a":Rect2(-0.7548,-0.4032,1.5096,1.3871),
	"annexdesk_b":Rect2(-0.7548,-0.4032,1.5096,1.3871)
}
const STEP := 0.20
const BODY_RADIUS := 0.32
const ENTRY := Vector3(4.0,0.0,3.8)
const COFFEE := Vector3(-4.2,0.0,2.5)
static var _grid_key := ""
static var _grid: AStarGrid2D
static var _walk_obstacles: Array[Rect2]=[]
static var _walk_expanded := false
static var _route_check_key := ""
static var _route_check_ok := false

static func legacy_monitor_placement() -> Dictionary:
	# Keep the former fixed monitor at Ren's workstation, with its complete
	# footprint on the tabletop rather than beyond the left edge.
	var surface: Dictionary = BUILTIN_MONITOR_SURFACES[2]
	var center: Vector3 = surface.center
	var yaw := float(surface.rotation_y)
	var at := center + Basis(Vector3.UP,yaw) * Vector3(0.5,0,-0.03)
	return {"position":[at.x,at.y,at.z],"rotation_y":yaw+PI/2.0}

static func _stored_position(order: Dictionary) -> Vector2:
	var value = order.get("install_position",order.get("position",[]))
	if value is Array and value.size()>=3:return Vector2(float(value[0]),float(value[2]))
	return FIXED_SLOTS.get(str(order.get("id","")),Vector2.ZERO)

static func _rotation(order: Dictionary) -> float:
	if bool(order.get("moving_installed",false)):return float(order.get("move_origin_rotation",0.0))
	return float(order.get("rotation_y",PI if str(order.get("id","")) in ["teamdesk","workstation"] else 0.0))

static func _surface_rect(surface: Dictionary) -> Rect2:
	var center_value: Variant = surface.get("center",Vector3.ZERO)
	var center := Vector2.ZERO
	if center_value is Vector3: center = Vector2(center_value.x,center_value.z)
	var size_value: Variant = surface.get("size",Vector2.ZERO)
	var size: Vector2 = size_value if size_value is Vector2 else Vector2.ZERO
	var local := Rect2(-size * 0.5,size)
	return _rotated_rect(local,center,float(surface.get("rotation_y",0.0)))

static func _desk_surfaces(order: Dictionary) -> Array:
	var at := _stored_position(order)
	var yaw := _rotation(order)
	var id := str(order.get("id", ""))
	# Rectangles follow the actual height-normalized top vertices. The corner
	# desk has two wings; its empty quadrant must never support a monitor.
	var tops: Array = [Rect2(-0.754714,-0.40311,1.509428,0.80622)]
	var height := 0.79
	if id == "workstation":
		height = 0.76
		tops = [Rect2(-0.963302,-0.963302,1.926604,0.77110),Rect2(0.19220,-0.19220,0.771102,1.155502)]
	var result: Array = []
	for index in tops.size():
		var top: Rect2 = tops[index]
		var center := at + top.get_center().rotated(-yaw)
		result.append({"id":"desk_%s_%d" % [id,index], "center":Vector3(center.x,height,center.y), "size":top.size, "rotation_y":yaw, "support_id":id})
	return result

static func monitor_surface_specs(orders: Array = []) -> Array:
	var result: Array = BUILTIN_MONITOR_SURFACES.duplicate(true)
	for order in orders:
		if _installed(order) and str(order.get("id", "")) in ["workstation","teamdesk","annexdesk_a","annexdesk_b"]:
			result.append_array(_desk_surfaces(order))
	return result

static func surface_specs(orders: Array = []) -> Array:
	return monitor_surface_specs(orders)

static func monitor_surface_for_position(position: Array, rotation_y: float, orders: Array = []) -> Dictionary:
	if position.size() < 3: return {}
	var center := Vector2(float(position[0]),float(position[2]))
	var candidate := _monitor_corners(center,rotation_y,MONITOR_SURFACE_MARGIN)
	for surface in monitor_surface_specs(orders):
		var surface_center: Vector3 = surface.get("center",Vector3.ZERO)
		var surface_height := surface_center.y
		if absf(float(position[1]) - surface_height) > 0.015: continue
		if _surface_contains(surface,candidate): return surface
	return {}

static func _monitor_corners(center: Vector2, rotation_y: float, margin: float = 0.0) -> Array[Vector2]:
	var local := Rect2(-MONITOR_HALF,MONITOR_HALF * 2.0).grow(margin)
	return [center + local.position.rotated(-rotation_y),center + Vector2(local.end.x,local.position.y).rotated(-rotation_y),center + local.end.rotated(-rotation_y),center + Vector2(local.position.x,local.end.y).rotated(-rotation_y)]

static func _surface_corners(surface: Dictionary, margin: float = 0.0) -> Array[Vector2]:
	var center_value: Variant = surface.get("center",Vector3.ZERO)
	var center := Vector2.ZERO
	if center_value is Vector3: center = Vector2(center_value.x,center_value.z)
	var size_value: Variant = surface.get("size",Vector2.ZERO)
	var size: Vector2 = size_value if size_value is Vector2 else Vector2.ZERO
	var local := Rect2(-size * 0.5,size).grow(-margin)
	var yaw := float(surface.get("rotation_y",0.0))
	return [center + local.position.rotated(-yaw),center + Vector2(local.end.x,local.position.y).rotated(-yaw),center + local.end.rotated(-yaw),center + Vector2(local.position.x,local.end.y).rotated(-yaw)]

static func _surface_contains(surface: Dictionary, candidate: Array[Vector2]) -> bool:
	var surface_center: Vector3 = surface.get("center",Vector3.ZERO)
	var yaw := float(surface.get("rotation_y",0.0))
	var size_value: Variant = surface.get("size",Vector2.ZERO)
	var size: Vector2 = size_value if size_value is Vector2 else Vector2.ZERO
	var local_rect := Rect2(-size * 0.5,size)
	for world_point in candidate:
		var local_point := (world_point - Vector2(surface_center.x,surface_center.z)).rotated(yaw)
		if not local_rect.has_point(local_point): return false
	return true

static func _project(corners: Array[Vector2], axis: Vector2) -> Vector2:
	var low := corners[0].dot(axis); var high := low
	for index in range(1,corners.size()):
		var value := corners[index].dot(axis); low=minf(low,value); high=maxf(high,value)
	return Vector2(low,high)

static func _oriented_rects_intersect(first: Array[Vector2], second: Array[Vector2]) -> bool:
	var axes: Array[Vector2] = []
	for corners in [first,second]:
		for index in [0,1]:
			var edge: Vector2 = corners[index + 1] - corners[index]
			if edge.length_squared() > 0.000001: axes.append(Vector2(-edge.y,edge.x).normalized())
	for axis in axes:
		var a := _project(first,axis); var b := _project(second,axis)
		if a.y <= b.x or b.y <= a.x: return false
	return true

static func _builtin_monitor_props() -> Array:
	var result: Array = []
	for surface in BUILTIN_MONITOR_SURFACES:
		var center: Vector3 = surface.center; var yaw := float(surface.rotation_y)
		result.append({"center":center,"rotation_y":yaw,"local":Rect2(-0.32,-0.085,0.64,0.17),"offset":Vector2(0.0,-0.17)})
		result.append({"center":center,"rotation_y":yaw,"local":Rect2(-0.205,-0.086,0.410,0.172),"offset":Vector2(-0.10,0.23)})
		result.append({"center":center,"rotation_y":yaw,"local":Rect2(-0.079,-0.079,0.158,0.158),"offset":Vector2(-0.60,-0.17)})
		result.append({"center":center,"rotation_y":yaw,"local":Rect2(-0.043,-0.073,0.086,0.146),"offset":Vector2(0.32,0.30)})
		result.append({"center":center,"rotation_y":yaw,"local":Rect2(-0.14,-0.035,0.28,0.07),"offset":Vector2(-0.43,0.25)})
	return result

static func _prop_corners(prop: Dictionary) -> Array[Vector2]:
	var center: Vector3 = prop.center; var yaw := float(prop.rotation_y)
	var local: Rect2 = prop.local; var offset: Vector2 = prop.offset
	var at := Vector2(center.x,center.z) + offset.rotated(-yaw)
	return [at + local.position.rotated(-yaw),at + Vector2(local.end.x,local.position.y).rotated(-yaw),at + local.end.rotated(-yaw),at + Vector2(local.position.x,local.end.y).rotated(-yaw)]

static func monitor_position_error(position: Array, rotation_y: float, orders: Array, expanded: bool = false) -> String:
	if position.size() != 3: return UI.copy("equipment_surface_invalid","Placement is unavailable.")
	for value in position:
		if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)): return UI.copy("equipment_surface_invalid","Placement is unavailable.")
	if not is_finite(rotation_y): return UI.copy("equipment_surface_invalid","Placement is unavailable.")
	var surface := monitor_surface_for_position(position,rotation_y,orders)
	if surface.is_empty(): return UI.copy("equipment_surface_invalid","Placement is unavailable.")
	var candidate := _monitor_corners(Vector2(float(position[0]),float(position[2])),rotation_y)
	for prop in _builtin_monitor_props():
		if _oriented_rects_intersect(candidate,_prop_corners(prop)): return UI.copy("equipment_surface_invalid","Placement is unavailable.")
	for raw_order in orders:
		var order: Dictionary = raw_order
		if str(order.get("id","")) == "monitor": continue
		if not _installed(order): continue
		var id := str(order.get("id",""))
		if id not in ["workstation","teamdesk","annexdesk_a","annexdesk_b"]: continue
		var desk_center := _stored_position(order)
		var desk_yaw := _rotation(order)
		var screen_offset := Vector2(0.0,-0.62) if id == "workstation" else Vector2(0.0,-0.17)
		var keyboard_offset := Vector2(-0.08,-0.29) if id == "workstation" else Vector2(-0.10,0.23)
		var mouse_offset := Vector2(0.32,-0.30) if id == "workstation" else Vector2(0.32,0.30)
		for spec in [[screen_offset,Vector2(0.64,0.17)],[keyboard_offset,Vector2(0.410,0.172)],[mouse_offset,Vector2(0.086,0.146)]]:
			var size: Vector2 = spec[1]
			var prop := {"center":Vector3(desk_center.x,0,desk_center.y),"rotation_y":desk_yaw,"local":Rect2(-size*0.5,size),"offset":spec[0]}
			if _oriented_rects_intersect(candidate,_prop_corners(prop)): return UI.copy("equipment_surface_invalid")

	return ""

static func footprint(id: String, position: Vector2, rotation: float) -> Rect2:
	var local: Rect2=LOCAL_BOUNDS.get(id,Rect2(-0.1,-0.1,0.2,0.2))
	return _rotated_rect(local,position,rotation).grow(0.04)

static func _rotated_rect(local: Rect2,position: Vector2,rotation: float) -> Rect2:
	var points: Array[Vector2]=[local.position,Vector2(local.end.x,local.position.y),local.end,Vector2(local.position.x,local.end.y)]
	var result := Rect2()
	for index in points.size():
		var point: Vector2=position+points[index].rotated(-rotation)
		result=Rect2(point,Vector2.ZERO) if index==0 else result.expand(point)
	return result

static func _half_for(id: String, rotation: float) -> Vector2:
	return footprint(id,Vector2.ZERO,rotation).size*0.5

static func _plant_half(rotation: float) -> Vector2:
	return _half_for("plant",rotation)

static func workplace(order: Dictionary) -> Dictionary:
	var at:=_stored_position(order);var yaw:=_rotation(order)
	var basis:=Basis(Vector3.UP,yaw);var position:=Vector3(at.x,0,at.y)
	return {"position":position,"seat":position+basis*Vector3(0,0,0.72),"approach":position+basis*Vector3(0,0,1.5),"seat_yaw":fposmod(yaw+PI,TAU)}

static func _static_rects() -> Array[Rect2]:
	var rectangles: Array[Rect2]=[
		Rect2(4.92,-1.60,0.96,1.20),Rect2(4.92,0.60,0.96,1.20),
		Rect2(-5.50,2.92,1.40,0.96),Rect2(3.10,4.10,0.60,0.60),
		Rect2(2.00,-4.98,2.80,0.56),Rect2(3.92,4.45,1.56,0.55),
		Rect2(-5.05,-4.05,0.50,0.50)
	]
	for desk in [[Vector2(-0.5,-1.0),0.0,0.98],[Vector2(-3.6,-2.3),0.2,0.58],[Vector2(2.8,-2.8),-0.25,0.58]]:
		var at: Vector2=desk[0];var angle: float=desk[1];var chair_offset: float=desk[2]
		rectangles.append(_rotated_rect(Rect2(-0.8,-0.43,1.6,0.86),at,angle))
		rectangles.append(_rotated_rect(Rect2(-0.36,chair_offset-0.36,0.72,0.72),at,angle))
	return rectangles

static func _installed(order: Dictionary) -> bool:
	return str(order.get("status",""))=="installed" or bool(order.get("moving_installed",false))

static func _layout_key(orders: Array, expanded: bool) -> String:
	var items: Array=[]
	for order in orders:
		if _installed(order) and str(order.get("id","")) in FLOOR_IDS:
			items.append([str(order.id),_stored_position(order),_rotation(order)])
	return str(expanded)+JSON.stringify(items)

static func _walk_floor(point: Vector2, expanded: bool) -> bool:
	if point.x>=-5.55 and point.x<=5.55 and point.y>=-4.55 and point.y<=4.40:return true
	if not expanded:return false
	if point.x>=6.42 and point.x<=11.55 and point.y>=0.44 and point.y<=4.55:return true
	return point.x>=5.4 and point.x<=6.6 and point.y>=2.70 and point.y<=3.60

static func _navigation(orders: Array, expanded: bool) -> AStarGrid2D:
	var key:=_layout_key(orders,expanded)
	if _grid!=null and key==_grid_key:return _grid
	var grid:=AStarGrid2D.new();grid.region=Rect2i(-28,-23,88,47);grid.cell_size=Vector2(STEP,STEP)
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE;grid.update()
	var rectangles:=_static_rects()
	for order in orders:
		if _installed(order) and str(order.get("id","")) in FLOOR_IDS:
			rectangles.append(footprint(str(order.id),_stored_position(order),_rotation(order)))
	for y in range(grid.region.position.y,grid.region.end.y):
		for x in range(grid.region.position.x,grid.region.end.x):
			grid.set_point_solid(Vector2i(x,y),not _walk_floor(Vector2(x,y)*STEP,expanded))
	for rectangle in rectangles:
		var area:=rectangle.grow(BODY_RADIUS)
		var first:=Vector2i(maxi(grid.region.position.x,floori(area.position.x/STEP)),maxi(grid.region.position.y,floori(area.position.y/STEP)))
		var last:=Vector2i(mini(grid.region.end.x,ceili(area.end.x/STEP)+1),mini(grid.region.end.y,ceili(area.end.y/STEP)+1))
		for y in range(first.y,last.y):
			for x in range(first.x,last.x):
				if _hits(Vector2(x,y)*STEP,rectangle):grid.set_point_solid(Vector2i(x,y),true)
	_walk_obstacles.clear()
	for rectangle in rectangles:_walk_obstacles.append(rectangle)
	_walk_expanded=expanded;_grid=grid;_grid_key=key;return grid

static func _point_clear(point: Vector2) -> bool:
	if not _walk_floor(point,_walk_expanded):return false
	for rectangle in _walk_obstacles:
		if _hits(point,rectangle):return false
	return true

static func _hits(point: Vector2, rectangle: Rect2) -> bool:
	var closest:=Vector2(clampf(point.x,rectangle.position.x,rectangle.end.x),clampf(point.y,rectangle.position.y,rectangle.end.y))
	return closest.distance_squared_to(point)<BODY_RADIUS*BODY_RADIUS

static func _segment_clear(from: Vector2, to: Vector2) -> bool:
	var steps:=maxi(1,ceili(from.distance_to(to)/0.04))
	for i in range(steps+1):
		if not _point_clear(from.lerp(to,float(i)/steps)):return false
	return true

static func _nearest_cell(grid: AStarGrid2D, point: Vector2) -> Vector2i:
	var center:=Vector2i(roundi(point.x/STEP),roundi(point.y/STEP))
	var best:=Vector2i(9999,9999);var distance:=0.31
	for y in range(center.y-1,center.y+2):
		for x in range(center.x-1,center.x+2):
			var candidate:=Vector2i(x,y)
			if not grid.is_in_boundsv(candidate) or grid.is_point_solid(candidate):continue
			if not _segment_clear(point,Vector2(candidate)*STEP):continue
			var d: float=(Vector2(candidate)*STEP).distance_to(point)
			if d<distance:distance=d;best=candidate
	return best

static func walk_path(from: Vector3, to: Vector3, orders: Array, expanded: bool) -> Array[Vector3]:
	var grid:=_navigation(orders,expanded)
	if not _point_clear(Vector2(from.x,from.z)) or not _point_clear(Vector2(to.x,to.z)):return []
	var start:=_nearest_cell(grid,Vector2(from.x,from.z));var finish:=_nearest_cell(grid,Vector2(to.x,to.z))
	var result: Array[Vector3]=[]
	if start.x==9999 or finish.x==9999:return result
	var cells:=grid.get_id_path(start,finish)
	if cells.is_empty():return result
	for i in cells.size():
		if i>0 and i<cells.size()-1 and cells[i]-cells[i-1]==cells[i+1]-cells[i]:continue
		result.append(Vector3(cells[i].x*STEP,0,cells[i].y*STEP))
	if result[-1].distance_to(to)>0.001:result.append(to)
	return result

static func _access_ok(orders: Array, expanded: bool) -> bool:
	var key:=_layout_key(orders,expanded)
	if key==_route_check_key:return _route_check_ok
	var required: Dictionary = _access_points(orders)
	var ok:=true
	for raw_point in required.values():
		var point: Vector3 = raw_point
		if walk_path(ENTRY,point,orders,expanded).is_empty():ok=false;break
	_route_check_key=key;_route_check_ok=ok;return ok

static func _access_points(orders: Array) -> Dictionary:
	var required: Dictionary = {
		"coffee": COFFEE,
		"board": Vector3(-2.5,0,3.4),
		"terminal": Vector3(-0.5,0,0.80),
		"aya": Vector3(-3.6,0,-0.85),
		"ren": Vector3(2.8,0,-1.35),
		"annex_entry": Vector3(4.7,0,4.0),
		"bookcase": Vector3(4.4,0,-1.0),
	}
	for order in orders:
		var id := str(order.get("id",""))
		if _installed(order) and id in DESKS:
			required["desk:"+id] = workplace(order).approach
	return required

static func _access_transition_ok(before: Array, proposed: Array, moved_id: String, expanded: bool) -> bool:
	# A legacy layout may already have an unreachable point (for example an
	# older desk collision footprint). Preserve that save while refusing a new
	# regression caused by the current move.
	var before_points: Dictionary = _access_points(before)
	var after_points: Dictionary = _access_points(proposed)
	var reachable: Array[String] = []
	for key in before_points.keys():
		if not after_points.has(key): continue
		var before_point: Vector3 = before_points[key]
		if not walk_path(ENTRY,before_point,before,expanded).is_empty(): reachable.append(key)
	# Check each layout together so mouse-motion previews rebuild the route grid
	# at most twice, rather than alternating it for every access point.
	for key in reachable:
		var after_point: Vector3 = after_points[key]
		if walk_path(ENTRY,after_point,proposed,expanded).is_empty(): return false
	# A newly moved/placed desk still needs a usable route to its own approach;
	# otherwise an apparently valid floor position strands its workstation.
	var moved_key := "desk:"+moved_id
	if after_points.has(moved_key):
		var moved_point: Vector3 = after_points[moved_key]
		if walk_path(ENTRY,moved_point,proposed,expanded).is_empty(): return false
	return true

static func expansion_blocked(orders: Array) -> bool:
	var doorway:=Rect2(5.35,2.65,1.2,1.0)
	for order in orders:
		if _installed(order) and str(order.get("id","")) in FLOOR_IDS and footprint(str(order.id),_stored_position(order),_rotation(order)).intersects(doorway):return true
	return false

static func position_error(id: String, position: Array, rotation_y: float, orders: Array, expanded: bool=false) -> String:
	if id=="monitor":return monitor_position_error(position,rotation_y,orders,expanded)
	if id not in FLOOR_IDS:return "この設備は自由配置に対応していません。"
	if position.size()!=3:return "床面を指定できません。"
	for value in position:
		if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)):return "無効な位置です。"
	if not is_finite(rotation_y):return "無効な回転です。"
	if absf(float(position[1]))>0.001:return "床面の高さが不正です。"
	var center:=Vector2(float(position[0]),float(position[2]));var rectangle:=footprint(id,center,rotation_y)
	var main:=Rect2(-5.82,-4.80,11.64,9.35);var annex:=Rect2(6.12,0.12,5.75,4.73)
	if not main.encloses(rectangle) and not (expanded and annex.encloses(rectangle)):return "床の範囲外です。"
	for fixed in _static_rects():
		if rectangle.intersects(fixed):return "現在の位置に障害物があります。"
	var proposed: Array=[]
	for original in orders:
		var other_id:=str(original.get("id",""))
		if other_id==id:continue
		if _installed(original) and other_id in FLOOR_IDS and rectangle.intersects(footprint(other_id,_stored_position(original),_rotation(original))):return "設置済みの設備に重なります。"
		proposed.append(original)
	proposed.append({"id":id,"status":"installed","install_position":position,"rotation_y":rotation_y})
	if not _access_transition_ok(orders,proposed,id,expanded):return UI.copy("equipment_route_blocked")
	return ""
