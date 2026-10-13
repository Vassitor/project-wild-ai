class_name WildWildernessWorld
extends Node2D
## 世界视图只拥有地形纹理、相机和本地输入。共享世界快照与移动规则由会话提供。

signal target_changed(entry: Dictionary)
signal inspect_requested(entry: Dictionary)

const EXPLORER: PackedScene = preload("res://scenes/player/base_explorer.tscn")
var camera: Camera2D
var explorer: WildBaseExplorer
var _session: WildLocalSession
var _actor: String
var _world: WildWorldData
var _config: WildGameConfig
var _layers: Array[TileMapLayer] = []
var _target: Dictionary = {}
var _buildings: Dictionary = {}
var _outputs: Dictionary = {}
var _prey: Dictionary = {}
var _visual_seconds: float = 0
var _night: CanvasModulate
var _remote_explorers: Dictionary[String, WildBaseExplorer] = {}


func configure(session: WildLocalSession, actor: String, config: WildGameConfig) -> void:
	_session = session
	_actor = actor
	_config = config


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tile_set: TileSet = WildWorldTiles.create_set()
	for title: String in ["Land", "Water"]:
		var layer := TileMapLayer.new()
		layer.name = title
		layer.tile_set = tile_set
		layer.position = Vector2(16, 16) # TileMap 格中心与领域 0–32 像素格的中心对齐。
		layer.show_behind_parent = true
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(layer)
		_layers.append(layer)
	explorer = EXPLORER.instantiate() as WildBaseExplorer
	explorer.configure(_actor, _config)
	# 人物节点只画画；位置不通过该 CharacterBody 的基地输入逻辑修改。
	explorer.process_mode = Node.PROCESS_MODE_DISABLED
	explorer.collision_layer = 0
	explorer.collision_mask = 0
	add_child(explorer)
	camera = Camera2D.new()
	camera.enabled = false
	camera.position_smoothing_enabled = false
	add_child(camera)
	_night = CanvasModulate.new()
	_night.visible = false
	add_child(_night)


## 切换 / 恢复同一任务不重新生成、不重置位置；新任务才重建显示层。
func enter(record: Dictionary) -> bool:
	var world: WildWorldData = WildWorldCodec.decode(record, _config)
	if world == null:
		return false
	_world = world
	refresh_dynamic(_session.world_dynamic(_actor))
	for layer: TileMapLayer in _layers:
		layer.clear()
	for y: int in range(world.size.y):
		for x: int in range(world.size.x):
			var terrain: int = world.tiles[y * world.size.x + x]
			var layer_index: int = 1 if terrain == WildWorldData.Terrain.WATER else 0
			_layers[layer_index].set_cell(Vector2i(x, y), 0, Vector2i((x * 7 + y * 13) % 4, terrain))
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = world.size.x * world.tile_pixels
	camera.limit_bottom = world.size.y * world.tile_pixels
	camera.enabled = true
	visible = true
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_update_position()
	queue_redraw()
	return true


func leave() -> void:
	camera.enabled = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_world = null
	_target = {}
	_buildings.clear()
	_outputs.clear()
	_prey.clear()
	_night.color = Color.WHITE
	_night.visible = false
	for player: WildBaseExplorer in _remote_explorers.values(): player.queue_free()
	_remote_explorers.clear()


func _physics_process(delta: float) -> void:
	if _world == null:
		return
	_visual_seconds += delta
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var before: Vector2 = _session.world_position(_actor)
	_session.move_world_player(_actor, direction, minf(delta, 0.1), Input.is_action_pressed(&"sprint"))
	if not direction.is_zero_approx():
		explorer.face(direction)
	_update_position()
	_update_remote_players(delta)
	explorer.animate_motion(explorer.position - before, delta, Input.is_action_pressed(&"sprint"))
	_update_target()
	queue_redraw()

func _update_remote_players(delta: float) -> void:
	var positions: Dictionary = _session.world_player_positions()
	for actor: String in positions:
		if actor == _actor: continue
		if not _remote_explorers.has(actor):
			var remote: WildBaseExplorer = EXPLORER.instantiate() as WildBaseExplorer
			remote.configure(actor,_config)
			remote.process_mode = Node.PROCESS_MODE_DISABLED
			remote.collision_layer = 0
			remote.collision_mask = 0
			remote.modulate = Color("a6d7fa")
			add_child(remote)
			remote.position = positions[actor]
			_remote_explorers[actor] = remote
		var player: WildBaseExplorer = _remote_explorers[actor]
		var motion: Vector2 = positions[actor] - player.position
		player.position = positions[actor]
		if not motion.is_zero_approx(): player.face(motion.normalized())
		player.animate_motion(motion,delta,false)
		_world.players[actor] = player.position


func _update_position() -> void:
	explorer.position = _session.world_position(_actor)
	if _world != null: _world.players[_actor] = explorer.position
	camera.position = explorer.position
	camera.force_update_scroll()


func _update_target() -> void:
	var nearest: Dictionary = {}
	var distance: float = _world.tile_pixels * 1.5 + 0.01
	var reachable: Dictionary = _world.distances(_world.cell_at(explorer.position), 3)
	for entry: Dictionary in _world.resources.values():
		var cell := Vector2i(entry["x"], entry["y"])
		var candidate: float = explorer.position.distance_to(_world.centre(cell))
		if entry["remaining"] > 0 and candidate < distance and reachable.has(cell) and int(reachable[cell]) <= 3:
			distance = candidate
			nearest = entry
	for entry: Dictionary in _buildings.values():
		var rectangle := Rect2(Vector2(entry["x"],entry["y"]) * _world.tile_pixels, Vector2(entry["width"],entry["height"]) * _world.tile_pixels)
		var closest := Vector2(clampf(explorer.position.x,rectangle.position.x,rectangle.end.x),clampf(explorer.position.y,rectangle.position.y,rectangle.end.y))
		var candidate: float = explorer.position.distance_to(closest)
		if candidate < distance and WildBuildingRules.in_reach(_world,_actor,entry):
			distance = candidate
			nearest = entry.duplicate(true)
			nearest["entity_type"] = "building"
	for entry: Dictionary in _prey.values():
		if not entry["alive"]: continue
		var cell := Vector2i(entry["x"],entry["y"])
		var candidate: float = explorer.position.distance_to(_world.centre(cell))
		if candidate < distance and reachable.has(cell):
			distance = candidate
			nearest = entry.duplicate(true)
			nearest["entity_type"] = "prey"
	for entry: Dictionary in _outputs.values():
		if entry["owner"] == _actor and explorer.position.distance_to(Vector2(entry["x"],entry["y"])) <= _world.tile_pixels * 1.5:
			nearest = entry.duplicate(true)
			nearest["kind"] = "output"
			nearest["entity_type"] = "output"
	if nearest.get("id", "") != _target.get("id", ""):
		_target = nearest.duplicate(true)
		target_changed.emit(_target.duplicate(true))


func request_interaction() -> void:
	_update_target()
	queue_redraw()
	if not _target.is_empty():
		inspect_requested.emit(_target.duplicate(true))


func current_target() -> Dictionary:
	return _target.duplicate(true)


func _draw() -> void:
	if _world == null:
		return
	# 显示绘制按相机可见范围裁剪，资源仍保存在全世界快照，不以离屏销毁代替状态。
	var bounds := Rect2(camera.get_screen_center_position() - Vector2(352, 212), Vector2(704, 424))
	for entry: Dictionary in _world.resources.values():
		var centre: Vector2 = _world.centre(Vector2i(entry["x"], entry["y"]))
		if bounds.has_point(centre):
			_draw_resource(centre, entry)
	for building: Dictionary in _buildings.values():
		var centre := Vector2(building["x"]+building["width"]*0.5,building["y"]+building["height"]*0.5) * _world.tile_pixels
		if bounds.has_point(centre):
			if building["kind"] == "fire":
				if building["lit"]: WildArtLibrary.draw_campfire(self,centre + Vector2(0,8),_visual_seconds,2)
				else: draw_texture_rect(WildArtLibrary.texture(&"campfire"),Rect2(centre - Vector2(16,16),Vector2(32,32)),false)
			elif building["kind"] == "storage_box":
				draw_texture_rect(WildArtLibrary.texture(&"crate"),Rect2(centre - Vector2(16,16),Vector2(32,32)),false)
			elif building["kind"] == "cooking_table":
				draw_rect(Rect2(centre-Vector2(28,12),Vector2(56,24)),Color("786043"))
				draw_texture_rect(WildArtLibrary.texture(&"cooked_fish"),Rect2(centre-Vector2(12,12),Vector2(24,24)),false)
			elif building["kind"] in ["small_trap","large_trap"]:
				draw_texture_rect(WildArtLibrary.texture(&"crate"),Rect2(centre-Vector2(14,14),Vector2(28,28)),false)
				draw_arc(centre,12,0,TAU,12,Color("e4cf94") if not building.get("capture",{}).is_empty() else Color("937550"),2)
			else:
				var camp_scale: float = float(building["width"])/2
				draw_rect(Rect2(centre - Vector2(32,32)*camp_scale,Vector2(64,64)*camp_scale),Color("796948"))
				draw_colored_polygon(PackedVector2Array([centre+Vector2(-30,16)*camp_scale,centre+Vector2(0,-30)*camp_scale,centre+Vector2(30,16)*camp_scale]),Color("afbc7b"))
				draw_colored_polygon(PackedVector2Array([centre+Vector2(-12,16)*camp_scale,centre+Vector2(0,-9)*camp_scale,centre+Vector2(12,16)*camp_scale]),Color("4c5738"))
	for output: Dictionary in _outputs.values():
		var centre := Vector2(output["x"],output["y"])
		if bounds.has_point(centre): draw_texture_rect(WildArtLibrary.texture(&"crate"),Rect2(centre - Vector2(12,12),Vector2(24,24)),false)
	# 栖息标记对应实际保存的猎物实体，尚无 P6 的游走 / 战斗动画。
	for animal: Dictionary in _prey.values():
		var centre: Vector2 = _world.centre(Vector2i(animal["x"],animal["y"]))
		if animal["alive"] and bounds.has_point(centre):
			draw_circle(centre,4,Color("efead1") if animal["kind"] == "rabbit" else Color("8c5d47"))
			draw_line(centre+Vector2(-3,-2),centre+Vector2(-4,-7),Color("e4cf94"),2)
			draw_line(centre+Vector2(3,-2),centre+Vector2(4,-7),Color("e4cf94"),2)
	if not _target.is_empty():
		var centre: Vector2 = Vector2(_target["x"],_target["y"]) if _target.get("kind","") == "output" else _world.centre(Vector2i(_target["x"], _target["y"]))
		draw_rect(Rect2(centre - Vector2(15, 15), Vector2(30, 30)), Color("e4cf94"), false, 1)


func refresh_dynamic(data: Dictionary) -> void:
	if _world == null or data.is_empty(): return
	_world.resources = data["resources"].duplicate(true)
	_world.blocked_cells = data["blocked_cells"].duplicate()
	_buildings = data["buildings"].duplicate(true)
	_outputs = data["outputs"].duplicate(true)
	_prey = data.get("prey",{}).duplicate(true)
	queue_redraw()


func show_time(elapsed: float) -> void:
	var hour: float = fmod(8 + elapsed/3600,24)
	_night.visible = true
	_night.color = Color("aebcdc") if hour < 6 or hour >= 18 else Color.WHITE


func _draw_resource(point: Vector2, entry: Dictionary) -> void:
	var variant: int = int(entry["x"]) * 7 + int(entry["y"]) * 11
	var image: Texture2D = WildArtLibrary.resource_texture(StringName(entry["kind"]), variant, int(entry["remaining"]) <= 0)
	if image == null:
		return
	# 树和浆果丛保持原生尺寸；小资源放大两倍，仍只在原资源格交互。
	var factor: int = 1 if entry["kind"] in ["tree", "berry"] else 2
	var dimensions: Vector2 = image.get_size() * factor
	draw_texture_rect(image, Rect2(point - Vector2(dimensions.x / 2, dimensions.y - 10), dimensions), false)
