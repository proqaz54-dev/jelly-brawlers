class_name JellyPlayer
extends Node3D
## Gang-Beasts style puppet: rigid spheres/capsules chained by a soft
## spring solver, muscles (joint torques) drive an IK gait.

signal on_hit(pos: Vector3, col: Color)

const MOVE_FORCE := 34.0
const JUMP_V := 7.5
const PUNCH_IMP := 10.0
const KICK_IMP := 14.0
const HIT_RADIUS := 1.05
const KILL_Y := -1.0

const SPRING_FORCE := 300.0
const SPRING_DAMP := 40.0
const MAX_PUSH := 34.0
const SERVO_ANG := 36.0
const SERVO_DAMP := 6.0

const FACE_Z := 0.3
const HIP_SIDE := 0.14

const LEG_L1 := 0.3
const LEG_L2 := 0.3
const ARM_L1 := 0.22
const ARM_L2 := 0.2

var color_main := Color(0.35, 0.72, 1.0)
var color_dark := Color(0.14, 0.38, 0.66)
var color_light := Color(0.75, 0.91, 1.0)

# [id, r, mass, center pos, kind(0 sphere / 1 capsule), bone len]
const SPEC := [
	["torso", 0.4, 3.2, Vector3(0, 0.78, 0), 0, 0.0],
	["head", 0.26, 1.1, Vector3(0, 1.24, 0), 0, 0.0],
	["uarm_l", 0.14, 0.5, Vector3(-0.5, 0.88, 0), 1, 0.32],
	["uarm_r", 0.14, 0.5, Vector3(0.5, 0.88, 0), 1, 0.32],
	["frm_l", 0.12, 0.4, Vector3(-0.52, 0.62, 0), 1, 0.26],
	["frm_r", 0.12, 0.4, Vector3(0.52, 0.62, 0), 1, 0.26],
	["hand_l", 0.19, 0.6, Vector3(-0.54, 0.38, 0), 0, 0.0],
	["hand_r", 0.19, 0.6, Vector3(0.54, 0.38, 0), 0, 0.0],
	["thigh_l", 0.14, 1.0, Vector3(-HIP_SIDE, 0.5, 0), 1, 0.32],
	["thigh_r", 0.14, 1.0, Vector3(HIP_SIDE, 0.5, 0), 1, 0.32],
	["shin_l", 0.12, 0.7, Vector3(-HIP_SIDE, 0.24, 0), 1, 0.26],
	["shin_r", 0.12, 0.7, Vector3(HIP_SIDE, 0.24, 0), 1, 0.26],
	["foot_l", 0.17, 0.8, Vector3(-HIP_SIDE, 0.07, 0), 0, 0.0],
	["foot_r", 0.17, 0.8, Vector3(HIP_SIDE, 0.07, 0), 0, 0.0],
]

const LINKS := [
	["torso", "head"],
	["torso", "uarm_l"], ["torso", "uarm_r"],
	["uarm_l", "frm_l"], ["uarm_r", "frm_r"],
	["frm_l", "hand_l"], ["frm_r", "hand_r"],
	["torso", "thigh_l"], ["torso", "thigh_r"],
	["thigh_l", "shin_l"], ["thigh_r", "shin_r"],
	["shin_l", "foot_l"], ["shin_r", "foot_r"],
]

var parts := {}
var springs := {}

var opponent: JellyPlayer = null
var move_dir := Vector2.ZERO
var want_punch := false
var want_kick := false
var want_jump := false

var punch_t := 0.0
var kick_t := 0.0
var pull_t := 0.0
var side := 0
var hit_done := false
var attack_dir := Vector3.RIGHT

var grounded := false
var fell := false
var facing := 1.0
var active := true
var t_gait := 0.0

var _eye_mat := StandardMaterial3D.new()

func _ready() -> void:
	_eye_mat.albedo_color = Color(0.045, 0.04, 0.08)
	_build_body()
	_build_face()

func set_palette(main: Color, dark: Color, light: Color) -> void:
	color_main = main
	color_dark = dark
	color_light = light
	for k in parts.keys():
		var b: RigidBody3D = parts[k]
		var mi2: MeshInstance3D = b.get_node("Mesh")
		if mi2 == null:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = main
		mat.roughness = 0.5
		mat.metallic = 0.0
		mi2.material_override = mat

func _build_body() -> void:
	for s in SPEC:
		var id: String = s[0]
		var r: float = s[1]
		var pos: Vector3 = s[3]
		var kind: int = s[4]
		var blen: float = s[5]
		var b := RigidBody3D.new()
		b.name = id
		b.mass = s[2]
		b.collision_layer = 2
		b.collision_mask = 1
		b.linear_damp = 0.3
		b.angular_damp = 1.4
		b.can_sleep = false
		b.gravity_scale = 1.0
		var cs := CollisionShape3D.new()
		if kind == 0:
			var sph := SphereShape3D.new()
			sph.radius = r
			cs.shape = sph
		else:
			var cap := CapsuleShape3D.new()
			cap.radius = r
			cap.height = blen + r * 2.0
			cs.shape = cap
		b.add_child(cs)
		b.position = pos
		add_child(b)
		parts[id] = b
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color_main
		mat.roughness = 0.5
		mat.metallic = 0.0
		var msh: Mesh
		if kind == 0:
			var sm := SphereMesh.new()
			sm.radius = r
			sm.height = r * 2.0
			sm.radial_segments = 22
			sm.rings = 11
			msh = sm
		else:
			var cm := CapsuleMesh.new()
			cm.radius = r
			cm.height = blen + r * 2.0
			cm.radial_segments = 14
			cm.rings = 6
			msh = cm
		var mi2 := MeshInstance3D.new()
		mi2.name = "Mesh"
		mi2.mesh = msh
		mi2.material_override = mat
		b.add_child(mi2)

	for ln in LINKS:
		var a: RigidBody3D = parts[ln[0]]
		var cb: RigidBody3D = parts[ln[1]]
		var rest: float = (cb.position - a.position).length()
		var d := {"a": ln[0], "b": ln[1], "rest": rest}
		springs[ln[1]] = d

func _build_face() -> void:
	var f := Node3D.new()
	f.name = "Face"
	parts["head"].add_child(f)
	for l in [-1.0, 1.0]:
		var sm := SphereMesh.new()
		sm.radius = 0.052
		sm.height = 0.104
		sm.radial_segments = 10
		sm.rings = 5
		var em := MeshInstance3D.new()
		em.name = "Eye"
		em.mesh = sm
		em.material_override = _eye_mat
		f.add_child(em)
		em.position = Vector3(0.0, l * 0.09, FACE_Z)

func place(p: Vector3) -> void:
	for s in SPEC:
		var b: RigidBody3D = parts[s[0]]
		b.global_position = p + s[3]
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
	fell = false
	punch_t = 0.0
	kick_t = 0.0
	pull_t = 0.0
	hit_done = false
	grounded = false
	t_gait = 0.0

func set_active(b2: bool) -> void:
	active = b2

func clear_falling() -> void:
	fell = false

func set_input(dir: Vector2, punch: bool, kick: bool, jump: bool) -> void:
	move_dir = dir
	want_punch = punch
	want_kick = kick
	want_jump = jump

func clear_input() -> void:
	move_dir = Vector2.ZERO
	want_punch = false
	want_kick = false
	want_jump = false

func torso_pos() -> Vector3:
	return parts["torso"].global_position

func _physics_process(delta: float) -> void:
	_solve_springs(delta)
	_update_grounded()
	if not active or fell:
		return
	_advance_attack(delta)
	_drive(delta)

func _solve_springs(_delta: float) -> void:
	for k in springs.keys():
		var s: Dictionary = springs[k]
		var a: RigidBody3D = parts[s["a"]]
		var cb: RigidBody3D = parts[s["b"]]
		var rest: float = s["rest"]
		var d: Vector3 = cb.global_position - a.global_position
		var dist := d.length()
		if dist < 1e-4:
			continue
		var dir := d / dist
		var err := dist - rest
		var rel: float = (cb.linear_velocity - a.linear_velocity).dot(dir)
		var push := clampf(err * SPRING_FORCE + rel * SPRING_DAMP, -MAX_PUSH, MAX_PUSH)
		var imp := dir * (push * 0.5)
		a.apply_central_impulse(imp * a.mass)
		cb.apply_central_impulse(-imp * cb.mass)

func _update_grounded() -> void:
	grounded = false
	if not is_inside_tree():
		return
	var sp := get_world_3d().direct_space_state
	for i in 2:
		var foot: RigidBody3D = parts["foot_r" if i == 1 else "foot_l"]
		var fr := foot.global_position
		var q := PhysicsRayQueryParameters3D.create(fr + Vector3.UP * 0.06, fr + Vector3(0, -0.5, 0), 1)
		q.exclude = [foot]
		if not sp.intersect_ray(q).is_empty():
			grounded = true
			return

func aim_dir() -> Vector3:
	if opponent != null and not opponent.fell:
		var d: Vector3 = opponent.torso_pos() - parts["torso"].global_position
		if d.length() > 0.01:
			return d.normalized()
	return Vector3(facing, 0.0, 0.0)

func _advance_attack(delta: float) -> void:
	if want_punch and punch_t <= 0.0 and kick_t <= 0.0 and pull_t <= 0.0:
		punch_t = 0.22
		side = 1 - side
		hit_done = false
		attack_dir = aim_dir()
		want_punch = false
	if want_kick and punch_t <= 0.0 and kick_t <= 0.0 and pull_t <= 0.0:
		kick_t = 0.2
		hit_done = false
		attack_dir = aim_dir()
		want_kick = false
	if punch_t > 0.0:
		punch_t -= delta
		if punch_t <= 0.0:
			pull_t = 0.14
	elif pull_t > 0.0:
		pull_t -= delta
	elif kick_t > 0.0:
		kick_t -= delta
		if kick_t <= 0.0:
			pull_t = 0.12

func _horizontal(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()

func _drive(delta: float) -> void:
	var torso: RigidBody3D = parts["torso"]
	if absf(move_dir.x) > 0.15:
		facing = signf(move_dir.x)
	elif absf(torso.linear_velocity.x) > 0.25:
		facing = signf(torso.linear_velocity.x)

	var m := Vector3(move_dir.x, 0.0, -move_dir.y)
	var walk := clampf(m.length(), 0.0, 1.0)
	if walk > 0.01:
		m /= walk
	torso.apply_central_impulse(m * MOVE_FORCE * torso.mass * delta)
	torso.apply_central_force(-torso.linear_velocity * 4.0 * torso.mass)
	parts["head"].apply_central_force(m * MOVE_FORCE * 0.12 * parts["head"].mass * delta)

	if want_jump and grounded:
		torso.apply_central_impulse(Vector3(0, JUMP_V, 0) * torso.mass)
		want_jump = false

	t_gait += delta * lerp(0.7, 3.0, walk)

	var fwdv := m if walk > 0.01 else Vector3(facing, 0.0, 0.0)
	var fwd_h := _horizontal(fwdv)
	if fwd_h.length() < 0.01:
		fwd_h = Vector3(facing, 0.0, 0.0)

	var atk := _horizontal(attack_dir)
	var kick_leg := -1
	if kick_t > 0.0:
		kick_leg = 0 if attack_dir.x >= 0.0 else 1

	for i in 2:
		var side_s := 1.0 if i == 1 else -1.0
		var hip := torso.global_position + Vector3(side_s * HIP_SIDE, -0.22, 0)
		var target := Vector3.ZERO
		if kick_t > 0.0 and i == kick_leg:
			target = torso.global_position + atk.normalized() * 1.5 + Vector3(0, -0.1, 0)
		elif kick_t > 0.0:
			target = hip + Vector3(0, -0.6, 0)
		else:
			var ph := t_gait + (PI if i == 1 else 0.0)
			var step := (0.18 + 0.42 * walk) * cos(ph)
			var lift := maxf(0.0, sin(ph)) * (0.12 + 0.15 * walk)
			target = hip + Vector3(step, -0.6 + lift, 0.0)
		_pose_leg(i, torso, target, fwd_h)
		if kick_t > 0.0 and i == kick_leg:
			var fp: RigidBody3D = parts["foot_r" if i == 1 else "foot_l"]
			if fp.global_position.distance_to(target) < 1.0:
				_check_hit(fp.global_position, true)

	var shoulder := torso.global_position + Vector3(0, 0.15, 0)
	if punch_t > 0.0:
		var aim := _horizontal(attack_dir)
		var hst := torso.global_position + aim * 1.4 + Vector3(0, 0.15, 0)
		_pose_arm(side, shoulder, hst, fwd_h)
		var hg: RigidBody3D = parts["hand_r" if side == 1 else "hand_l"]
		_check_hit(hg.global_position, false)
	elif pull_t > 0.0:
		_pose_arm(side, shoulder, torso.global_position + Vector3(side * 0.8, 0.3, 0), fwd_h)
		_pose_arm(1 - side, shoulder, torso.global_position + Vector3(-side * 0.6, -0.15, 0), fwd_h)
	else:
		_pose_arm(0, shoulder, torso.global_position + Vector3(0.4, -0.32, 0), fwd_h)
		_pose_arm(1, shoulder, torso.global_position + Vector3(-0.32, -0.2, 0), fwd_h)

func _pose_leg(i: int, torso: RigidBody3D, tgt: Vector3, fwd: Vector3) -> void:
	var su := "r" if i == 1 else "l"
	var thigh: RigidBody3D = parts["thigh_" + su]
	var shin: RigidBody3D = parts["shin_" + su]
	var dirs := _solver(torso.global_position + Vector3(HIP_SIDE if i == 1 else -HIP_SIDE, -0.22, 0), tgt, LEG_L1, LEG_L2, fwd)
	_bone_shoulder(parts["torso"], thigh, dirs[0])
	_bone_shoulder(thigh, shin, dirs[1])

func _pose_arm(s: int, shoulder: Vector3, tgt: Vector3, fwd: Vector3) -> void:
	var su := "r" if s == 1 else "l"
	var upper: RigidBody3D = parts["uarm_" + su]
	var frm: RigidBody3D = parts["frm_" + su]
	var hand: RigidBody3D = parts["hand_" + su]
	var dirs := _solver(shoulder, tgt, ARM_L1, ARM_L2, fwd)
	_bone_shoulder(parts["torso"], upper, dirs[0])
	_bone_shoulder(upper, frm, dirs[1])
	_bone_shoulder(frm, hand, Vector3(0, -1, 0))

func _solver(par_pos: Vector3, tgt: Vector3, la: float, lb: float, fwd: Vector3) -> Array:
	var fw := _horizontal(fwd)
	if fw.length() < 0.01:
		fw = Vector3.FORWARD
	var d := tgt - par_pos
	var a := d.dot(fw)
	var b := d.dot(Vector3.UP)
	var dist := sqrt(a * a + b * b)
	var D := clampf(dist, absf(la - lb) + 0.02, la + lb - 0.02)
	var alpha := acos(clampf((la * la + D * D - lb * lb) / (2.0 * la * D), -1.0, 1.0))
	var beta := acos(clampf((la * la + lb * lb - D * D) / (2.0 * la * lb), -1.0, 1.0))
	var base := atan2(b, a)
	var t1 := base + alpha
	var t2 := t1 - (PI - beta)
	var d1 := (fw * cos(t1) + Vector3.UP * sin(t1)).normalized()
	var d2 := (fw * cos(t2) + Vector3.UP * sin(t2)).normalized()
	return [d1, d2]

func _bone_shoulder(par: RigidBody3D, child: RigidBody3D, dir: Vector3) -> void:
	var d := dir.normalized()
	if d.length() < 0.001:
		return
	var child_q := child.global_transform.basis.get_rotation_quaternion()
	var cur_bone := child.global_transform.basis.y
	var rot := Quaternion(cur_bone, d)
	_servo_to(par, child, rot * child_q)

func _servo_to(par: RigidBody3D, child: RigidBody3D, target_q: Quaternion) -> void:
	var par_q := par.global_transform.basis.get_rotation_quaternion()
	var child_q := child.global_transform.basis.get_rotation_quaternion()
	var cur_rel := par_q.inverse() * child_q
	var tgt_rel := par_q.inverse() * target_q
	var e := tgt_rel * cur_rel.inverse()
	var v := e.get_axis() * clampf(e.get_angle(), 0.0, 1.4)
	var rel_w := child.angular_velocity - par.angular_velocity
	var trq := v * SERVO_ANG - rel_w * SERVO_DAMP
	child.apply_torque_impulse(_hard_clamp(trq, child.mass * 1.2))
	par.apply_torque_impulse(_hard_clamp(-trq, child.mass * 0.5))

func _hard_clamp(v: Vector3, m: float) -> Vector3:
	var l := v.length()
	if l > m and l > 0.0:
		return v / l * m
	return v

func _check_hit(pos: Vector3, strong: bool) -> void:
	if opponent == null or hit_done or opponent.fell:
		return
	if pos.distance_to(opponent.torso_pos()) > HIT_RADIUS:
		return
	hit_done = true
	opponent._knock(_horizontal(attack_dir), KICK_IMP if strong else PUNCH_IMP, pos, color_main)

func _knock(dir: Vector3, power: float, pos: Vector3, col: Color) -> void:
	for id in parts.keys():
		var p: RigidBody3D = parts[id]
		var w := 1.0 if id == "torso" else (0.75 if id == "head" else 0.4)
		var jit := Vector3(randf() - 0.5, randf() * 0.6, randf() - 0.5) * 4.0
		p.apply_central_impulse((_horizontal(dir) * power * w + jit) * p.mass)
	on_hit.emit(pos, col)