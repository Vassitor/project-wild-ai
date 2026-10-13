extends SceneTree
## P1 验证关注物资守恒、事务回滚、非法数据、跨重启去重和真实 UI 接线。

const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const VERIFICATION = preload("res://tests/verification_paths.gd")
var _failures := PackedStringArray()
var _checks: int = 0

class MemoryStore:
	extends RefCounted
	var data: Dictionary = {}
	var fail_save: bool = false
	func load_records() -> WildOperationResult:
		return WildOperationResult.accept({"exists": not data.is_empty(), "primary": data.duplicate(true), "backup": {}})
	func save_record(record: Dictionary, _preserve: bool = false) -> WildOperationResult:
		if fail_save:
			return WildOperationResult.reject(&"SAVE_FAILED")
		data = record.duplicate(true)
		return WildOperationResult.accept()


func _initialize() -> void:
	if not VERIFICATION.arguments_are_isolated():
		push_error("Tests require workspace verification paths")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	_check(CATALOG.validate() and CATALOG.definitions.size() == 25, "25 个物品定义有效且 ID 唯一")
	_test_grid()
	_test_transfer()
	_test_transactions()
	_test_departure()
	_test_files()
	await _test_ui()
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("P1 checks: %d passed, %d failed" % [_checks - _failures.size(), _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_grid() -> void:
	var state := WildBaseState.new("p", CONFIG)
	var axe := WildItemInstance.new(CATALOG.find(&"axe"))
	var bag: WildInventoryContainer = state.containers["backpack"]
	_check(WildInventoryRules.can_place(state, CATALOG, CONFIG, "p", bag, axe, Vector2i(7, 4), false).code == &"OUT_OF_BOUNDS", "越界拒绝")
	_check(WildInventoryRules.can_place(state, CATALOG, CONFIG, "p", bag, axe, Vector2i(5, 4), true).successful, "旋转后按 3×2 检查尺寸")
	bag.placements[axe.instance_id] = {"item": axe, "position": Vector2i.ZERO, "rotated": false}
	var knife := WildItemInstance.new(CATALOG.find(&"knife"))
	_check(WildInventoryRules.can_place(state, CATALOG, CONFIG, "p", bag, knife, Vector2i(1, 1), false).code == &"OVERLAP", "重叠拒绝")
	var small := WildInventoryContainer.new("small", "p", Vector2i(4, 4), 0.1)
	_check(WildInventoryRules.can_place(state, CATALOG, CONFIG, "p", small, knife, Vector2i.ZERO, false).code == &"VOLUME_LIMIT", "体积与几何独立校验")
	var heavy_catalog: WildItemCatalog = CATALOG.duplicate(true) as WildItemCatalog
	var heavy := WildItemDefinition.new()
	heavy.item_id = &"heavy_fixture"
	heavy.display_name = "负重测试"
	heavy.unit_weight_kg = 35.0
	heavy.unit_volume_l = 0.1
	heavy_catalog.definitions.append(heavy)
	_check(WildInventoryRules.can_place(state, heavy_catalog, CONFIG, "p", bag, WildItemInstance.new(heavy), Vector2i(4, 0), false).code == &"WEIGHT_LIMIT", "有空间仍不能超过 30 kg")
	var bottle := WildItemInstance.new(CATALOG.find(&"bottle"))
	bottle.water_l = 1.0
	_check(is_equal_approx(bottle.weight(CATALOG.find(&"bottle")), 1.25), "满水壶重量包含水")
	_check(is_equal_approx(bottle.volume(CATALOG.find(&"bottle")), 1.2), "水不重复计算外部体积")
	_check(WildInventoryRules.can_place(state, CATALOG, CONFIG, "p", state.containers["armor"], knife, Vector2i.ZERO, false).code == &"INVALID_CATEGORY", "护甲槽拒绝工具")
	_check(WildInventoryRules.can_place(state, CATALOG, CONFIG, "p", state.containers["main_hand"], axe, Vector2i.ZERO, false, "", true).successful, "装备槽接受工具且使用独立空间")
	var private := WildInventoryContainer.new("private", "someone_else", Vector2i(4, 4), 5.0)
	_check(WildInventoryRules.can_place(state, CATALOG, CONFIG, "p", private, knife, Vector2i.ZERO, false).code == &"FORBIDDEN_CONTAINER", "他人私人物品权限拒绝")
	private.public_access = true
	_check(WildInventoryRules.can_place(state, CATALOG, CONFIG, "p", private, knife, Vector2i.ZERO, false).successful, "公开容器允许队员操作")


func _test_transfer() -> void:
	var state := WildBaseState.new("p", CONFIG)
	var ration := WildItemInstance.new(CATALOG.find(&"ration"), 4)
	var warehouse: WildInventoryContainer = state.containers["warehouse"]
	warehouse.placements[ration.instance_id] = {"item": ration, "position": Vector2i.ZERO, "rotated": false}
	var original: String = JSON.stringify(state.record(), "", true)
	var stale: Dictionary = _move_data(state, "warehouse", "backpack", ration.instance_id, Vector2i.ZERO)
	stale["source_version"] = 99
	_check(WildInventoryRules.transfer(state, CATALOG, CONFIG, "p", stale).code == &"STALE_VERSION", "旧版本操作拒绝")
	_check(JSON.stringify(state.record(), "", true) == original, "失败转移不修改任一容器")
	var split: Dictionary = _move_data(state, "warehouse", "warehouse", ration.instance_id, Vector2i(1, 0))
	split["quantity"] = 2
	var divided: WildOperationResult = WildInventoryRules.transfer(state, CATALOG, CONFIG, "p", split)
	_check(divided.successful and warehouse.placements.size() == 2, "拆分生成两个独立实例")
	_check(_total_quantity(state, &"ration") == 4, "拆分数量守恒")
	_check(is_equal_approx(warehouse.volume(CATALOG), 1.4), "拆分体积守恒")
	var part_id: String = divided.payload["instance_id"]
	var merge: Dictionary = _move_data(state, "warehouse", "warehouse", part_id, Vector2i.ZERO)
	_check(WildInventoryRules.transfer(state, CATALOG, CONFIG, "p", merge).successful, "同类堆叠合并")
	_check(warehouse.placements.size() == 1 and _total_quantity(state, &"ration") == 4, "合并不复制物品")
	var fractional: Dictionary = _move_data(state, "warehouse", "backpack", ration.instance_id, Vector2i.ZERO)
	fractional["quantity"] = 1.5
	_check(not WildInventoryRules.transfer(state, CATALOG, CONFIG, "p", fractional).successful, "小数数量拒绝而非截断")
	_check(WildInventoryRules.transfer(state, CATALOG, CONFIG, "p", _move_data(state, "warehouse", "backpack", ration.instance_id, Vector2i.ZERO)).successful, "完整堆叠跨容器转移")
	_check(warehouse.placements.is_empty() and _total_quantity(state, &"ration") == 4, "源清除、目标唯一保留")
	var decoded: WildBaseState = WildBaseStateCodec.decode(state.record(), "p", CONFIG, CATALOG)
	_check(decoded != null, "合法状态可恢复")
	var invalid: Dictionary = state.record()
	invalid["containers"]["backpack"]["entries"][0]["position"] = [8, 6]
	_check(WildBaseStateCodec.decode(invalid, "p", CONFIG, CATALOG) == null, "坏布局不被静默读入")
	invalid = state.record()
	invalid["containers"]["backpack"]["entries"][0]["item"]["quantity"] = 1.5
	_check(WildBaseStateCodec.decode(invalid, "p", CONFIG, CATALOG) == null, "坏存档的非整数数量拒绝")
	_check(WildBaseStateCodec.decode(state.record(), "other", CONFIG, CATALOG) == null, "档案不能冒用其他身份")
	var self_split: Dictionary = _move_data(state, "backpack", "backpack", ration.instance_id, Vector2i.ZERO)
	self_split["quantity"] = 1
	_check(WildInventoryRules.transfer(state, CATALOG, CONFIG, "p", self_split).code == &"SAME_ITEM", "不能拆分后再放回同一物品")
	var extra := WildItemInstance.new(CATALOG.find(&"ration"))
	warehouse.placements[extra.instance_id] = {"item": extra, "position": Vector2i.ZERO, "rotated": false}
	var before_overflow: String = JSON.stringify(state.record(), "", true)
	_check(WildInventoryRules.transfer(state, CATALOG, CONFIG, "p", _move_data(state, "warehouse", "backpack", extra.instance_id, Vector2i.ZERO)).code == &"OVERLAP", "堆叠上限仍生效")
	_check(JSON.stringify(state.record(), "", true) == before_overflow, "满堆叠失败数量和布局不变")
	var enormous: Dictionary = state.record()
	enormous["currency"] = 1e30
	_check(WildBaseStateCodec.decode(enormous, "p", CONFIG, CATALOG) == null, "超出安全整数范围的档案拒绝")


func _test_transactions() -> void:
	var memory := MemoryStore.new()
	var service: WildBaseService = _service(memory)
	_check(service.snapshot()["currency"] == 600, "新档案初始化货币")
	_check(service.snapshot()["containers"]["warehouse"]["entries"].size() == 3, "三个免费工具自动提供")
	var buy := WildGameCommand.new("p", &"shop.buy", {"definition_id": "ration", "quantity": 4}, "buy_once")
	_check(service.submit(buy).successful and service.snapshot()["currency"] == 480, "购买按数量扣款并入仓")
	_check(service.submit(buy).successful and service.snapshot()["currency"] == 480, "同请求重复不扣款")
	service = _service(memory)
	_check(service.submit(buy).successful and service.snapshot()["currency"] == 480, "重启后收据仍能去重")
	memory.fail_save = true
	var retriable := WildGameCommand.new("p", &"shop.buy", {"definition_id": "axe", "quantity": 1}, "retry_after_disk_failure")
	var before: String = JSON.stringify(service.snapshot(), "", true)
	_check(service.submit(retriable).code == &"SAVE_FAILED", "保存失败返回明确结果")
	_check(JSON.stringify(service.snapshot(), "", true) == before, "保存失败不提交货币或物品")
	memory.fail_save = false
	_check(service.submit(retriable).successful and service.snapshot()["currency"] == 230, "保存恢复后可重试同 ID")
	_check(service.submit(WildGameCommand.new("p", &"shop.buy", {"definition_id": "leather_armor"})).code == &"INSUFFICIENT_CURRENCY", "资金不足无交易")
	_check(service.snapshot()["currency"] == 230, "资金不足不改变余额")
	_check(service.submit(WildGameCommand.new("p", &"shop.buy", {"definition_id": "wood"})).code == &"NOT_FOR_SALE", "资源不作为商店商品")
	var view: Dictionary = service.snapshot()
	var free: Dictionary = view["containers"]["warehouse"]["entries"][0]["item"]
	_check(service.submit(WildGameCommand.new("p", &"shop.sell", {"item_id": free["id"], "version": view["containers"]["warehouse"]["version"]})).code == &"FREE_SUPPLY", "免费补给不能出售套利")
	var count_before: int = view["containers"]["warehouse"]["entries"].size()
	service.submit(WildGameCommand.new("p", &"supply.claim"))
	_check(service.snapshot()["containers"]["warehouse"]["entries"].size() == count_before, "反复领取不堆积基础工具")
	_check(service.submit(WildGameCommand.new("other", &"shop.buy", {"definition_id": "ration"})).code == &"UNKNOWN_ACTOR", "事务身份校验")
	var conflict := WildGameCommand.new("p", &"shop.buy", {"definition_id": "knife"}, "buy_once")
	_check(service.submit(conflict).code == &"REQUEST_ID_CONFLICT", "持久收据防止编号被复用")
	var ration_entry: Dictionary = _find_entry(service.snapshot(), "warehouse", &"ration")
	view = service.snapshot()
	_check(service.submit(WildGameCommand.new("p", &"shop.sell", {"item_id": ration_entry["item"]["id"], "version": view["containers"]["warehouse"]["version"], "quantity": 1})).successful, "非免费库存可出售部分数量")
	_check(service.snapshot()["currency"] == 242, "出售按单份价格 40% 计算")
	var filled: WildBaseState = WildBaseStateCodec.decode(memory.data, "p", CONFIG, CATALOG)
	var warehouse: WildInventoryContainer = filled.containers["warehouse"]
	for y: int in range(warehouse.grid_size.y):
		for x: int in range(warehouse.grid_size.x):
			if warehouse.item_at(Vector2i(x, y), CATALOG).is_empty():
				var stone := WildItemInstance.new(CATALOG.find(&"stone"))
				warehouse.placements[stone.instance_id] = {"item": stone, "position": Vector2i(x, y), "rotated": false}
	memory.data = filled.record()
	var full: WildBaseService = _service(memory)
	var balance: int = full.snapshot()["currency"]
	_check(full.submit(WildGameCommand.new("p", &"shop.buy", {"definition_id": "ration"})).code == &"NO_SPACE", "满仓购买拒绝")
	_check(full.snapshot()["currency"] == balance, "满仓购买不扣货币")


func _test_departure() -> void:
	var memory := MemoryStore.new()
	var service: WildBaseService = _service(memory)
	for index: int in range(6):
		service.submit(WildGameCommand.new("p", &"shop.buy", {"definition_id": "arrow"}))
	var origin: Dictionary = service.snapshot()
	_check(service.submit(WildGameCommand.new("p", &"expedition.prepare")).successful, "开始准备生成稳定任务 ID")
	for entry: Dictionary in origin["containers"]["warehouse"]["entries"]:
		if entry["item"]["item_id"] == "arrow":
			_check(_auto_transfer(service, "warehouse", "backpack", entry["item"]["id"]).successful, "装载物资")
	_check(service.snapshot()["containers"]["backpack"]["entries"].size() == 6, "超过五件仍可合法装载")
	_check(service.submit(WildGameCommand.new("p", &"shop.buy", {"definition_id": "ration"})).code == &"INVALID_PHASE", "准备中不能通过购买破坏回滚快照")
	_check(service.submit(WildGameCommand.new("p", &"expedition.cancel")).successful, "取消准备")
	_check(_contents(service.snapshot()) == _contents(origin), "取消恢复原坐标、数量、ID、朝向")
	_check(service.snapshot()["currency"] == origin["currency"], "取消不退已发生的基地交易")
	service.submit(WildGameCommand.new("p", &"expedition.prepare"))
	_check(service.submit(WildGameCommand.new("p", &"expedition.commit")).successful, "提交进入占位荒野")
	_check(service.current_phase() == WildRunFlow.Phase.WILDERNESS, "单局与基地状态切换")
	var loaded: WildBaseService = _service(memory)
	_check(loaded.current_phase() == WildRunFlow.Phase.WILDERNESS, "重启恢复任务与阶段")
	_check(loaded.submit(WildGameCommand.new("p", &"expedition.return_placeholder")).successful, "占位荒野允许无奖励返回")
	_check(_contents(loaded.snapshot()) == _contents(origin), "占位返回保留全部物资")
	var failure_memory := MemoryStore.new()
	var failure: WildBaseService = _service(failure_memory, func() -> bool: return false)
	var before: Dictionary = failure.snapshot()
	failure.submit(WildGameCommand.new("p", &"expedition.prepare"))
	var entry: Dictionary = _find_entry(failure.snapshot(), "warehouse", &"knife")
	_auto_transfer(failure, "warehouse", "backpack", entry["item"]["id"])
	_check(failure.submit(WildGameCommand.new("p", &"expedition.commit")).code == &"GENERATION_FAILED", "投放失败明确反馈")
	_check(failure.current_phase() == WildRunFlow.Phase.BASE and _contents(failure.snapshot()) == _contents(before), "投放失败原子恢复基地和物资")
	_check(_service(failure_memory).current_phase() == WildRunFlow.Phase.BASE, "失败恢复结果已经持久化")


func _test_files() -> void:
	var path: String = "res://.godot/verification/%s.json" % WildStableId.create("p1_file_test")
	var store := WildBaseStateStore.new(path)
	var service := WildBaseService.new(CONFIG, CATALOG, store.load_records, store.save_record)
	_check(service.initialize("p").successful, "真实文件创建")
	_check(service.submit(WildGameCommand.new("p", &"shop.buy", {"definition_id": "ration"})).successful, "实际原子替换已有文件")
	var reloaded := WildBaseService.new(CONFIG, CATALOG, store.load_records, store.save_record)
	_check(reloaded.initialize("p").successful and reloaded.snapshot()["currency"] == 570, "真实文件恢复余额与库存")
	var invalid: Dictionary = store.load_records().payload["primary"]
	invalid["containers"]["warehouse"]["entries"][0]["position"] = [999, 999]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(invalid))
	file.close()
	var recovery := WildBaseService.new(CONFIG, CATALOG, store.load_records, store.save_record)
	var recovered: WildOperationResult = recovery.initialize("p")
	_check(recovered.successful and recovered.payload.get("recovered_backup", false), "无效布局可从最近完整备份恢复")
	_check(recovery.snapshot()["currency"] == 600, "备份恢复明确使用上一份有效状态")
	var restart := WildBaseService.new(CONFIG, CATALOG, store.load_records, store.save_record)
	_check(restart.initialize("p").successful, "恢复后正式档案有效")
	var future: Dictionary = store.load_records().payload["primary"]
	future["save_version"] = 99
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(future))
	file.close()
	var unsupported := WildBaseService.new(CONFIG, CATALOG, store.load_records, store.save_record)
	_check(not unsupported.initialize("p").successful, "不支持的新版本不使用旧备份冒充恢复")
	_check(store.load_records().payload["primary"]["save_version"] == 99, "拒绝未知版本后不覆盖文件")


func _test_ui() -> void:
	var main: WildMain = MAIN.instantiate() as WildMain
	main._profile_path = VERIFICATION.profile("p1-scene")
	root.add_child(main)
	main.session.set_focus_lost(false)
	await process_frame
	_check(main.session != null and not main.session.base_snapshot(main.local_player_id).is_empty(), "主界面注入事务服务")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.open_station", {"station_id": "supply"}))
	await process_frame
	var buy: Button
	for node: Node in main.find_children("*", "", true, false):
		if node is Button and node.text == "购买":
			buy = node
	_check(buy != null, "商店显示实际购买按钮")
	if buy != null:
		var balance: int = main.session.base_snapshot(main.local_player_id)["currency"]
		buy.pressed.emit()
		await process_frame
		_check(main.session.base_snapshot(main.local_player_id)["currency"] == balance - 250, "UI 按钮经过会话完成购买")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.open_station", {"station_id": "storage"}))
	await process_frame
	var warehouse: WildInventoryGrid
	var bag: WildInventoryGrid
	for node: Node in main.find_children("*", "", true, false):
		if node is WildInventoryGrid:
			if node.container_id == "warehouse": warehouse = node
			if node.container_id == "backpack": bag = node
	_check(warehouse != null and bag != null, "真实仓库与背包网格已接线")
	if warehouse != null and bag != null:
		var view: Dictionary = main.session.base_snapshot(main.local_player_id)
		var entry: Dictionary = _find_entry(view, "warehouse", &"axe")
		if entry.is_empty():
			_check(false, "购买后仓库存在斧头实例")
			main.session.submit(WildGameCommand.new(main.local_player_id, &"base.close_station"))
			main.queue_free()
			await process_frame
			return
		var data: Dictionary = {"source": "warehouse", "source_version": view["containers"]["warehouse"]["version"], "item_id": entry["item"]["id"], "definition_id": "axe", "quantity": 1, "rotated": false}
		_check(bag._can_drop_data(Vector2(2, 2), data), "UI 拖放预览使用规则校验")
		bag._drop_data(Vector2(2, 2), data)
		await process_frame
		_check(not _find_entry(main.session.base_snapshot(main.local_player_id), "backpack", &"axe").is_empty(), "真实拖放路由提交并保存")
		# 真实按键应在 GUI 列表 / 输入框之前处理物品旋转。
		for node: Node in main.find_children("*", "", true, false):
			if node is WildInventoryGrid and node.container_id == "backpack": bag = node
		bag.item_selected.emit("backpack", entry["item"]["id"])
		var rotate := InputEventKey.new()
		rotate.physical_keycode = KEY_R
		rotate.pressed = true
		Input.parse_input_event(rotate)
		await process_frame
		_check(_find_entry(main.session.base_snapshot(main.local_player_id), "backpack", &"axe")["rotated"], "R 键旋转已选物品")
		rotate.pressed = false
		Input.parse_input_event(rotate)
		main.session.submit(WildGameCommand.new(main.local_player_id, &"shop.buy", {"definition_id": "ration", "quantity": 4}))
		await process_frame
		for node: Node in main.find_children("*", "", true, false):
			if node is WildInventoryGrid:
				if node.container_id == "warehouse": warehouse = node
				if node.container_id == "backpack": bag = node
		var ration: Dictionary = _find_entry(main.session.base_snapshot(main.local_player_id), "warehouse", &"ration")
		warehouse.begin_partial_drag(ration["item"]["id"], 2)
		_check(root.gui_is_dragging(), "部分数量可启动真实 Godot 拖拽")
		var partial_data: Dictionary = root.gui_get_drag_data()
		_check(partial_data["quantity"] == 2, "拆分拖拽保存指定数量")
		_check(bag._can_drop_data(Vector2(122, 2), partial_data), "拆分落点使用容量和几何校验")
		bag._drop_data(Vector2(122, 2), partial_data)
		root.gui_cancel_drag()
		await process_frame
		var split_view: Dictionary = main.session.base_snapshot(main.local_player_id)
		_check(_find_entry(split_view, "warehouse", &"ration")["item"]["quantity"] == 2 and _find_entry(split_view, "backpack", &"ration")["item"]["quantity"] == 2, "实际拆分拖拽完成数量守恒")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.close_station"))
	main.session.submit(WildGameCommand.new(main.local_player_id, &"expedition.prepare"))
	_check(main.session.submit(WildGameCommand.new(main.local_player_id, &"expedition.commit")).successful, "真实组合根提交投放")
	await process_frame
	_check(not main.base_world.visible and not paused, "进入荒野关闭整备面板并恢复输入")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"survival.abandon" if main.session.base_snapshot(main.local_player_id).get("survival_enabled",false) else (&"expedition.return_exploration" if main.session.base_snapshot(main.local_player_id).get("exploration_only", false) else &"expedition.return_placeholder")))
	await process_frame
	_check(main.base_world.visible and main.session.flow.current_phase == WildRunFlow.Phase.BASE, "真实场景返回基地并恢复阶段")
	main.queue_free()
	await process_frame


func _service(memory: MemoryStore, spawn_check: Callable = Callable()) -> WildBaseService:
	var service := WildBaseService.new(CONFIG, CATALOG, memory.load_records, memory.save_record, spawn_check)
	_check(service.initialize("p").successful, "事务服务初始化")
	return service


func _move_data(state: WildBaseState, source: String, target: String, id: String, cell: Vector2i) -> Dictionary:
	return {"source": source, "target": target, "item_id": id, "source_version": state.containers[source].version, "target_version": state.containers[target].version, "x": cell.x, "y": cell.y, "rotated": false}


func _auto_transfer(service: WildBaseService, source: String, target: String, id: String) -> WildOperationResult:
	var view: Dictionary = service.snapshot()
	return service.submit(WildGameCommand.new("p", &"inventory.transfer", {"source": source, "target": target, "item_id": id, "source_version": view["containers"][source]["version"], "target_version": view["containers"][target]["version"], "auto": true}))


func _total_quantity(state: WildBaseState, id: StringName) -> int:
	var total: int = 0
	for container: WildInventoryContainer in state.containers.values():
		for entry: Dictionary in container.placements.values():
			if (entry["item"] as WildItemInstance).item_id == id:
				total += (entry["item"] as WildItemInstance).quantity
	return total


func _find_entry(view: Dictionary, container: String, definition: StringName) -> Dictionary:
	for entry: Dictionary in view["containers"][container]["entries"]:
		if entry["item"]["item_id"] == str(definition):
			return entry
	return {}


func _contents(view: Dictionary) -> String:
	var contents: Dictionary = {}
	for id: String in view["containers"]:
		contents[id] = view["containers"][id]["entries"]
	return JSON.stringify(contents, "", true)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
