extends Control
## Small procedural isometric block icon; can later be replaced with item textures.
var color := Color.WHITE
var grass := false
var kind := 0

func _draw() -> void:
	if kind >= 9:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.35
		match kind:
			9:
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r, r * 0.4), c + Vector2(-r * 0.6, -r * 0.5), c + Vector2(r * 0.3, -r * 0.7), c + Vector2(r, r * 0.4), c + Vector2(0, r * 0.7)]), color)
			10:
				draw_line(c + Vector2(-r, r), c + Vector2(r, -r), color, 5, true)
				draw_line(c, c + Vector2(-r * 0.2, -r), color, 3, true)
			11, 13:
				for i in range(5):
					var x := (i - 2) * r * 0.3
					draw_line(c + Vector2(x * 0.3, r), c + Vector2(x, -r + absf(x) * 0.4), color, 3, true)
			12:
				draw_arc(c, r * 0.75, 0, TAU * 0.9, 24, color, 5, true)
				draw_line(c + Vector2(r * 0.6, -r * 0.4), c + Vector2(r, -r), color, 4, true)
		return
	var center := size * Vector2(0.5, 0.42)
	var r := minf(size.x, size.y) * 0.4
	var top := center + Vector2(0, -r * 0.55)
	var left := center + Vector2(-r, 0)
	var right := center + Vector2(r, 0)
	var front := center + Vector2(0, r * 0.55)
	var bottom := front + Vector2(0, r)
	var side_color := Color("8b6547") if grass else color
	draw_colored_polygon(PackedVector2Array([top, right, front, left]), color.lightened(0.12))
	draw_colored_polygon(PackedVector2Array([left, front, bottom, left + Vector2(0, r)]), side_color.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([front, right, right + Vector2(0, r), bottom]), side_color.darkened(0.35))
