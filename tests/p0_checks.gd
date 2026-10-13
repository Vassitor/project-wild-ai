extends SceneTree
## P0 自动验证：真实场景 / 碰撞、身份持久化、权限、状态机与模式隔离。
## 使用工作区临时身份文件，不读取或更改玩家正式 user:// 档案。

const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const VERIFICATION = preload("res://tests/verification_paths.gd")

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _initialize() -> void:
	if not VERIFICATION.arguments_are_isolated():
		push_error("Tests require workspace verification paths")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	_check(CONFIG.validate().is_empty(), "配置通过有效性校验")
	var invalid: WildGameConfig = CONFIG.duplicate() as WildGameConfig
	invalid.hard_weight_limit_kg = invalid.soft_weight_limit_kg
	_check(not invalid.validate().is_empty(), "无效负重阈值被拒绝")
	_check(CONFIG.hard_weight_limit_kg > CONFIG.soft_weight_limit_kg, "测试修改没有污染共享配置")
	_check(WildSessionPolicy.pauses_world(WildSessionPolicy.Mode.SINGLE_PLAYER, true, false), "单机个人菜单暂停")
	_check(not WildSessionPolicy.pauses_world(WildSessionPolicy.Mode.COOPERATIVE, true, true), "合作个人菜单 / 失焦不暂停世界")
	_test_flow()
	_test_identity()
	_test_session()
	await _test_scene()
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("P0 checks: %d passed, %d failed" % [_checks - _failures.size(), _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_flow() -> void:
	var flow := WildRunFlow.new()
	_check(not flow.try_transition(WildRunFlow.Phase.WILDERNESS).successful, "不能从基地直接跳过准备与生成")
	_check(flow.current_phase == WildRunFlow.Phase.BASE, "非法转换保留原阶段")
	_check(flow.try_transition(WildRunFlow.Phase.PREPARATION).successful, "基地可进入准备")
	_check(flow.try_transition(WildRunFlow.Phase.GENERATING).successful, "准备可开始生成")
	_check(flow.try_transition(WildRunFlow.Phase.BASE).successful, "生成失败可退回基地")


func _test_identity() -> void:
	var path: String = "res://.godot/verification/%s.cfg" % WildStableId.create("identity_test")
	var store := WildProfileIdentityStore.new(path)
	var first: WildOperationResult = store.load_or_create()
	var second: WildOperationResult = WildProfileIdentityStore.new(path).load_or_create()
	_check(first.successful and second.successful, "身份创建与读取成功")
	_check(first.payload.get("player_id", "") == second.payload.get("player_id", "missing"), "重启读取保留稳定玩家 ID")
	_check(str(first.payload.get("player_id", "")).begins_with("player_"), "玩家身份与临时连接 ID 分离")
	var broken := ConfigFile.new()
	broken.set_value("identity", "version", 99)
	broken.set_value("identity", "player_id", "legacy")
	broken.save(path)
	_check(not store.load_or_create().successful, "不覆盖版本不兼容的身份档案")


func _test_session() -> void:
	var local := WildLocalSession.new()
	var player := WildPlayerState.new("test_player", "测试生存者", CONFIG)
	_check(local.register_player(player).successful, "可以注册角色")
	_check(not local.register_player(player).successful, "重复注册不能复制角色")
	var snapshot: Dictionary = local.player_snapshot(player.player_id)
	(snapshot["nutrition"] as Dictionary)[&"protein"] = 0.0
	_check(local.player_snapshot(player.player_id)["nutrition"][&"protein"] > 0.0, "界面快照不能修改真实营养")
	var forged := WildGameCommand.new("unknown", &"base.open_station", {"station_id": "storage"})
	_check(local.submit(forged).code == &"UNKNOWN_ACTOR", "未知身份不能操作")
	_check(local.submit(WildGameCommand.new(player.player_id, &"base.open_station", {"station_id": "not_a_station"})).code == &"UNKNOWN_STATION", "未知入口被拒绝")
	var command := WildGameCommand.new(player.player_id, &"base.open_station", {"station_id": "storage"}, "stable_request")
	var response: WildOperationResult = local.submit(command)
	_check(response.successful and local.is_paused(), "合法入口命令打开面板并暂停")
	response.payload["station_id"] = "mutated"
	_check(local.submit(command).payload["station_id"] == "storage", "调用者不能污染缓存结果")
	var reused := WildGameCommand.new(player.player_id, &"base.open_station", {"station_id": "training"}, "stable_request")
	_check(local.submit(reused).code == &"REQUEST_ID_CONFLICT", "相同 ID 不得重用于不同操作")
	_check(local.active_station() == &"storage", "冲突操作不修改状态")
	local.submit(WildGameCommand.new(player.player_id, &"base.close_station"))
	_check(not local.is_paused(), "关闭面板恢复本地模拟")
	var cooperative := WildLocalSession.new(WildSessionPolicy.Mode.COOPERATIVE)
	cooperative.register_player(WildPlayerState.new("coop_preview", "队员", CONFIG))
	cooperative.submit(WildGameCommand.new("coop_preview", &"base.open_station", {"station_id": "storage"}))
	_check(not cooperative.is_paused(), "合作策略不因个人操作而暂停")


func _test_scene() -> void:
	var main: WildMain = MAIN.instantiate() as WildMain
	main._profile_path = VERIFICATION.profile("p0-scene")
	root.add_child(main)
	main.session.set_focus_lost(false)
	await process_frame
	await physics_frame
	_check(main.session != null and main.base_world != null, "主场景创建会话和基地")
	if main.session == null or main.base_world == null:
		main.queue_free()
		return
	var explorer: WildBaseExplorer = main.base_world.explorer_for(main.local_player_id)
	_check(explorer != null, "按玩家 ID 创建移动视图")
	if explorer == null:
		main.queue_free()
		return
	var original: Vector2 = explorer.position
	Input.action_press(&"move_right")
	await create_timer(0.18, true, false, true).timeout
	Input.action_release(&"move_right")
	_check(explorer.position.x > original.x + 5.0, "输入能驱动真实角色移动")
	# 位于补给站下沿向上移动，应被建筑碰撞阻挡。
	explorer.position = Vector2(146, 178)
	Input.action_press(&"move_up")
	await create_timer(0.5, true, false, true).timeout
	Input.action_release(&"move_up")
	_check(explorer.position.y >= 155.0, "角色不能穿过建筑")
	await process_frame
	_check(main.base_world.interaction_target() == &"supply", "靠近补给站产生交互目标")
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.pressed = true
	Input.parse_input_event(interact)
	await process_frame
	_check(main.session.active_station() == &"supply", "E 键经意图 / 会话打开入口")
	_check(paused, "打开面板暂停物理移动")
	var before_pause: Vector2 = explorer.position
	Input.action_press(&"move_right")
	await create_timer(0.15, true, false, true).timeout
	Input.action_release(&"move_right")
	_check(explorer.position.is_equal_approx(before_pause), "暂停期间角色不移动")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.close_station"))
	_check(not paused, "关闭面板恢复场景")
	main.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
