extends RefCounted
## Existing rigs, posed in skeleton space. No extra skeleton, physics or animation assets.
## https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html
var skeleton: Skeleton3D
var model: Node3D
var bones: Dictionary = {}
var base_rotations: Dictionary = {}
var elapsed := 0.0
var rig_basis := Basis.IDENTITY
var arm_targets: Array[Vector3] = []
var sit_ground_y := 0.0
var sit_forward := 0.0
var leg_targets: Dictionary = {}
var detached_offsets: Dictionary = {}

func _index(name: String) -> int:
	if not bones.has(name): bones[name]=skeleton.find_bone(name)
	return int(bones[name])

func _aim(name: String, child: String, direction: Vector3) -> void:
	var index := _index(name); var child_index := _index(child)
	if index<0 or child_index<0: return
	var pose := skeleton.get_bone_global_pose(index)
	# Foot.* are IK controls, not children of LowerLeg.* in this imported rig.
	var current := pose.basis.y if name.begins_with("LowerLeg") else skeleton.get_bone_global_pose(child_index).origin-pose.origin
	var turn := Quaternion(current.normalized(),(rig_basis*direction).normalized())
	var desired := Basis(turn)*pose.basis
	var parent := skeleton.get_bone_parent(index)
	var local_basis := skeleton.get_bone_global_pose(parent).basis.inverse()*desired if parent>=0 else desired
	skeleton.set_bone_pose_rotation(index,local_basis.orthonormalized().get_rotation_quaternion())

func _aim_to_point(name: String, child: String, target_world: Vector3) -> void:
	var index := _index(name); var child_index := _index(child)
	if index < 0 or child_index < 0: return
	var pose := skeleton.get_bone_global_pose(index)
	var child_pose := skeleton.get_bone_global_pose(child_index)
	var target_skeleton := skeleton.to_local(target_world)
	var current := child_pose.origin - pose.origin
	var desired := target_skeleton - pose.origin
	if current.length_squared() < 0.0001 or desired.length_squared() < 0.0001: return
	var turn := Quaternion(current.normalized(),desired.normalized())
	var desired_basis := Basis(turn) * pose.basis
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(index,(parent_basis.inverse() * desired_basis).orthonormalized().get_rotation_quaternion())

func _two_bone_to_point(side: String, target_world: Vector3) -> void:
	var upper_index := _index("UpperArm."+side)
	var lower_index := _index("LowerArm."+side)
	var wrist_index := _index("Wrist."+side)
	if upper_index < 0 or lower_index < 0 or wrist_index < 0: return
	var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(upper_index).origin)
	var elbow := skeleton.to_global(skeleton.get_bone_global_pose(lower_index).origin)
	var wrist := skeleton.to_global(skeleton.get_bone_global_pose(wrist_index).origin)
	var upper_length := maxf(0.001,shoulder.distance_to(elbow))
	var lower_length := maxf(0.001,elbow.distance_to(wrist))
	var offset := target_world - shoulder
	if offset.length_squared() < 0.0001: return
	var direction := offset.normalized()
	var minimum_reach := absf(upper_length-lower_length)+0.001
	var maximum_reach := maxf(minimum_reach,upper_length+lower_length-0.001)
	var reach := clampf(offset.length(),minimum_reach,maximum_reach)
	var reachable_target := shoulder + direction*reach
	# A down-and-out pole selects the natural elbow side while the cosine law
	# keeps both imported bone lengths intact at every target distance.
	var side_sign := -1.0 if side == "L" else 1.0
	var pole_hint := Vector3(side_sign*0.72,-0.78,0.16)
	var pole := pole_hint-direction*pole_hint.dot(direction)
	if pole.length_squared() < 0.0001:
		pole = Vector3.UP-direction*direction.y
	pole = pole.normalized()
	var cosine := clampf((upper_length*upper_length+reach*reach-lower_length*lower_length)/(2.0*upper_length*reach),-1.0,1.0)
	var sine := sqrt(maxf(0.0,1.0-cosine*cosine))
	var elbow_target := shoulder + direction*(cosine*upper_length) + pole*(sine*upper_length)
	_aim_to_point("UpperArm."+side,"LowerArm."+side,elbow_target)
	_aim_to_point("LowerArm."+side,"Wrist."+side,reachable_target)

func _two_bone_leg_to_point(side: String, target_world: Vector3) -> void:
	var upper_index := _index("UpperLeg."+side)
	var lower_index := _index("LowerLeg."+side)
	var foot_index := _index("Foot."+side)
	if upper_index < 0 or lower_index < 0 or foot_index < 0: return
	var hip := skeleton.to_global(skeleton.get_bone_global_pose(upper_index).origin)
	var knee := skeleton.to_global(skeleton.get_bone_global_pose(lower_index).origin)
	var ankle := skeleton.to_global(skeleton.get_bone_global_pose(foot_index).origin)
	var upper_length := maxf(0.001,hip.distance_to(knee))
	# Foot.* is detached from LowerLeg, so knee.distance_to(Foot) is not a
	# bone length. The imported Quaternius rig uses equal-length upper/lower
	# leg segments; retain that measured upper segment for the IK chain.
	var lower_length := upper_length
	var offset := target_world-hip
	if offset.length_squared() < 0.000001: return
	var reach := clampf(offset.length(),absf(upper_length-lower_length)+0.002,upper_length+lower_length-0.002)
	var direction := offset.normalized()
	# The pole is in front of the worker. It prevents the imported legs from
	# folding backwards when the chair target is close to the hips.
	var pole_hint := Vector3(0.0,0.12,0.95)
	if side == "L": pole_hint.x = -0.10
	else: pole_hint.x = 0.10
	var pole := pole_hint-direction*pole_hint.dot(direction)
	if pole.length_squared() < 0.000001: pole=Vector3.FORWARD-direction*direction.z
	pole= pole.normalized()
	var cosine := clampf((upper_length*upper_length+reach*reach-lower_length*lower_length)/(2.0*upper_length*reach),-1.0,1.0)
	var sine := sqrt(maxf(0.0,1.0-cosine*cosine))
	var knee_target := hip+direction*(cosine*upper_length)+pole*(sine*upper_length)
	_aim_to_point("UpperLeg."+side,"LowerLeg."+side,knee_target)
	_aim_to_point("LowerLeg."+side,"Foot."+side,target_world)
	# Foot.* and PT.* are detached Root skin bones. Their imported positions are
	# IK controls far below the visible ankle, so rotation alone leaves the
	# weighted shoe floating. Move both skin anchors to the solved floor point,
	# while preserving their imported rest rotations.
	var target_local := skeleton.to_local(target_world)
	var foot_detached := _index("Foot."+side)
	if foot_detached >= 0: skeleton.set_bone_pose_position(foot_detached,target_local)
	var pt_detached := _index("PT."+side)
	if pt_detached >= 0:
		var detached_offset: Vector3=detached_offsets.get(side,Vector3.ZERO)
		skeleton.set_bone_pose_position(pt_detached,target_local+detached_offset)

func setup(value: Node3D, targets: Array[Vector3] = []) -> bool:
	model=value
	arm_targets = targets
	var found := model.find_children("*","Skeleton3D",true,false)
	if found.is_empty(): return false
	skeleton=found[0]
	for player in model.find_children("*","AnimationPlayer",true,false): player.stop(); player.active=false
	skeleton.reset_bone_poses()
	rig_basis=skeleton.global_basis.inverse()*model.global_basis
	for side in ["L","R"]:
		var foot_index := _index("Foot."+side)
		var pt_index := _index("PT."+side)
		if foot_index >= 0 and pt_index >= 0:
			detached_offsets[side]=skeleton.get_bone_global_pose(pt_index).origin-skeleton.get_bone_global_pose(foot_index).origin
	# Capture the actual imported leg geometry before posing. These values are
	# used to place feet on the floor and keep both knees bending forward.
	for side in ["L","R"]:
		var lower_index := _index("LowerLeg."+side)
		if lower_index >= 0:
			# Foot.* is a detached IK/skin control whose imported origin is not
			# the ankle. Use a model-space floor target from the actual leg chain.
			var sign := -1.0 if side == "R" else 1.0
			leg_targets[side] = model.to_global(Vector3(sign*0.12,0.035,0.20))
		var parent := model.get_parent()
		sit_ground_y=float(parent.global_position.y) if parent else 0.0
	for side in ["L","R"]:
		var original: Vector3=leg_targets.get(side,Vector3.ZERO)
		var foot_target := original
		foot_target.y=sit_ground_y+0.035
		# Move feet slightly toward the desk, based on their real imported x
		# separation. No guessed 90-degree bone rotations are used.
		foot_target += model.global_basis * Vector3(0.0,0.0,0.13)
		leg_targets[side]=foot_target
		_two_bone_leg_to_point(side,foot_target)
		_aim("UpperArm."+side,"LowerArm."+side,Vector3(0.12 if side=="L" else -0.12,-0.83,0.55))
		_aim("LowerArm."+side,"Wrist."+side,Vector3(0,-0.35,0.94))
	var hips := _index("Hips")
	if hips>=0:
		var height: float=skeleton.to_global(skeleton.get_bone_global_pose(hips).origin).y-sit_ground_y
		# Seat height follows the actual hip/foot geometry and remains stable
		# when the source model scale changes.
		model.position.y+=0.78-height
	# Re-solve once after the model's measured seat-height correction so the
	# final ankle positions, rather than the pre-correction ones, touch floor.
	for side in ["L","R"]:
		if leg_targets.has(side):
			var final_target: Vector3=leg_targets[side]
			final_target.y=sit_ground_y+0.035
			leg_targets[side]=final_target
			_two_bone_leg_to_point(side,final_target)
	for name in ["Head","Wrist.L","Wrist.R","Chest","UpperArm.L","LowerArm.L","UpperArm.R","LowerArm.R"]:
		var index := _index(name)
		if index>=0: base_rotations[name]=skeleton.get_bone_pose_rotation(index)
	return true

func update(working: bool, reporting: bool, delta: float) -> void:
	if skeleton==null: return
	elapsed+=delta
	for name in base_rotations:
		var change := Vector3.ZERO
		if name=="Head": change=Vector3(-0.04,0.32 if reporting else sin(elapsed*0.45)*0.025,0)
		elif name=="Chest": change.x=sin(elapsed*1.5)*0.006
		elif working and name.begins_with("Wrist"): change.x=sin(elapsed*9.0+(0.0 if name=="Wrist.L" else PI))*0.025
		skeleton.set_bone_pose_rotation(_index(name),base_rotations[name]*Quaternion.from_euler(change))
	# Both hands stay attached to the actual desk controls. Solve the imported
	# upper/lower arm lengths instead of lerping an elbow toward an unreachable
	# point, which produces the straight floating arm pose.
	if arm_targets.size() >= 2:
		for side in ["L","R"]:
			var target := arm_targets[0] if side == "L" else arm_targets[1]
			_two_bone_to_point(side,target)
