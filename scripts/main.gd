extends Node3D
## Game controller (3D): arena, two jelly ragdoll players, round/match state
## machine, bot AI, particles and camera shake.

enum Mode { MENU = 0, PLAYING = 1, COUNTDOWN = 2, ROUND_OVER = 3, MATCH_OVER = 4 }

const WALL_X := 7.0
const GAP := 0.95
const FLOOR_HALF := 5.0
const WALL_TOP := 1.6
const KILL_Y := -1.0
const ROUND_WINS := 3

var mode := Mode.MENU
var p2_is_bot := true

var p1: JellyPlayer
var p2: JellyPlayer
var ui: TouchUI
var hud: Hud
var cam: Camera3D
var sun: DirectionalLight3D

var countdown_t := 0.0
var play_t := 0.0
var state_t := 0.0
var scores := [0, 0]
var match_winner := -1
var round_result := -1
var shake := 0.0
var ai_timer := 0.0
var sim_t := 0.0

var lava_mat := StandardMaterial3D.new()

func _ready() -> void:
	_build_camera()
	_build_lights()
	_build_arena()
	_build_players()
	_build_ui()
	_go_menu()
	if OS.get_environment("JB_AUTOSTART") != "":
		ui.in_menu = false
		_start_game()

func _build_camera() -> void:
	cam = Camera3D.new()
	cam.position = Vector3(0, 5.4, 9.2)
	cam.fov = 72.0
	add_child(cam)
	cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	cam.make_current()

func _build_lights() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.10, 0.30)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.55, 0.95)
	env.ambient_light_energy = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_normalized = true
	env.glow_hdr_threshold = 1.0
	env.glow_bloom = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.rotation_degrees = Vector3(-55, -32, 0)
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.6, 1.0)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(20, 120, 0)
	add_child(fill)

func _build_arena() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	_add_box(body, Vector3(-(WALL_X + GAP) * 0.5, -0.2, 0.0), Vector3(WALL_X - GAP, 0.4, FLOOR_HALF * 2.0))
	_add_box(body, Vector3((WALL_X + GAP) * 0.5, -0.2, 0.0), Vector3(WALL_X - GAP, 0.4, FLOOR_HALF * 2.0))
	# keep players inside the arena
	_add_box(body, Vector3(0.0, 0.3, FLOOR_HALF + 0.12), Vector3(WALL_X * 2.0 + 0.4, 0.9, 0.3))
	_add_box(body, Vector3(0.0, 0.3, -(FLOOR_HALF + 0.12)), Vector3(WALL_X * 2.0 + 0.4, 0.9, 0.3))

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.32, 0.36, 0.54)
	floor_mat.roughness = 0.9
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Color(0.42, 0.46, 0.68)
	top_mat.roughness = 0.75
	var side_mat := StandardMaterial3D.new()
	side_mat.albedo_color = Color(0.20, 0.22, 0.34)
	side_mat.roughness = 1.0

	_add_mesh(body, BoxMesh.new(), Vector3(-(WALL_X + GAP) * 0.5, -0.2, 0.0), Vector3(WALL_X - GAP, 0.4, FLOOR_HALF * 2.0), floor_mat)
	_add_mesh(body, BoxMesh.new(), Vector3((WALL_X + GAP) * 0.5, -0.2, 0.0), Vector3(WALL_X - GAP, 0.4, FLOOR_HALF * 2.0), floor_mat)
	# floor top faces (brighter)
	_add_mesh(body, BoxMesh.new(), Vector3(-(WALL_X + GAP) * 0.5, 0.11, 0.0), Vector3(WALL_X - GAP, 0.14, FLOOR_HALF * 2.0), top_mat)
	_add_mesh(body, BoxMesh.new(), Vector3((WALL_X + GAP) * 0.5, 0.11, 0.0), Vector3(WALL_X - GAP, 0.14, FLOOR_HALF * 2.0), top_mat)
	# slight knee bump near the pit
	_add_mesh(body, BoxMesh.new(), Vector3(-GAP - 0.16, -0.16, 0.0), Vector3(0.5, 0.5, FLOOR_HALF * 2.0), side_mat)
	_add_mesh(body, BoxMesh.new(), Vector3(GAP + 0.16, -0.16, 0.0), Vector3(0.5, 0.5, FLOOR_HALF * 2.0), side_mat)

	# walls / cage posts
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.28, 0.31, 0.5)
	post_mat.roughness = 0.7
	for z in [-FLOOR_HALF + 0.5, FLOOR_HALF - 0.5]:
		for x in range(-WALL_X + 0.6, WALL_X - 0.3, 1.4):
			_add_mesh(body, CylinderMesh.new(), Vector3(x, 0.6, z), Vector3(0.32, 0.32, 0.32), post_mat)

	# pit bottom + lava
	_add_box(body, Vector3(0.0, -1.3, 0.0), Vector3(GAP * 2.0, 0.7, FLOOR_HALF * 2.0))
	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = Color(0.12, 0.08, 0.2)
	var pit := MeshInstance3D.new()
	pit.mesh = BoxMesh.new()
	pit.material_override = pit_mat
	pit.position = Vector3(0, -1.0, 0)
	pit.scale = Vector3(GAP * 2.0, 0.12, FLOOR_HALF * 2.0)
	body.add_child(pit)

	# lava glow mesh (emissive)
	lava_mat.albedo_color = Color(0.2, 0.1, 0.08)
	lava_mat.emission_enabled = true
	lava_mat.emission = Color(3.0, 0.5, 0.15)
	var lava := MeshInstance3D.new()
	var lm := PlaneMesh.new()
	lm.size = Vector2(GAP * 2.0 - 0.25, FLOOR_HALF * 2.0 - 0.35)
	lava.mesh = lm
	lava.material_override = lava_mat
	lava.rotation_degrees = Vector3(-90, 0, 0)
	lava.position = Vector3(0.0, -0.97, 0.0)
	add_child(lava)
	# a soft glow plate under the lava
	var gl := MeshInstance3D.new()
	var gm := QuadMesh.new()
	gm.size = Vector2(GAP * 2.0 + 0.6, FLOOR_HALF * 2.0 + 0.6)
	gl.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(1.0, 0.35, 0.1, 0.6)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.emission_enabled = true
	gmat.emission = Color(2.2, 0.35, 0.08)
	gl.material_override = gmat
	gl.position = Vector3(0.0, -0.98, 0.0)
	gl.rotation_degrees = Vector3(-90, 0, 0)
	body.add_child(gl)

func _add_box(parent: StaticBody3D, pos: Vector3, sz: Vector3) -> void:
	var c := CollisionShape3D.new()
	var r := BoxShape3D.new()
	r.size = sz
	c.shape = r
	c.position = pos
	parent.add_child(c)

func _add_mesh(parent: Node, ms: Mesh, pos: Vector3, size: Vector3, mat: BaseMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = ms
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)

func _build_players() -> void:
	p1 = JellyPlayer.new()
	p1.set_palette(Color(0.35, 0.72, 1.0), Color(0.13, 0.38, 0.66), Color(0.75, 0.91, 1.0))
	p2 = JellyPlayer.new()
	p2.set_palette(Color(1.0, 0.45, 0.32), Color(0.62, 0.18, 0.1), Color(1.0, 0.79, 0.66))
	add_child(p1)
	add_child(p2)
	p1.opponent = p2
	p2.opponent = p1
	p1.on_hit.connect(_on_hit)
	p2.on_hit.connect(_on_hit)
	p1.place(Vector3(-2.9, 0.55, 0.0))
	p2.place(Vector3(2.9, 0.55, 0.0))

func _build_ui() -> void:
	ui = TouchUI.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.add_child(ui)
	add_child(layer)
	hud = Hud.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

func _go_menu() -> void:
	mode = Mode.MENU
	ui.in_menu = true
	ui.reset_inputs()
	p1.set_active(false)
	p2.set_active(false)
	p1.place(Vector3(-2.9, 0.55, 0.0))
	p2.place(Vector3(2.9, 0.55, 0.0))

func _start_game() -> void:
	scores = [0, 0]
	match_winner = -1
	_start_round()

func _start_round() -> void:
	p1.place(Vector3(-2.9, 0.55, 0.0))
	p2.place(Vector3(2.9, 0.55, 0.0))
	p1.clear_falling()
	p2.clear_falling()
	p1.set_active(true)
	p2.set_active(true)
	p1.clear_input()
	p2.clear_input()
	countdown_t = 1.6
	round_result = -1
	mode = Mode.COUNTDOWN

func _process(delta: float) -> void:
	sim_t += delta
	_update_hud()
	lava_mat.emission = Color(2.2 + sin(sim_t * 6.0) * 1.0, 0.4, 0.12)
	if shake > 0.0:
		shake = maxf(shake - delta * 2.0, 0.0)
		cam.position.y = 5.4 + (randf() - 0.5) * shake * 0.8
		cam.position.x = (randf() - 0.5) * shake * 0.8
	else:
		cam.position = Vector3(0, 5.4, 9.2)

func _physics_process(delta: float) -> void:
	match mode:
		Mode.MENU:
			var pick := _take_menu_pick()
			if pick != -1:
				p2_is_bot = pick == 0
				ui.in_menu = false
				_start_game()
		Mode.COUNTDOWN:
			countdown_t -= delta
			if countdown_t <= 0.0:
				countdown_t = 0.0
				play_t = 0.0
				mode = Mode.PLAYING
		Mode.PLAYING:
			play_t += delta
			_collect_inputs(delta)
			_check_falls()
		Mode.ROUND_OVER:
			state_t -= delta
			if state_t <= 0.0:
				if scores[0] >= ROUND_WINS or scores[1] >= ROUND_WINS:
					match_winner = 0 if scores[0] > scores[1] else 1
					scores = [0, 0]
					state_t = 3.0
					mode = Mode.MATCH_OVER
				else:
					_start_round()
		Mode.MATCH_OVER:
			state_t -= delta
			if state_t <= 0.0:
				_go_menu()

func _take_menu_pick() -> int:
	if ui.menu_press == -1:
		return -1
	var v := ui.menu_press
	ui.menu_press = -1
	return v

func _collect_inputs(delta: float) -> void:
	var s0: Dictionary = ui.state(0)
	p1.set_input(s0["dir"], s0["punch"], s0["kick"], s0["jump"])
	if p2_is_bot:
		_bot_input(delta)
	else:
		var s1: Dictionary = ui.state(1)
		p2.set_input(s1["dir"], s1["punch"], s1["kick"], s1["jump"])

func _bot_input(delta: float) -> void:
	var bot := p2
	var foe := p1
	if foe.fell:
		bot.clear_input()
		return
	var td := foe.torso_pos() - bot.torso_pos()
	var mv := Vector2.ZERO
	if absf(td.x) > 0.4:
		mv.x = signf(td.x)
	mv.y = clampf(-td.z * 0.8, -1.0, 1.0)  # align to the camera plane
	var want_p := false
	var want_k := false
	var want_j := false
	if absf(bot.torso_pos().x) > WALL_X - 1.0:
		mv.x = -signf(bot.torso_pos().x)
	elif td.length() < 1.4 and absf(bot.torso_pos().y) < 0.6:
		ai_timer -= delta
		if ai_timer <= 0.0:
			ai_timer = 0.2 + randf() * 0.4
			want_p = true
			if randf() < 0.4:
				want_p = false
				want_k = true
	elif bot.grounded and randf() < 0.01:
		want_j = true
	bot.set_input(mv, want_p, want_k, want_j)

func _check_falls() -> void:
	for i in 2:
		var pl := p1 if i == 0 else p2
		if pl.fell:
			continue
		if pl.torso_pos().y >= KILL_Y:
			continue
		pl.fell = true
		pl.set_active(false)
		_burst(pl.torso_pos(), Color(1.0, 0.45, 0.2))
		var other := p2 if i == 0 else p1
		if other.fell:
			round_result = 2
			state_t = 1.0
		else:
			scores[i] += 1
			round_result = i
			state_t = 1.5
		mode = Mode.ROUND_OVER

func _on_hit(pos: Vector3, col: Color) -> void:
	shake = minf(shake + 0.3, 1.0)
	_burst(pos, col)

func _burst(global_pos: Vector3, col: Color) -> void:
	var p := CPUParticles3D.new()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.1
	p.position = global_pos
	add_child(p)
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.gravity = Vector3(0, -20, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 7.0
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.3
	p.color = col
	p.amount = 18
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.emitting = true
	p.finished.connect(p.queue_free)

func _update_hud() -> void:
	hud.mode = mode
	hud.countdown = countdown_t
	hud.play_t = play_t
	hud.scores = scores
	hud.match_winner = match_winner
	hud.round_result = round_result
	hud.p1_color = p1.color_main
	hud.p2_color = p2.color_main
	hud.queue_redraw()
