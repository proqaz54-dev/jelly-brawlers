class_name TouchUI
extends Control
## Full-screen virtual joystick + action buttons (two player halves).

const JOY_TRAVEL := 120.0

var in_menu := true
var menu_press: int = -1

var _states := [
	{ "dir": Vector2.ZERO, "punch": false, "kick": false, "jump": false },
	{ "dir": Vector2.ZERO, "punch": false, "kick": false, "jump": false },
]
var _ptr := {}        # pointer id -> { half:int, mode:int, origin:Vector2 }
var _joy_origin: Array = [null, null]

func reset_inputs() -> void:
	for i in 2:
		_states[i]["dir"] = Vector2.ZERO
		_states[i]["punch"] = false
		_states[i]["kick"] = false
		_states[i]["jump"] = false
	_joy_origin = [null, null]
	_ptr.clear()

func state(i: int) -> Dictionary:
	return _states[i]

func _process(_delta: float) -> void:
	queue_redraw()

func button_centers(half: int, name: String) -> Vector2:
	var w := size.x
	var h := size.y
	var x0 := half * w * 0.5
	var half_w := w * 0.5
	match name:
		"kick":
			return Vector2(x0 + half_w * 0.18, h - 300.0)
		"jump":
			return Vector2(x0 + half_w * 0.50, h - 500.0)
		"punch":
			return Vector2(x0 + half_w * 0.82, h - 320.0)
	return Vector2.ZERO

func button_radius(name: String) -> float:
	match name:
		"kick":
			return 110.0
		"jump":
			return 150.0
		"punch":
			return 130.0
	return 0.0

func _assign(point: Vector2, id: int) -> void:
	if in_menu:
		menu_press = 0 if point.x < size.x * 0.5 else 1
		return
	var half := 0 if point.x < size.x * 0.5 else 1
	var order := ["kick", "jump", "punch"]
	for i in 3:
		var name: String = order[i]
		var c := button_centers(half, name)
		if point.distance_to(c) <= button_radius(name) * 0.9:
			_ptr[id] = { "half": half, "mode": i, "origin": point }
			return
	_joy_origin[half] = point
	_ptr[id] = { "half": half, "mode": 3, "origin": point }

func _release(id: int) -> void:
	if not _ptr.has(id):
		return
	var d: Dictionary = _ptr[id]
	var half: int = d["half"]
	if d["mode"] == 3:
		_states[half]["dir"] = Vector2.ZERO
		_joy_origin[half] = null
	else:
		match int(d["mode"]):
			0:
				_states[half]["punch"] = false
			1:
				_states[half]["kick"] = false
			2:
				_states[half]["jump"] = false
	_ptr.erase(id)

func _move(id: int, point: Vector2) -> void:
	if not _ptr.has(id):
		return
	var d: Dictionary = _ptr[id]
	var half: int = d["half"]
	match int(d["mode"]):
		0:
			_states[half]["punch"] = true
		1:
			_states[half]["kick"] = true
		2:
			_states[half]["jump"] = true
		3:
			var delta: Vector2 = point - (d["origin"] as Vector2)
			var l := delta.length()
			_states[half]["dir"] = (delta / l) if l > JOY_TRAVEL else delta / JOY_TRAVEL

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_assign(event.position, event.index)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		_move(event.index, event.position)
	elif event is InputEventMouseButton:
		if event.pressed:
			_assign(event.position, -7)
		else:
			_release(-7)
	elif event is InputEventMouseMotion:
		_move(-7, event.position)

func _draw() -> void:
	if in_menu:
		return
	var font := get_theme_default_font()
	for half in 2:
		if _joy_origin[half] != null:
			var o: Vector2 = _joy_origin[half]
			draw_circle(o, 150.0, Color(1, 1, 1, 0.14))
			draw_arc(o, 150.0, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 6.0)
			var inp: Dictionary = _states[half]
			var kn: Vector2 = o + (inp["dir"] as Vector2) * (JOY_TRAVEL + 20.0)
			draw_circle(kn, 60.0, Color(1, 1, 1, 0.55))
		for name in ["kick", "jump", "punch"]:
			var c := button_centers(half, name)
			var r := button_radius(name)
			var held: bool = _states[half][name]
			var col := Color(0.6, 0.45, 0.9, 0.9)
			match name:
				"kick":
					col = Color(0.6, 0.45, 0.9, 0.9)
				"jump":
					col = Color(0.95, 0.72, 0.2, 0.92)
				"punch":
					col = Color(0.95, 0.35, 0.3, 0.92)
			if held:
				draw_circle(c, r + 10.0, Color(1, 1, 1, 0.55))
			draw_circle(c, r, Color(0.1, 0.08, 0.16, 0.65))
			draw_circle(c, r * 0.92, col)
			var label: String = name.to_upper()
			draw_string(font, c + Vector2(-50, 16), label, HORIZONTAL_ALIGNMENT_CENTER, 100,
					36, Color(0.09, 0.06, 0.12, 0.95))