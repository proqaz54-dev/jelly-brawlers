class_name JellyPlayer
extends Node3D
## 3D jelly ragdoll brawler (Gang Beasts style): a chain of RigidBody3D spheres
## held together by a tiny spring-impulse solver on top of the Godot physics.

signal on_hit(pos: Vector3, col: Color)

enum Body { TORSO = 0, HEAD = 1, HAND_L = 2, HAND_R = 3, FOOT_L = 4, FOOT_R = 5 }

const RADII := {
	Body.TORSO: 0.55, Body.HEAD: 0.38, Body.HAND_L: 0.30,
	Body.HAND_R: 0.30, Body.FOOT_L: 0.32, Body.FOOT_R: 0.32,
}
const MASS := {
	Body.TORSO: 2.0, Body.HEAD: 1.1, Body.HAND_L: 0.8,
	Body.HAND_R: 0.8, Body.FOOT_L: 0.9, Body.FOOT_R: 0.9,
}
const SPRINGS := [
	[Body.TORSO, Body.HEAD, 0.62],
	[Body.TORSO, Body.HAND_L, 0.56],
	[Body.TORSO, Body.HAND_R, 0.56],
	[Body.TORSO, Body.FOOT_L, 0.78],
	[Body.TORSO, Body.FOOT_R, 0.78],
	[Body.HEAD, Body.HAND_L, 0.74],
	[Body.HEAD, Body.HAND_R, 0.74],
]
const SPRING_FORCE := 260.0
const SPRING_DAMP := 32.0
const MAX_SPRING_PUSH := 30.0
const MOVE_FORCE := 55.0
const JUMP_V := 26.0
const PUNCH_IMP := 30.0
const KICK_IMP := 40.0
const HIT_RADIUS := 0.95
const KILL_Y := -1.0
const FACE_Z := 0.26

var color_main := Color(0.32, 0.66, 1.0)
var color_dark := Color(0.14, 0.38, 0.66)
var color_light := Color(0.75, 0.91, 1.0)

var parts: Dictionary = {}
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
var flail := 0.0

var grounded := false
var fell := false
var facing := 1.0
var active := false

var _face: Node3D
var _eye_mat := StandardMaterial3D.new()

func _ready() -> void:
	_eye_mat.albedo_color = Color(0.06, 0.05, 0.1)
	_build_body()
	_build_face()

func set_palette(main: Color, dark: Color, light: Color) -> void:
	color_main = main
	color_dark = dark
	color_light = light
	for k in parts.keys():
		var b: RigidBody3D = parts[k]
		var mi: MeshInstance3D = b.get_node("Mesh")
		if mi == null:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = main
		mat.roughness = 0.45
		mat.metallic = 0.0
		mi.material_override = mat

func _build_body() -> void:
	for k in [Body.TORSO, Body.HEAD, Body.HAND_L, Body.HAND_R, Body.FOOT_L, Body.FOOT_R]:
		var b := RigidBody3D.new()
		b.name = "part%d" % k
		b.mass = MASS[k]
		b.collision_layer = 2
		b.collision_mask = 1 | 2
		b.linear_damp = 0.6
		b.angular_damp = 6.0
		b.can_sleep = false
		b.gravity_scale = 1.0
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = RADII[k]
		cs.shape = sph
		b.add_child(cs)
		var sm := SphereMesh.new()
		sm.radius = RADII[k]
		sm.height = RADII[k] * 2.0
		sm.radial_segments = 32
		sm.rings = 16
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = sm
		b.add_child(mi)
		parts[k] = b
		add_child(b)
	set_palette(color_main, color_dark, color_light)

func _build_face() -> void:
	_face = Node3D.new()
	add_child(_face)
	for l in [-1.0, 1.0]:
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		sm.radial_segments = 16
		sm.rings = 8
		var em := MeshInstance3D.new()
		em.mesh = sm
		em.material_override = _eye_mat
		_face.add_child(em)
		em.position = Vector3(0.0, l * 0.09, FACE_Z)

func place(p: Vector3) -> void:
	var t: Vector3 = p
	parts[Body.TORSO].global_position = t
	parts[Body.HEAD].global_position = t + Vector3(0, 0.62, 0)
	parts[Body.HAND_L].global_position = t + Vector3(-0.52, 0.0, 0)
	parts[Body.HAND_R].global_position = t + Vector3(0.52, 0.0, 0)
	parts[Body.FOOT_L].global_position = t + Vector3(-0.3, -0.34, 0)
	parts[Body.FOOT_R].global_position = t + Vector3(0.3, -0.34, 0)
	for k in parts.keys():
		parts[k].linear_velocity = Vector3.ZERO
		parts[k].angular_velocity = Vector3.ZERO
	fell = false
	punch_t = 0.0
	kick_t = 0.0
	pull_t = 0.0
	hit_done = false
	grounded = false

func set_active(b: bool) -> void:
	active = b

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
	return parts[Body.TORSO].global_position

func _physics_process(delta: float) -> void:
	if not active and not fell:
		return
	_update_grounded()
	_solve_springs(delta)
	if not fell:
		_apply_controls(delta)
		_advance_attack(delta)

func _update_grounded() -> void:
	grounded = false
	for k in [Body.FOOT_L, Body.FOOT_R]:
		var p: Vector3 = parts[k].global_position
		if p.y > -0.05 and p.y < 0.4 and absf(p.x) > 0.95 and absf(p.z) < 6.5:
			grounded = true
			return

func _solve_springs(_delta: float) -> void:
	for s in SPRINGS:
		var a: RigidBody3D = parts[s[0]]
		var b: RigidBody3D = parts[s[1]]
		var rest: float = s[2]
		var d: Vector3 = b.global_position - a.global_position
		var dist := d.length()
		if dist < 1e-4:
			continue
		var dir := d / dist
		var err := dist - rest
		var rel: float = (b.linear_velocity - a.linear_velocity).dot(dir)
		var push := clampf(err * SPRING_FORCE + rel * SPRING_DAMP, -MAX_SPRING_PUSH, MAX_SPRING_PUSH)
		var imp := dir * (push * 0.5)
		a.apply_central_impulse(imp)
		b.apply_central_impulse(-imp)

func _apply_controls(delta: float) -> void:
	if absf(move_dir.x) > 0.15:
		facing = signf(move_dir.x)
	elif absf(parts[Body.TORSO].linear_velocity.x) > 0.4:
		facing = signf(parts[Body.TORSO].linear_velocity.x)

	var m := Vector3(move_dir.x, 0.0, -move_dir.y)
	if m.length() > 1.0:
		m = m.normalized()
	parts[Body.TORSO].apply_central_impulse(m * MOVE_FORCE * parts[Body.TORSO].mass * delta)
	parts[Body.HEAD].apply_central_impulse(m * MOVE_FORCE * 0.35 * parts[Body.HEAD].mass * delta)

	if want_jump and grounded:
		parts[Body.TORSO].apply_central_impulse(Vector3(0, JUMP_V, 0) * parts[Body.TORSO].mass)
		parts[Body.FOOT_L].apply_central_impulse(Vector3(0, JUMP_V * 0.6, 0) * parts[Body.FOOT_L].mass)
		parts[Body.FOOT_R].apply_central_impulse(Vector3(0, JUMP_V * 0.6, 0) * parts[Body.FOOT_R].mass)

func aim_dir() -> Vector3:
	if opponent != null and not opponent.fell:
		var torso: RigidBody3D = parts[Body.TORSO]
		var d: Vector3 = opponent.torso_pos() - torso.global_position
		if d.length() > 0.01:
			return d.normalized()
	return Vector3(facing, 0.0, 0.0)

func _advance_attack(delta: float) -> void:
	if want_punch and punch_t <= 0.0 and kick_t <= 0.0 and pull_t <= 0.0:
		punch_t = 0.16
		side = 1 - side
		hit_done = false
		attack_dir = aim_dir()
	if want_kick and punch_t <= 0.0 and kick_t <= 0.0 and pull_t <= 0.0:
		kick_t = 0.15
		hit_done = false
		attack_dir = aim_dir()

	if punch_t > 0.0:
		flail += delta * 40.0
		var hand: RigidBody3D = parts[Body.HAND_L if side == 0 else Body.HAND_R]
		var perp := Vector3(-attack_dir.z, 0.0, attack_dir.x)
		var dir := (attack_dir + perp * sin(flail) * 0.5).normalized()
		hand.apply_central_impulse(dir * PUNCH_IMP * hand.mass)
		punch_t -= delta
		_check_hit(hand.global_position, false)
		if punch_t <= 0.0:
			pull_t = 0.12
	elif pull_t > 0.0:
		var hand: RigidBody3D = parts[Body.HAND_L if side == 0 else Body.HAND_R]
		hand.apply_central_impulse(-attack_dir * PUNCH_IMP * 0.5 * hand.mass)
		pull_t -= delta
	elif kick_t > 0.0:
		flail += delta * 30.0
		var foot: RigidBody3D = parts[Body.FOOT_L if attack_dir.x > 0.0 else Body.FOOT_R]
		var perp := Vector3(-attack_dir.z, 0.0, attack_dir.x)
		var dir := (attack_dir + perp * sin(flail) * 0.35).normalized()
		foot.apply_central_impulse(dir * KICK_IMP * foot.mass)
		kick_t -= delta
		_check_hit(foot.global_position, true)
		if kick_t <= 0.0:
			pull_t = 0.14

func _check_hit(pos: Vector3, strong: bool) -> void:
	if opponent == null or hit_done or opponent.fell:
		return
	if pos.distance_to(opponent.torso_pos()) > HIT_RADIUS:
		return
	hit_done = true
	var power := KICK_IMP if strong else PUNCH_IMP
	var dir := attack_dir
	for k in opponent.parts.keys():
		var p: RigidBody3D = opponent.parts[k]
		var weight := 1.0 if k == Body.TORSO else (0.75 if k == Body.HEAD else 0.55)
		var jit := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.5
		p.apply_central_impulse((dir * power * weight + jit) * p.mass)
	on_hit.emit(pos, color_main)