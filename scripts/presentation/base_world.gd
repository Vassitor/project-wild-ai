class_name WildBaseWorld
extends Node2D
## CC0 营地画面、静态碰撞与交互范围。仅发意图信号，所有规则由会话处理。

signal interaction_requested(station_id: StringName)
signal interaction_target_changed(station_id: StringName)

const EXPLORER_SCENE: PackedScene = preload("res://scenes/player/base_explorer.tscn")
const BOUNDARIES: Array[Rect2] = [Rect2(28, 58, 584, 6), Rect2(28, 304, 584, 6), Rect2(28, 58, 6, 252), Rect2(606, 58, 6, 252)]

var _config: WildGameConfig
var _local_player_id: String
var _explorers: Dictionary[String, WildBaseExplorer] = {}
var _collision_body: StaticBody2D
var _target: StringName = &""
var _font := SystemFont.new()
var _visual_seconds: float = 0.0


func configure(config: WildGameConfig, local_player_id: String) -> void:
	_config = config
	_local_player_id = local_player_id


func explorer_for(id: String) -> WildBaseExplorer:
	return _explorers.get(id)


func interaction_target() -> StringName:
	return _target


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei"])
	_collision_body = StaticBody2D.new()
	_collision_body.name = "BaseObstacles"
	add_child(_collision_body)
	for boundary: Rect2 in BOUNDARIES:
		_add_obstacle(boundary)
	for id: StringName in WildBaseLayout.STATIONS:
		var station: Dictionary = WildBaseLayout.station(id)
		_add_obstacle(station["bounds"] as Rect2)
	_add_obstacle(Rect2(307, 157, 26, 18))
	var explorer: WildBaseExplorer = EXPLORER_SCENE.instantiate() as WildBaseExplorer
	explorer.name = "Explorer_%s" % _local_player_id
	explorer.configure(_local_player_id, _config)
	explorer.position = WildBaseLayout.SPAWN
	_explorers[_local_player_id] = explorer
	add_child(explorer)
	y_sort_enabled = true
	queue_redraw()


func _process(delta: float) -> void:
	_visual_seconds += delta
	queue_redraw()
	var explorer: WildBaseExplorer = explorer_for(_local_player_id)
	if explorer == null:
		return
	var closest: StringName = &""
	var closest_distance: float = WildBaseLayout.INTERACTION_RADIUS
	for id: StringName in WildBaseLayout.STATIONS:
		var station_position: Vector2 = WildBaseLayout.STATIONS[id]["position"]
		var distance: float = explorer.position.distance_to(station_position)
		if distance < closest_distance:
			closest = id
			closest_distance = distance
	if closest != _target:
		_target = closest
		interaction_target_changed.emit(_target)


## 输入由组合根路由，避免主视口与子视口重复处理同一个 E 键。
func request_interaction() -> void:
	if not _target.is_empty():
		interaction_requested.emit(_target)


func _add_obstacle(bounds: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = bounds.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = bounds.get_center()
	_collision_body.add_child(collider)


func _draw() -> void:
	for row: int in range(12):
		for column: int in range(20):
			var region := Rect2(((column * 7 + row * 11) % 4) * 32, 32, 32, 32)
			draw_texture_rect_region(WildArtLibrary.TERRAIN, Rect2(column * 32, row * 32, 32, 32), region)
	# 步道和四个设施保留 P0 的布局，贴图不改变碰撞 / 交互范围。
	draw_texture_rect(WildArtLibrary.PATH, Rect2(90, 168, 462, 40), true)
	draw_texture_rect(WildArtLibrary.PATH, Rect2(291, 144, 58, 149), true)
	draw_texture_rect(WildArtLibrary.PATH, Rect2(105, 254, 419, 35), true)
	for i: int in range(24):
		draw_rect(Rect2(98 + i * 18, 185 + (i % 3) * 4, 6, 3), Color("b09667"))
	for boundary: Rect2 in BOUNDARIES:
		draw_rect(boundary, Color("6d6145"))
	for x: int in range(10, 640, 37):
		_draw_prop(&"pine", Vector2(x, 46), 1)
		_draw_prop(&"pine", Vector2(x + 12, 351), 1)
	for y: int in range(93, 305, 43):
		_draw_prop(&"pine", Vector2(12, y), 1)
		_draw_prop(&"pine", Vector2(626, y), 1)
	for id: StringName in [&"supply", &"storage"]:
		var bounds: Rect2 = WildBaseLayout.STATIONS[id]["bounds"]
		draw_rect(Rect2(bounds.position + Vector2(3, 5), bounds.size), Color(0.03, 0.06, 0.04, 0.28))
		draw_texture_rect(WildArtLibrary.texture(id), bounds, false)
		_draw_label(bounds.position + Vector2(14, 80), WildBaseLayout.STATIONS[id]["name"])
	_draw_prop(&"crate", Vector2(198, 155), 1)
	_draw_prop(&"barrel", Vector2(408, 154), 1)
	_draw_prop(&"crate", Vector2(526, 153), 1)
	# 训练与出发仍是既有入口；装饰贴图不代表训练 / 狩猎玩法已完成。
	draw_rect(Rect2(475, 221, 48, 48), Color("8b7853"))
	_draw_prop(&"target", Vector2(499, 257), 2)
	_draw_prop(&"sign", Vector2(140, 267), 2)
	_draw_label(Vector2(476, 291), "训练场")
	_draw_label(Vector2(121, 290), "出发点")
	draw_circle(Vector2(320, 168), 20, Color("6d6145"))
	WildArtLibrary.draw_campfire(self, Vector2(320, 175), _visual_seconds)
	_draw_prop(&"bench", Vector2(382, 244), 2)


## 所有装饰按整数倍率、脚底锚点绘制；不产生领域资源或额外碰撞。
func _draw_prop(id: StringName, foot: Vector2, factor: int) -> void:
	var image: Texture2D = WildArtLibrary.texture(id)
	var dimensions: Vector2 = image.get_size() * factor
	draw_texture_rect(image, Rect2(foot - Vector2(dimensions.x / 2, dimensions.y), dimensions), false)


func _draw_label(at: Vector2, text: String) -> void:
	draw_string(_font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("23382d"))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f1dfb6"))
