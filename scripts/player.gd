class_name JellyPlayer
extends Node2D
## Jelly ragdoll brawler: a chain of RigidBody2D circles held together by
## spring impulses (a tiny constraint solver on top of the Godot physics engine).

signal on_hit(pos: Vector2, col: Color)

enum Body { TORSO = 0, HEAD = 1, HAND_L = 2, HAND_R = 3, FOOT_L = 4, FOOT_R = 5 }

const RADII := {
	Body.HEAD: 0.38, Body.TORSO: 0.34, Body.HAND_L: 0.24,
	Body.HAND_R: 0.24, Body.FOOT_L: 0.27, Body.FOOT_R: 0.27,
}
const MASS := {
	Body.HEAD: 0.5, Body.TORSO: 1.0, Body.HAND_L: 0.35,
	Body.HAND_R: 0.35, Body.FOOT_L: 0.42, Body.FOOT_R: 0.42,
}
const SPRINGS := [
	[Body.TORSO, Body.HEAD, 0.55],
	[Body.TORSO, Body.HAND_L, 0.62],
	[Body.TORSO, Body.HAND_R, 0.62],
	[Body.TORSO, Body.FOOT_L, 0.82],
	[Body.TORSO, Body.FOOT_R, 0.82],
	[Body.HEAD, Body.HAND_L, 0.78],
	[Body.HEAD, Body.HAND_R, 0.78],
]
const SPRING_FORCE := 60.0
const MOVE_ACC := 9.0
const JUMP_V := 9.5
const PUNCH_IMP := 11.0
const KICK_IMP := 14.0
const HIT_RADIUS := 0.6
const FLOOR_Y := 3.6
const GAP := 1.05
const KILL_Y := 4.8

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
var attack_dir := Vector2.RIGHT
var flail := 0.0

var grounded := false
var fell := false
var facing := 1.0
var active := false

func _ready() -> void:
	_build_body()

func set_palette(main: Color, dark: Color, light: Color) -> void:
	color_main = main
	color_dark = dark
	color_light = light
	for k in parts.keys():
		var art: BodyArt = parts[k].get_node("Art")
		art.mainc = main
		art.darkc = dark
		art.lightc = light
		art.kind = k
		art.queue_redraw()

func _build_body() -> void:
	for k in [Body.TORSO, Body.HEAD, Body.HAND_L, Body.HAND_R, Body.FOOT_L, Body.FOOT_R]:
		var b := RigidBody2D.new()
		b.name = "part%d" % k
		b.mass = MASS[k]
		b.collision_layer = 2
		b.collision_mask = 1 | 2
		b.gravity_scale = 1.0
		b.linear_damp = 1.2
		b.angular_damp = 3.0
		b.can_sleep = false
		var shape := CircleShape2D.new()
		shape.radius = RADII[k]
		var col := CollisionShape2D.new()
		col.shape = shape
		b.add_child(col)
		var art := BodyArt.new()
		art.name = "Art"
		art.r = RADII[k]
		art.kind = k
		b.add_child(art)
		parts[k] = b
		add_child(b)

func place(p: Vector2) -> void:
	parts[Body.TORSO].global_position = p
	parts[Body.HEAD].global_position = p + Vector2(0, -0.6)
	parts[Body.HAND_L].global_position = p + Vector2(-0.35, -0.32)
	parts[Body.HAND_R].global_position = p + Vector2(0.35, -0.32)
	parts[Body.FOOT_L].global_position = p + Vector2(-0.24, 0.6)
	parts[Body.FOOT_R].global_position = p + Vector2(0.24, 0.6)
	for k in parts.keys():
		parts[k].linear_velocity = Vector2.ZERO
		parts[k].angular_velocity = 0.0
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

func torso_pos() -> Vector2:
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
		var p: Vector2 = parts[k].global_position
		if p.y > FLOOR_Y - 0.35 and p.y < FLOOR_Y + 0.35 and absf(p.x) > GAP:
			grounded = true
			return

func _solve_springs(_delta: float) -> void:
	for s in SPRINGS:
		var a: RigidBody2D = parts[s[0]]
		var b: RigidBody2D = parts[s[1]]
		var rest: float = s[2]
		var d: Vector2 = b.global_position - a.global_position
		var dist := d.length()
		if dist < 1e-4:
			continue
		var dir := d / dist
		var err := dist - rest
		var rel: float = (b.linear_velocity - a.linear_velocity).dot(dir)
		var imp := dir * (err * SPRING_FORCE + rel * 3.0) * 0.5
		a.apply_central_impulse(imp)
		b.apply_central_impulse(-imp)

func _apply_controls(delta: float) -> void:
	if absf(move_dir.x) > 0.15:
		facing = signf(move_dir.x)
	elif absf(parts[Body.TORSO].linear_velocity.x) > 0.4:
		facing = signf(parts[Body.TORSO].linear_velocity.x)

	var m := move_dir
	if m.length() > 1.0:
		m = m.normalized()
	parts[Body.TORSO].apply_central_impulse(m * MOVE_ACC * parts[Body.TORSO].mass * delta)
	parts[Body.HEAD].apply_central_impulse(m * MOVE_ACC * 0.35 * parts[Body.HEAD].mass * delta)

	if want_jump and grounded:
		parts[Body.TORSO].apply_central_impulse(Vector2(0, -JUMP_V) * parts[Body.TORSO].mass)
		parts[Body.FOOT_L].apply_central_impulse(Vector2(0, -JUMP_V * 0.7) * parts[Body.FOOT_L].mass)
		parts[Body.FOOT_R].apply_central_impulse(Vector2(0, -JUMP_V * 0.7) * parts[Body.FOOT_R].mass)

func aim_dir() -> Vector2:
	if opponent != null and not opponent.fell:
		var torso: RigidBody2D = parts[Body.TORSO]
		var d: Vector2 = opponent.torso_pos() - torso.global_position
		if d.length() > 0.01:
			return d.normalized()
	return Vector2(facing, 0.0)

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
		var hand: RigidBody2D = parts[Body.HAND_L if side == 0 else Body.HAND_R]
		var perp := Vector2(-attack_dir.y, attack_dir.x)
		var dir: Vector2 = (attack_dir + perp * sin(flail) * 0.5).normalized()
		hand.apply_central_impulse(dir * PUNCH_IMP * hand.mass)
		punch_t -= delta
		_check_hit(hand.global_position, false)
		if punch_t <= 0.0:
			pull_t = 0.12
	elif pull_t > 0.0:
		var hand: RigidBody2D = parts[Body.HAND_L if side == 0 else Body.HAND_R]
		hand.apply_central_impulse(-attack_dir * PUNCH_IMP * 0.5 * hand.mass)
		pull_t -= delta
	elif kick_t > 0.0:
		flail += delta * 30.0
		var foot: RigidBody2D = parts[Body.FOOT_R if attack_dir.x > 0.0 else Body.FOOT_L]
		var perp := Vector2(-attack_dir.y, attack_dir.x)
		var dir: Vector2 = (attack_dir + perp * sin(flail) * 0.35).normalized()
		foot.apply_central_impulse(dir * KICK_IMP * foot.mass)
		kick_t -= delta
		_check_hit(foot.global_position, true)
		if kick_t <= 0.0:
			pull_t = 0.14

func _check_hit(pos: Vector2, strong: bool) -> void:
	if opponent == null or hit_done or opponent.fell:
		return
	if pos.distance_to(opponent.torso_pos()) > HIT_RADIUS:
		return
	hit_done = true
	var power := KICK_IMP if strong else PUNCH_IMP
	var dir := attack_dir
	for k in opponent.parts.keys():
		var p: RigidBody2D = opponent.parts[k]
		var weight := 1.0 if k == Body.TORSO else (0.75 if k == Body.HEAD else 0.55)
		var jit := Vector2(randf() - 0.5, randf() - 0.5) * 2.5
		p.apply_central_impulse((dir * power * weight + jit) * p.mass)
	on_hit.emit(pos, color_main)

class BodyArt:
	extends Node2D
	## Gang-Beasts style: glossy squishy blob with wobble, sheen and a face.

	var r := 0.3
	var mainc := Color.WHITE
	var darkc := Color.BLACK
	var lightc := Color(1, 1, 1, 0.7)
	var kind := 0

	func _draw() -> void:
		var rb: RigidBody2D = get_parent()
		var vel: Vector2 = rb.linear_velocity
		var sp := vel.length()
		var k := clampf(sp * 0.010, 0.0, 0.30)
		var sx := 1.0 + k
		var sy := 1.0 - k * 0.75
		if kind == JellyPlayer.Body.TORSO:
			sx *= 1.18
			sy *= 0.90
		var ang := vel.angle() if sp > 0.5 else 0.0
		draw_set_transform(Vector2.ZERO, ang, Vector2(sx, sy))

		var outline := Color(0.07, 0.05, 0.11, 0.95)
		var o := r + 0.065
		draw_circle(Vector2.ZERO, o, outline)
		draw_circle(Vector2.ZERO, r, mainc)
		draw_circle(Vector2(0.0, r * 0.30), r * 0.80, Color(darkc.r, darkc.g, darkc.b, 0.55))
		draw_circle(Vector2(-r * 0.26, -r * 0.30), r * 0.52, Color(1, 1, 1, 0.26))
		draw_circle(Vector2(-r * 0.40, -r * 0.44), r * 0.20, Color(1, 1, 1, 0.82))
		draw_arc(Vector2.ZERO, r * 0.92, -0.5, 1.1, 18, Color(1, 1, 1, 0.38), r * 0.13)

		if kind == JellyPlayer.Body.HEAD:
			var pl: JellyPlayer = get_parent().get_parent()
			var f := pl.facing
			draw_circle(Vector2(f * 0.15, -0.03), 0.13, Color(1, 1, 1, 0.98))
			draw_circle(Vector2(f * 0.215, -0.03), 0.058, Color(0.08, 0.07, 0.12))
			draw_line(Vector2(f * -0.02, -0.24), Vector2(f * 0.26, -0.18), Color(0.08, 0.07, 0.12), 0.055)
			draw_arc(Vector2(f * 0.26, 0.15), 0.065, 0.35, 2.4, 8, Color(0.08, 0.07, 0.12), 0.032)
		elif kind == JellyPlayer.Body.HAND_L or kind == JellyPlayer.Body.HAND_R:
			var pl: JellyPlayer = get_parent().get_parent()
			var f := pl.facing
			draw_circle(Vector2(f * 0.16, 0.10), r * 0.52, outline)
			draw_circle(Vector2(f * 0.16, 0.10), r * 0.42, mainc)
			draw_circle(Vector2(f * 0.06, 0.02), r * 0.20, Color(1, 1, 1, 0.5))
		elif kind == JellyPlayer.Body.FOOT_L or kind == JellyPlayer.Body.FOOT_R:
			var pl: JellyPlayer = get_parent().get_parent()
			var f := pl.facing
			draw_circle(Vector2(f * 0.18, 0.10), r * 0.46, Color(darkc.r, darkc.g, darkc.b, 0.9))
			draw_circle(Vector2(f * 0.16, 0.08), r * 0.34, mainc)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)