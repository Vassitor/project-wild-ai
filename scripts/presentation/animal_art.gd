class_name WildAnimalArt
extends RefCounted
## 原生像素形状动物与命中反馈；不替换现有 Ninja 人物 / 地形 / 道具。
static func draw(canvas: Node2D, point: Vector2, animal: Dictionary, visual_seconds: float) -> void:
	var rabbit: bool = animal["kind"] == "rabbit"
	var wolf: bool = animal["kind"] == "wolf"
	var color := Color("ebe3c4") if rabbit else Color("8794a2") if wolf else Color("8f5d45")
	var feet: float = sin(visual_seconds*12)*2 if animal.get("mode","wander") in ["wander","flee","chase","return"] else 0.0
	canvas.draw_circle(point+Vector2(0,6),10,Color(0,0,0,0.2))
	canvas.draw_rect(Rect2(point-Vector2(10,7),Vector2(20,14)),color)
	canvas.draw_rect(Rect2(point+Vector2(6,-9),Vector2(10,11)),color.lightened(0.1))
	canvas.draw_rect(Rect2(point+Vector2(-8,4+feet),Vector2(4,7)),color.darkened(0.2))
	canvas.draw_rect(Rect2(point+Vector2(5,4-feet),Vector2(4,7)),color.darkened(0.2))
	if rabbit:
		canvas.draw_rect(Rect2(point+Vector2(4,-18),Vector2(4,12)),color)
		canvas.draw_rect(Rect2(point+Vector2(10,-18),Vector2(4,12)),color)
	elif wolf:
		canvas.draw_colored_polygon(PackedVector2Array([point+Vector2(6,-9),point+Vector2(8,-15),point+Vector2(12,-9)]),color)
		canvas.draw_line(point+Vector2(-10,-1),point+Vector2(-19,-5),color,4)
	else:
		canvas.draw_line(point+Vector2(16,1),point+Vector2(20,-3),Color("efe8d0"),3)
	canvas.draw_rect(Rect2(point+Vector2(11,-7),Vector2(2,2)),Color("202c27"))
	if animal.has("hp") and animal["alive"]:
		canvas.draw_rect(Rect2(point+Vector2(-12,-25),Vector2(24,3)),Color("243a2d"))
		var maximum: float = animal.get("max_hp",{"rabbit":20.0,"boar":70.0,"wolf":50.0}[animal["kind"]])
		canvas.draw_rect(Rect2(point+Vector2(-12,-25),Vector2(24*clampf(float(animal["hp"])/maximum,0,1),3)),Color("e4be68"))
