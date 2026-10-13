class_name WildWorldMinimap
extends Control
## 探索原型的地图概览：显示地形、出生点和本地位置，不改变共享地图。

var _texture: ImageTexture
var _size := Vector2i.ZERO
var _spawn := Vector2i.ZERO
var _tile_pixels: int = 32
var player_position := Vector2.ZERO

func configure(record: Dictionary) -> void:
	_size = Vector2i(record["size"][0], record["size"][1])
	_spawn = Vector2i(record["spawn"][0], record["spawn"][1])
	_tile_pixels = record["tile_pixels"]
	var image := Image.create(_size.x, _size.y, false, Image.FORMAT_RGB8)
	var colors: Array[Color] = WildArtLibrary.TERRAIN_COLORS
	for y: int in range(_size.y):
		for x: int in range(_size.x):
			image.set_pixel(x, y, colors[int(record["tiles"][y][x])])
	_texture = ImageTexture.create_from_image(image)
	queue_redraw()

func _draw() -> void:
	if _texture == null:
		return
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
	draw_rect(Rect2(Vector2.ZERO, size), Color("b0ae7e"), false)
	var spawn_point: Vector2 = (Vector2(_spawn) + Vector2(0.5, 0.5)) / Vector2(_size) * size
	draw_circle(spawn_point, 3, Color("d8b46f"))
	var current: Vector2 = player_position / _tile_pixels / Vector2(_size) * size
	draw_circle(current, 2, Color("ffffff"))
