extends Node2D
## Game controller: arena, two players, round/match state machine, bot AI,
## particles and camera shake.

enum Mode { MENU = 0, PLAYING = 1, COUNTDOWN = 2, ROUND_OVER = 3, MATCH_OVER = 4 }

const WALL_X := 7.0
const GAP := 1.05
const FLOOR_Y := 3.6
const FLOOR_BOTTOM := 5.5
const WALL_TOP := -3.6
const KILL_Y := 4.8
const ROUND_WINS := 3

var mode := Mode.MENU
var p2_is_bot := true

var p1: JellyPlayer
var p2: JellyPlayer
var ui: TouchUI
var hud: Hud
var cam: Camera2D

var countdown_t := 0.0
var play_t := 0.0
var state_t := 0.0
var scores := [0, 0]
var match_winner := -1
var round_result := -1
var shake := 0.0
var ai_timer := 0.0
var sim_t := 0.0

func _ready() -> void:
	get_viewport().canvas_transform = Transform2D()
	_build_camera()
	_build_arena()
	_build_players()
	_build_ui()
	_go_menu()
	if OS.get_environment("JB_AUTOSTART") != "":
		ui.in_menu = false
		_start_game()

func _build_camera() -> void:
	cam = Camera2D.new()
	cam.position = Vector2(0, 1.0)
	var vh: float = get_viewport().get_visible_rect().size.y
	var zoom := vh / 9.6
	cam.zoom = Vector2(zoom, zoom)
	add_child(cam)
	cam.make_current()

func _build_arena() -> void:
	var arena := StaticBody2D.new()
	arena.collision_layer = 1
	arena.collision_mask = 0
	add_child(arena)
	_add_box(arena, Vector2(-(WALL_X + GAP) * 0.5, FLOOR_Y), Vector2(WALL_X - GAP, 0.3))
	_add_box(arena, Vector2((WALL_X + GAP) * 0.5, FLOOR_Y), Vector2(WALL_X - GAP, 0.3))
	_add_box(arena, Vector2(-GAP, (FLOOR_Y + FLOOR_BOTTOM) * 0.5), Vector2(0.3, FLOOR_BOTTOM - FLOOR_Y))
	_add_box(arena, Vector2(GAP, (FLOOR_Y + FLOOR_BOTTOM) * 0.5), Vector2(0.3, FLOOR_BOTTOM - FLOOR_Y))
	_add_box(arena, Vector2(-WALL_X, (FLOOR_Y + WALL_TOP) * 0.5), Vector2(0.5, FLOOR_Y - WALL_TOP))
	_add_box(arena, Vector2(WALL_X, (FLOOR_Y + WALL_TOP) * 0.5), Vector2(0.5, FLOOR_Y - WALL_TOP))
	queue_redraw()

func _add_box(parent: StaticBody2D, pos: Vector2, sz: Vector2) -> void:
	var c := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = sz
	c.shape = r
	c.position = pos
	parent.add_child(c)

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
	p1.place(Vector2(-2.3, 2.5))
	p2.place(Vector2(2.3, 2.5))

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
	p1.place(Vector2(-2.3, 2.5))
	p2.place(Vector2(2.3, 2.5))

func _start_game() -> void:
	scores = [0, 0]
	match_winner = -1
	_start_round()

func _start_round() -> void:
	p1.place(Vector2(-2.3, 2.5))
	p2.place(Vector2(2.3, 2.5))
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
	if shake > 0.0:
		shake = maxf(shake - delta * 2.0, 0.0)
		cam.offset = Vector2(randf() - 0.5, randf() - 0.5) * shake * 26.0
	else:
		cam.offset = Vector2.ZERO

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
	var mv := Vector2.RIGHT
	if foe.torso_pos().x >= bot.torso_pos().x:
		mv = Vector2.RIGHT
	else:
		mv = Vector2.LEFT
	var want_p := false
	var want_k := false
	var want_j := false
	if absf(bot.torso_pos().x) > WALL_X - 0.9:
		mv = -mv
	elif absf(foe.torso_pos().x - bot.torso_pos().x) < 1.3:
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
		if pl.torso_pos().y <= KILL_Y:
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

func _on_hit(pos: Vector2, col: Color) -> void:
	shake = minf(shake + 0.3, 1.0)
	_burst(pos, col)

func _burst(global_pos: Vector2, col: Color) -> void:
	var p := CPUParticles2D.new()
	p.set_as_top_level(true)
	p.position = global_pos
	add_child(p)
	p.amount = 18
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector2(0, 26)
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.5
	p.color = col
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

func _draw() -> void:
	var vh: float = get_viewport().get_visible_rect().size.y
	var vw: float = get_viewport().get_visible_rect().size.x
	var half_h := vh / cam.zoom.y / 2.0
	var half_w := vw / cam.zoom.y / 2.0
	var cy := cam.global_position.y

	# background gradient
	for i in 10:
		var t0 := i / 10.0
		var t1 := (i + 1) / 10.0
		var col := _bg_color(t0)
		draw_rect(
			Rect2(Vector2(-half_w - 1, cy - half_h + (t0 - 0.5) * half_h * 2.0),
			Vector2(half_w * 2.0 + 2.0, (t1 - t0) * half_h * 2.0)), col)

	# soft light glow behind the arena
	draw_circle(Vector2(0, -1.2), 11.0, Color(0.45, 0.30, 0.85, 0.05))
	draw_circle(Vector2(0, -1.2), 7.0, Color(0.45, 0.30, 0.85, 0.06))
	draw_circle(Vector2(0, 0.1), 4.5, Color(0.95, 0.50, 0.25, 0.05))
	draw_circle(Vector2(0, 1.2), 2.9, Color(0.95, 0.50, 0.25, 0.06))

	# floor blocks
	var floor_c := Color(0.27, 0.30, 0.43)
	var floor_top := Color(0.42, 0.47, 0.66)
	var floor_edge := Color(0.20, 0.22, 0.32)
	draw_rect(Rect2(Vector2(-WALL_X, FLOOR_Y), Vector2(WALL_X - GAP, FLOOR_BOTTOM - FLOOR_Y)), floor_c)
	draw_rect(Rect2(Vector2(GAP, FLOOR_Y), Vector2(WALL_X - GAP, FLOOR_BOTTOM - FLOOR_Y)), floor_c)
	draw_rect(Rect2(Vector2(-WALL_X, FLOOR_Y), Vector2(WALL_X - GAP, 0.18)), floor_top)
	draw_rect(Rect2(Vector2(GAP, FLOOR_Y), Vector2(WALL_X - GAP, 0.18)), floor_top)
	draw_rect(Rect2(Vector2(-WALL_X, FLOOR_Y), Vector2(WALL_X - GAP, 0.10)), Color(0.16, 0.17, 0.26))
	draw_rect(Rect2(Vector2(GAP, FLOOR_Y), Vector2(WALL_X - GAP, 0.10)), Color(0.16, 0.17, 0.26))

	# floor grid
	var grid := Color(0.05, 0.06, 0.11, 0.5)
	for i in 6:
		var x := -WALL_X + 0.62 + i * 1.12
		draw_line(Vector2(x, FLOOR_Y + 0.12), Vector2(x, FLOOR_BOTTOM - 0.04), grid, 0.05)
		draw_line(Vector2(-x, FLOOR_Y + 0.12), Vector2(-x, FLOOR_BOTTOM - 0.04), grid, 0.05)
	draw_line(Vector2(-WALL_X + 0.1, FLOOR_Y + 0.88), Vector2(-GAP - 0.1, FLOOR_Y + 0.88), grid, 0.05)
	draw_line(Vector2(GAP + 0.1, FLOOR_Y + 0.88), Vector2(WALL_X - 0.1, FLOOR_Y + 0.88), grid, 0.05)
	# hazard stripes near the pit
	draw_rect(Rect2(Vector2(-GAP - 0.22, FLOOR_Y), Vector2(0.12, 0.5)), Color(0.98, 0.75, 0.22, 0.8))
	draw_rect(Rect2(Vector2(GAP + 0.10, FLOOR_Y), Vector2(0.12, 0.5)), Color(0.98, 0.75, 0.22, 0.8))

	# gap side trim
	draw_rect(Rect2(Vector2(-GAP - 0.18, FLOOR_Y), Vector2(0.18, FLOOR_BOTTOM - FLOOR_Y)), floor_edge)
	draw_rect(Rect2(Vector2(GAP, FLOOR_Y), Vector2(0.18, FLOOR_BOTTOM - FLOOR_Y)), floor_edge)

	# side walls
	var wall_c := Color(0.20, 0.22, 0.38)
	var bar_top := Color(0.34, 0.38, 0.58)
	var bar := Color(0.24, 0.26, 0.44)
	draw_rect(Rect2(Vector2(-WALL_X - 0.45, WALL_TOP), Vector2(0.45, FLOOR_Y - WALL_TOP)), wall_c)
	draw_rect(Rect2(Vector2(WALL_X, WALL_TOP), Vector2(0.45, FLOOR_Y - WALL_TOP)), wall_c)
	for i in 5:
		var y := FLOOR_Y - 0.9 - i * 1.1
		draw_circle(Vector2(-WALL_X - 0.22, y), 0.11, Color(0.35, 0.38, 0.6))
		draw_circle(Vector2(WALL_X + 0.22, y), 0.11, Color(0.35, 0.38, 0.6))
	# top rail
	draw_rect(Rect2(Vector2(-WALL_X - 0.75, WALL_TOP - 0.30), Vector2(WALL_X * 2.0 + 1.5, 0.16)), bar_top)
	draw_rect(Rect2(Vector2(-WALL_X - 0.75, WALL_TOP - 0.14), Vector2(WALL_X * 2.0 + 1.5, 0.05)), Color(0.16, 0.18, 0.30))
	# cage bars rising above the rail
	for i in 12:
		var x := -WALL_X - 0.62 + i * 1.34
		if x > WALL_X + 0.62:
			break
		draw_rect(Rect2(Vector2(x, WALL_TOP - 3.15), Vector2(0.10, 2.85)), bar)
		draw_rect(Rect2(Vector2(x - 0.02, WALL_TOP - 3.15), Vector2(0.14, 0.10)), bar_top)

	# soft blob shadows under the players
	for pl in [p1, p2]:
		if pl == null:
			continue
		var t: Vector2 = pl.torso_pos()
		if t.y >= KILL_Y:
			continue
		var sw := clampf(1.9 - t.y * 0.10, 0.8, 1.9)
		draw_set_transform(Vector2(t.x, FLOOR_Y + 0.06), 0.0, Vector2(sw, 0.30))
		draw_circle(Vector2.ZERO, 1.0, Color(0.0, 0.0, 0.0, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# lava under the pit gap
	var pulse := 0.5 + 0.5 * sin(sim_t * 6.0)
	var lava := Color(1.0, 0.36, 0.12).lerp(Color(1.0, 0.8, 0.3), pulse)
	draw_rect(Rect2(Vector2(-GAP + 0.25, KILL_Y - 0.30), Vector2(GAP * 2 - 0.5, 0.22)), Color(1.0, 0.55, 0.2, 0.16))
	draw_rect(Rect2(Vector2(-GAP + 0.25, KILL_Y - 0.62), Vector2(GAP * 2 - 0.5, 0.7)), lava)
	draw_rect(Rect2(Vector2(-GAP + 0.25, KILL_Y - 0.62 - 0.55), Vector2(GAP * 2 - 0.5, 0.55)), Color(1.0, 0.6, 0.25, 0.25))
	draw_rect(Rect2(Vector2(-GAP + 0.25, KILL_Y + 0.08), Vector2(GAP * 2 - 0.5, 0.35)), Color(0.4, 0.08, 0.02, 0.6))

func _bg_color(t: float) -> Color:
	var top := Color(0.20, 0.12, 0.38)
	var bottom := Color(0.06, 0.03, 0.14)
	return top.lerp(bottom, t)
