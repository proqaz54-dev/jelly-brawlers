class_name Hud
extends Control
## Draws the menu, countdown, scores and round/match overlays.

var mode := 0             # 0 menu, 1 playing, 2 countdown, 3 round over, 4 match over
var countdown := 0.0
var play_t := 0.0
var scores := [0, 0]
var round_result := -1    # -1 none, 0 = P1 scored, 1 = P2 scored, 2 = double KO
var match_winner := -1
var p1_color := Color(0.35, 0.72, 1.0)
var p2_color := Color(1.0, 0.45, 0.32)

func _process(_delta: float) -> void:
	queue_redraw()

func _center(text: String, at: Vector2, size: int, col: Color, outline: Color = Color.BLACK) -> void:
	var font := get_theme_default_font()
	for off in [Vector2(-3, 3), Vector2(3, 3), Vector2(-3, -3), Vector2(3, -3)]:
		draw_string(font, at + off, text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, outline)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, col)

func _draw() -> void:
	var w := get_viewport().get_visible_rect().size.x
	var h := get_viewport().get_visible_rect().size.y

	if mode == 0:
		_center("JELLY BRAWLERS", Vector2(w * 0.5, h * 0.2), 92,
			Color(1.0, 0.92, 0.6), Color(0.45, 0.15, 0.5))
		_center("RAGDOLL ARENA BRAWLER", Vector2(w * 0.5, h * 0.32), 38,
			Color(0.75, 0.8, 0.95), Color(0, 0, 0))

		var left := Vector2(w * 0.5 - 300.0, h * 0.6)
		draw_circle(left, 150.0, Color(0.14, 0.22, 0.45, 0.6))
		var c0 := p1_color
		c0.a = 1.0
		draw_circle(left, 130.0, c0)
		draw_circle(left - Vector2(40, 55), 45.0, Color(1, 1, 1, 0.35))
		_center("VS BOT", left - Vector2(0, 8), 46, Color(0.05, 0.1, 0.2), Color(0.85, 0.95, 1.0))

		var right := Vector2(w * 0.5 + 300.0, h * 0.6)
		draw_circle(right, 150.0, Color(0.45, 0.14, 0.08, 0.6))
		var c1 := p2_color
		c1.a = 1.0
		draw_circle(right, 130.0, c1)
		draw_circle(right - Vector2(40, 55), 45.0, Color(1, 1, 1, 0.35))
		_center("2 PLAYERS", right - Vector2(10, 8), 15, Color(0.2, 0.06, 0.03),
			Color(1.0, 0.85, 0.8))

		_center("TAP A BUTTON TO START - INSPIRED BY GANG BEASTS",
			Vector2(w * 0.5, h * 0.86), 28, Color(0.7, 0.72, 0.85), Color(0, 0, 0))
		return

	for i in 2:
		var left := i == 0
		var base_x := 110.0 if left else w - 110.0
		var col := p1_color if i == 0 else p2_color
		_center("P%d" % (i + 1), Vector2(base_x, 80), 52, col, Color(0, 0, 0))
		for s in 3:
			var px := base_x + (-52.0 if left else 52.0) * s
			var py := 150.0
			draw_circle(Vector2(px, py), 28.0, Color(0, 0, 0, 0.5))
			if s < scores[i]:
				draw_circle(Vector2(px, py), 24.0, col)
				draw_circle(Vector2(px - 5, py - 6), 9.0, Color(1, 1, 1, 0.7))
			else:
				draw_circle(Vector2(px, py), 24.0, Color(0.16, 0.15, 0.22))

	if mode == 2:
		var n := int(ceil(countdown / 0.533))
		if n >= 1 and n <= 3:
			_center(str(n), Vector2(w * 0.5, h * 0.38), 200,
				Color(1, 1, 1), Color(0.45, 0.15, 0.5))
	elif mode == 3:
		if round_result == 2:
			_center("DOUBLE KO!", Vector2(w * 0.5, h * 0.38), 90,
				Color(1.0, 0.82, 0.3), Color(0.4, 0.1, 0.25))
		else:
			var who := "P1" if round_result == 0 else "P2"
			var col := p1_color if round_result == 0 else p2_color
			_center("%s SCORES!" % who, Vector2(w * 0.5, h * 0.38), 78, col,
				Color(0.1, 0.05, 0.18))
	elif mode == 4:
		var who := "P1" if match_winner == 0 else "P2"
		var col := p1_color if match_winner == 0 else p2_color
		_center("%s WINS THE MATCH!" % who, Vector2(w * 0.5, h * 0.38), 80, col,
			Color(0.1, 0.05, 0.18))
	elif mode == 1 and play_t < 0.8:
		_center("GO!", Vector2(w * 0.5, h * 0.38), 130, Color(0.6, 1.0, 0.75),
			Color(0.05, 0.25, 0.15))