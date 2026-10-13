class_name WildWildernessPlaceholder
extends Node2D
## P1 接收出发的独立占位场景；没有随机地图、时间消耗、奖励或生存结算。

const EXPLORER: PackedScene = preload("res://scenes/player/base_explorer.tscn")
var config: WildGameConfig
var player_id: String


func _ready() -> void:
	var explorer: WildBaseExplorer = EXPLORER.instantiate() as WildBaseExplorer
	explorer.configure(player_id, config)
	explorer.position = Vector2(320, 220)
	add_child(explorer)
	var body := StaticBody2D.new()
	add_child(body)
	for bounds: Rect2 in [Rect2(28, 58, 584, 6), Rect2(28, 304, 584, 6), Rect2(28, 58, 6, 252), Rect2(606, 58, 6, 252)]:
		var shape := RectangleShape2D.new()
		shape.size = bounds.size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = bounds.get_center()
		body.add_child(collision)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("21382e"))
	for y: int in range(16, 350, 16):
		for x: int in range(16, 630, 16):
			if (x * 11 + y * 7) % 5 == 0:
				draw_rect(Rect2(x, y, 7, 3), Color("3a4c34"))
	draw_rect(Rect2(240, 154, 160, 128), Color("5b6042"))
	for x: int in range(12, 630, 38):
		for y: int in [70, 320]:
			draw_rect(Rect2(x, y, 6, 24), Color("67533a"))
			draw_rect(Rect2(x - 12, y - 15, 30, 16), Color("375a40"))
			draw_rect(Rect2(x - 8, y - 27, 22, 16), Color("426848"))
