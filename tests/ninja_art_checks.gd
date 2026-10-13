extends SceneTree
## 动画接入的定向验证：真实输入、障碍、单机暂停和权威移动；只写随机工作区档案。

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const VERIFICATION = preload("res://tests/verification_paths.gd")
var _passed: int = 0
var _failed: int = 0

func _initialize() -> void:
	if not VERIFICATION.arguments_are_isolated():
		push_error("Tests require workspace verification paths")
		quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	var tiles: TileSet = WildWorldTiles.create_set()
	var atlas: TileSetAtlasSource = tiles.get_source(0) as TileSetAtlasSource
	_check(not atlas.has_tiles_outside_texture(), "水帧区域均在图集内")
	for column: int in range(4):
		_check(atlas.get_tile_animation_frames_count(Vector2i(column, 2)) == 4, "水格使用四帧")
	for definition: WildItemDefinition in WildMain.CATALOG.definitions:
		var icon: Texture2D = WildArtLibrary.texture(definition.item_id)
		_check(icon != null and icon.get_image().get_used_rect().has_area(), "目录物品图像可用：%s" % definition.item_id)
	_check(WildArtLibrary.resource_texture(&"tree", 0, true) == WildArtLibrary.texture(&"stump"), "耗尽树显示树桩")
	_check(WildArtLibrary.resource_texture(&"berry", 0, true) == WildArtLibrary.texture(&"bush"), "耗尽浆果显示无果丛")
	_check(WildArtLibrary.resource_texture(&"stone", 0, true) == null, "耗尽散石不产生装饰资源")
	var main: WildMain = MAIN.instantiate() as WildMain
	main._profile_path = "res://.godot/verification/ninja_art_%s.cfg" % WildStableId.create("check")
	root.add_child(main)
	main.session.set_focus_lost(false)
	var explorer: WildBaseExplorer = main.base_world.explorer_for(main.local_player_id)
	var origin: Vector2 = explorer.position
	Input.action_press(&"move_right")
	for frame: int in range(8): await physics_frame
	_check(explorer.position.x > origin.x and explorer.animation.moving and explorer.animation.direction_index == 3, "实际基地位移驱动右向行走")
	Input.action_release(&"move_right")
	for frame: int in range(2): await physics_frame
	_check(not explorer.animation.moving, "停止移动回到待机")
	explorer.position = Vector2(146, 167)
	Input.action_press(&"move_up")
	for frame: int in range(24): await physics_frame
	_check(explorer.position.y >= 155 and not explorer.animation.moving and explorer.animation.direction_index == 1, "顶住建筑保持上向待机，不原地走路")
	Input.action_release(&"move_up")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.open_station", {"station_id": "storage"}))
	var animation_time: float = explorer.animation.elapsed_seconds
	for frame: int in range(5): await process_frame
	_check(paused and is_equal_approx(explorer.animation.elapsed_seconds, animation_time), "单机菜单暂停人物动画")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.close_station"))
	main.session.submit(WildGameCommand.new(main.local_player_id, &"expedition.prepare", {"seed": "17"}))
	main.session.submit(WildGameCommand.new(main.local_player_id, &"expedition.commit"))
	var resources: Dictionary = main.session.world_snapshot(main.local_player_id)["resources"].duplicate(true)
	Input.action_press(&"move_right")
	for frame: int in range(8): await physics_frame
	_check(main.wilderness_world.explorer.animation.moving, "荒野停用基地物理输入后仍播放权威移动动画")
	Input.action_release(&"move_right")
	for frame: int in range(2): await physics_frame
	_check(not main.wilderness_world.explorer.animation.moving, "荒野停止输入回到待机")
	_check(main.session.world_snapshot(main.local_player_id)["resources"] == resources, "动画和贴图变体不改变资源快照")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.open_station", {"station_id": "storage"}))
	animation_time = main.wilderness_world.explorer.animation.elapsed_seconds
	for frame: int in range(5): await process_frame
	_check(is_equal_approx(main.wilderness_world.explorer.animation.elapsed_seconds, animation_time), "荒野菜单暂停人物动画")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.close_station"))
	main.queue_free()
	await process_frame
	print("Ninja art checks: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(ok: bool, description: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error(description)
