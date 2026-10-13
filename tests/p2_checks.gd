extends SceneTree
## 种子 / 安全投放、完整档案、移动权威与真实场景整合验证。档案仅使用工作区。

const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const VERIFICATION = preload("res://tests/verification_paths.gd")
var _checks: int = 0
var _failures := PackedStringArray()
var _maximum_ms: float = 0
var _fallbacks: int = 0
var _generator := WildWorldGenerator.new(CONFIG)
var _example: Dictionary
var _save_ms: float = 0.0

class MemoryStore extends RefCounted:
	var primary: Dictionary = {}
	var backup: Dictionary = {}
	var fail: bool = false
	func load_records() -> WildOperationResult:
		return WildOperationResult.accept({"exists": not primary.is_empty(), "primary": primary.duplicate(true), "backup": backup.duplicate(true)})
	func save_record(data: Dictionary, preserve_backup: bool = false) -> WildOperationResult:
		if fail:
			return WildOperationResult.reject(&"SAVE_FAILED")
		if not preserve_backup:
			backup = primary.duplicate(true)
		primary = data.duplicate(true)
		return WildOperationResult.accept()

func _initialize() -> void:
	if not VERIFICATION.arguments_are_isolated():
		push_error("Tests require workspace verification paths")
		quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	if "--skip-seed-sample" in OS.get_cmdline_user_args():
		_example = _with_player(_generator.generate("17").payload["world"], "p")
	else:
		_test_seeds()
	_test_codec_and_rules()
	_test_application()
	_test_world_file()
	await _test_scene()
	for failure: String in _failures:
		push_error(failure)
	if "--skip-seed-sample" not in OS.get_cmdline_user_args():
		print("P2 map sample: 100 seeds, %d fallbacks, max %.2f ms" % [_fallbacks, _maximum_ms])
	print("P2 checks: %d passed, %d failed" % [_checks - _failures.size(), _failures.size()])
	print("P2 world file save: %.2f ms" % _save_ms)
	quit(0 if _failures.is_empty() else 1)

func _test_seeds() -> void:
	for invalid: Variant in ["", "-1", "01", "1.2", "9223372036854775808", "seed", 123]:
		_check(not WildWorldGenerator.valid_seed(invalid), "拒绝非法种子 %s" % str(invalid))
	_check(WildWorldGenerator.valid_seed("9223372036854775807"), "支持精确 64 位种子上界")
	for index: int in range(100):
		var seed_text: String = str(index * 7919 + 17)
		var started: int = Time.get_ticks_usec()
		var result: WildOperationResult = _generator.generate(seed_text)
		var elapsed: float = (Time.get_ticks_usec() - started) / 1000.0
		_maximum_ms = maxf(_maximum_ms, elapsed)
		_check(result.successful, "种子 %s 生成成功" % seed_text)
		if not result.successful:
			continue
		var record: Dictionary = _with_player(result.payload["world"], "p")
		var world: WildWorldData = WildWorldCodec.decode(record, CONFIG)
		_check(world != null, "种子 %s 比例 / 连通 / 资源数量 / 安全路径通过同一校验" % seed_text)
		_check(elapsed <= 3000, "种子 %s 生成耗时 ≤3 秒" % seed_text)
		_fallbacks += 1 if record["fallback"] else 0
		if index == 0:
			_example = record
	var repeated: Dictionary = _with_player(_generator.generate("17").payload["world"], "p")
	_check(JSON.stringify(repeated, "", true) == JSON.stringify(_example, "", true), "同种子完整地形 / 资源 / 出生 / 随机状态一致")
	var different: Dictionary = _generator.generate("18").payload["world"]
	_check(different["tiles"] != _example["tiles"], "不同种子产生不同地形")
	var fallback: WildOperationResult = _generator.generate("17", true)
	_check(fallback.successful and fallback.payload["world"]["fallback"], "有限重试后安全模板可用")
	_check(WildWorldCodec.decode(_with_player(fallback.payload["world"], "p"), CONFIG) != null, "回退模板满足同样比例与出生路径规则")
	_check(_generator.generate("oops").code == &"INVALID_SEED", "非法种子不进入生成或模板回退")

func _test_codec_and_rules() -> void:
	var world: WildWorldData = WildWorldCodec.decode(_example, CONFIG)
	if world == null:
		_check(false, "样例世界必须有效")
		return
	var previous: Vector2 = world.players["p"]
	_check(WildWorldRules.move(world, "p", Vector2.RIGHT, 2, 96) == previous, "拒绝长步长导致瞬移")
	_check(WildWorldRules.move(world, "p", Vector2(INF, 0), 0.1, 96) == previous, "拒绝非有限方向")
	world.players["other"] = previous
	WildWorldRules.move(world, "p", Vector2.RIGHT, 0.1, 96)
	_check(world.players["other"] == previous, "多玩家按身份独立移动")
	var boundary := WildWorldData.new()
	boundary.size = Vector2i(5, 5)
	boundary.tiles.resize(25)
	boundary.tiles.fill(WildWorldData.Terrain.GRASS)
	for y: int in range(5): boundary.tiles[y * 5 + 2] = WildWorldData.Terrain.WATER
	boundary.players["p"] = boundary.centre(Vector2i(1, 2))
	for step: int in range(40): WildWorldRules.move(boundary, "p", Vector2.RIGHT, 0.1, 144)
	_check(boundary.players["p"].x < 58 and WildWorldRules.feet_clear(boundary, boundary.players["p"]), "连续冲刺不跨水、不穿过足部边界")
	boundary.players["p"] = boundary.centre(Vector2i(0, 0))
	for step: int in range(40): WildWorldRules.move(boundary, "p", Vector2(-1, -1), 0.1, 144)
	_check(WildWorldRules.feet_clear(boundary, boundary.players["p"]), "地图边缘限制足部不越界")
	var resource: Dictionary = _first_resource(world, "branch")
	world.players["p"] = world.centre(Vector2i(resource["x"], resource["y"]))
	_check(WildWorldRules.interaction(world, "p", resource["id"], 0).successful, "近处可达资源可查看")
	_check(WildWorldRules.interaction(world, "p", resource["id"], 9).code == &"STALE_VERSION", "旧资源版本被拒绝")
	_check(WildWorldRules.interaction(world, "outsider", resource["id"], 0).code == &"UNKNOWN_ACTOR", "未知角色拒绝交互")
	_check(WildWorldRules.consume(world, "p", resource["id"], 0, 1).successful, "动作完成原语扣减资源并更新版本")
	_check(WildWorldRules.consume(world, "p", resource["id"], 0, 1).code == &"STALE_VERSION", "同资源不能重复消耗")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(world.record()))
	var restored: WildWorldData = WildWorldCodec.decode(roundtrip, CONFIG)
	_check(restored != null and restored.resources[resource["id"]]["remaining"] == 0, "资源消耗后完整档案恢复不再出现")
	_check(restored != null and restored.initial_resources[resource["id"]]["remaining"] == 1, "保留原始世界与当前变更")
	var invalid: Dictionary = _example.duplicate(true)
	invalid["players"]["p"] = [-1, -1]
	_check(WildWorldCodec.decode(invalid, CONFIG) == null, "拒绝越界存档坐标")
	invalid = _example.duplicate(true)
	invalid["tiles"][0] = "bad"
	_check(WildWorldCodec.decode(invalid, CONFIG) == null, "拒绝坏地形行而非重新生成")
	invalid = _example.duplicate(true)
	invalid["resources"][resource["id"]]["remaining"] = 2
	_check(WildWorldCodec.decode(invalid, CONFIG) == null, "拒绝超初始库存的资源档案")
	invalid = _example.duplicate(true)
	invalid["rng_states"]["terrain"] = 123
	_check(WildWorldCodec.decode(invalid, CONFIG) == null, "RNG 大整数必须以字符串保存")
	var maximum: Dictionary = _with_player(_generator.generate("9223372036854775807").payload["world"], "p")
	var decoded_maximum: WildWorldData = WildWorldCodec.decode(JSON.parse_string(JSON.stringify(maximum)), CONFIG)
	_check(decoded_maximum != null and decoded_maximum.seed_text == "9223372036854775807", "JSON 往返完整保存 64 位种子")

func _test_application() -> void:
	var memory := MemoryStore.new()
	var service := WildBaseService.new(CONFIG, CATALOG, memory.load_records, memory.save_record, Callable(), _generator.generate)
	_check(service.initialize("p").successful, "探索事务服务初始化")
	_check(service.submit(WildGameCommand.new("p", &"expedition.prepare", {"seed": "bad"})).code == &"INVALID_SEED", "无效种子不改变物资与流程")
	_check(service.current_phase() == WildRunFlow.Phase.BASE, "非法种子仍在基地")
	service.submit(WildGameCommand.new("p", &"expedition.prepare", {"seed": "17"}))
	var start: Dictionary = service.snapshot()
	var commit := WildGameCommand.new("p", &"expedition.commit")
	memory.fail = true
	_check(service.submit(commit).code == &"SAVE_FAILED", "生成后保存失败不提交世界")
	_check(service.current_phase() == WildRunFlow.Phase.PREPARATION and service.world_record().is_empty(), "失败仍保留原准备和物资")
	memory.fail = false
	_check(service.submit(commit).successful, "同请求保存恢复后可继续出发")
	_check(service.world_record()["seed"] == "17", "实际出发使用锁定种子")
	_check(service.submit(commit).successful, "重发出发请求返回原收据")
	var first: Dictionary = service.world_record()
	var tampered: Dictionary = first.duplicate(true)
	tampered["tiles"][0] = "bad"
	_check(service.world_record()["tiles"][0] != "bad", "世界快照不泄漏可变引用")
	var position: Vector2 = service.player_position("p")
	service.move_player("p", Vector2.RIGHT, 0.1, false)
	memory.fail = true
	_check(not service.checkpoint().successful, "位置检查点保存失败可报告")
	memory.fail = false
	_check(service.checkpoint().successful, "检查点失败后可重试")
	var restarted := WildBaseService.new(CONFIG, CATALOG, memory.load_records, memory.save_record, Callable(), func(_seed: String) -> WildOperationResult: return WildOperationResult.reject(&"GENERATION_FAILED"))
	_check(restarted.initialize("p").successful, "恢复已有世界不调用生成器")
	_check(restarted.player_position("p").is_equal_approx(service.player_position("p")), "重开恢复真实当前位置")
	_check(restarted.world_record()["tiles"] == first["tiles"], "重开恢复完整地图")
	var knife: Dictionary = start["containers"]["warehouse"]["entries"][0]
	_check(service.submit(WildGameCommand.new("p", &"inventory.transfer", {"source": "warehouse", "target": "backpack", "item_id": knife["item"]["id"]})).code == &"FORBIDDEN_CONTAINER", "荒野不能远程取基地仓库")
	_check(service.submit(WildGameCommand.new("p", &"shop.buy", {"definition_id": "axe"})).code == &"INVALID_PHASE", "荒野不能购买")
	_check(service.submit(WildGameCommand.new("p", &"expedition.return_exploration")).successful and service.current_phase() == WildRunFlow.Phase.BASE, "结束探索恢复基地而非成功结算")
	_check(service.snapshot()["currency"] == 600 and service.world_record().is_empty(), "探索返回不发奖励、不留运行世界")
	var bad_memory := MemoryStore.new()
	var bad := WildBaseService.new(CONFIG, CATALOG, bad_memory.load_records, bad_memory.save_record, Callable(), func(_seed: String) -> WildOperationResult: return WildOperationResult.reject(&"GENERATION_FAILED"))
	bad.initialize("p")
	bad.submit(WildGameCommand.new("p", &"expedition.prepare", {"seed": "1"}))
	_check(bad.submit(WildGameCommand.new("p", &"expedition.commit")).code == &"GENERATION_FAILED", "所有生成方式失败时回滚")
	_check(bad.current_phase() == WildRunFlow.Phase.BASE and bad_memory.primary["active_run"].is_empty(), "失败回滚保存基地、不挂在生成态")
	# P1 的旧准备档没有 seed，读取后补充并保存；占位荒野仍按旧返回路径处理。
	var legacy := MemoryStore.new()
	var old := WildBaseService.new(CONFIG, CATALOG, legacy.load_records, legacy.save_record)
	old.initialize("p")
	old.submit(WildGameCommand.new("p", &"expedition.prepare"))
	legacy.primary["active_run"].erase("seed")
	var migrated := WildBaseService.new(CONFIG, CATALOG, legacy.load_records, legacy.save_record, Callable(), _generator.generate)
	_check(migrated.initialize("p").successful and WildWorldGenerator.valid_seed(migrated.snapshot()["seed"]), "兼容 P1 旧准备档补充种子")

func _test_world_file() -> void:
	var world: WildWorldData = WildWorldCodec.decode(_example, CONFIG)
	var resource: Dictionary = _first_resource(world, "branch")
	world.players["p"] = world.centre(Vector2i(resource["x"], resource["y"]))
	WildWorldRules.consume(world, "p", resource["id"], 0, 1)
	var state := WildBaseState.new("p", CONFIG)
	state.phase = WildRunFlow.Phase.WILDERNESS
	state.active_run = {"run_id": "file-world", "seed": "17", "exploration_only": true, "origin_containers": WildBaseState.new("p", CONFIG).record()["containers"]}
	state.world = world
	var path: String = "res://.godot/verification/p2_file_%s.json" % WildStableId.create("save")
	var store := WildBaseStateStore.new(path)
	var started: int = Time.get_ticks_usec()
	_check(store.save_record(state.record()).successful, "真实文件保存完整世界")
	_save_ms = (Time.get_ticks_usec() - started) / 1000.0
	var service := WildBaseService.new(CONFIG, CATALOG, store.load_records, store.save_record, Callable(), func(_seed: String) -> WildOperationResult: return WildOperationResult.reject(&"GENERATION_FAILED"))
	_check(service.initialize("p").successful, "真实 JSON 文件恢复不调用生成器")
	var restored: Dictionary = service.world_record()
	_check(not restored.is_empty() and restored["resources"][resource["id"]]["remaining"] == 0, "实际文件重开不刷新耗尽资源")
	_check(service.player_position("p").is_equal_approx(world.players["p"]), "实际文件恢复当前位置")
	_check(store.save_record(state.record()).successful, "保存第二份世界建立完整备份")
	var corrupt: Dictionary = state.record()
	corrupt["active_run"]["world"]["tiles"][0] = "bad"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt))
	file.close()
	var recovery := WildBaseService.new(CONFIG, CATALOG, store.load_records, store.save_record)
	var result: WildOperationResult = recovery.initialize("p")
	_check(result.successful and result.payload.get("recovered_backup", false), "损坏世界从完整备份恢复")
	_check(not recovery.world_record().is_empty() and recovery.world_record()["resources"][resource["id"]]["remaining"] == 0, "备份保持资源变更，未靠种子重建")

func _test_scene() -> void:
	var main: WildMain = MAIN.instantiate() as WildMain
	main._profile_path = VERIFICATION.profile("p2-scene")
	root.add_child(main)
	main.session.set_focus_lost(false)
	await process_frame
	_check(main.session != null, "主场景接入会话")
	if main.session == null:
		return
	main.session.submit(WildGameCommand.new(main.local_player_id, &"expedition.prepare", {"seed": "17"}))
	main.session.submit(WildGameCommand.new(main.local_player_id, &"expedition.commit"))
	await process_frame
	_check(main.wilderness_world.visible and main.wilderness_world.camera.enabled and not main.base_world.visible, "真实随机世界与跟随相机切换")
	_check(main.wilderness_world.find_children("*", "TileMapLayer", true, false).size() == 2, "分层地形使用 TileMapLayer")
	main.wilderness_world.request_interaction()
	await process_frame
	_check(main.session.active_station() == &"pause" and paused, "资源交互打开详情并暂停单机")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.close_station"))
	var before: Vector2 = main.session.world_position(main.local_player_id)
	Input.action_press(&"move_right")
	for frame: int in range(4): await physics_frame
	Input.action_release(&"move_right")
	_check(main.session.world_position(main.local_player_id).distance_to(before) > 0, "实际输入驱动权威角色移动")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.open_station", {"station_id": "storage"}))
	await process_frame
	var stopped: Vector2 = main.session.world_position(main.local_player_id)
	Input.action_press(&"move_left")
	for frame: int in range(3): await physics_frame
	Input.action_release(&"move_left")
	_check(main.session.world_position(main.local_player_id) == stopped, "单机库存菜单暂停世界输入")
	var warehouse_visible: bool = false
	for node: Node in main.find_children("*", "WildInventoryGrid", true, false):
		if node.container_id == "warehouse" and node.is_visible_in_tree(): warehouse_visible = true
	_check(not warehouse_visible, "荒野不显示远程基地仓库")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.close_station"))
	main.session.submit(WildGameCommand.new(main.local_player_id, &"survival.abandon" if main.session.base_snapshot(main.local_player_id).get("survival_enabled",false) else &"expedition.return_exploration"))
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.close_station"))
	await process_frame
	_check(main.base_world.visible and not main.wilderness_world.camera.enabled and not paused, "返回基地关闭相机并恢复输入")
	main.queue_free()
	await process_frame

func _with_player(record: Dictionary, actor: String) -> Dictionary:
	var result: Dictionary = record.duplicate(true)
	result["players"] = {actor: [(float(result["spawn"][0]) + 0.5) * CONFIG.terrain_tile_pixels, (float(result["spawn"][1]) + 0.5) * CONFIG.terrain_tile_pixels]}
	return result

func _first_resource(world: WildWorldData, kind: String) -> Dictionary:
	for entry: Dictionary in world.resources.values():
		if entry["kind"] == kind: return entry
	return {}

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition: _failures.append(message)
