extends Control
## Small procedural isometric block icon; can later be replaced with item textures.
var color := Color.WHITE
var grass := false

func _draw() -> void:
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
