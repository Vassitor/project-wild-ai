extends SceneTree
const VERIFICATION = preload("res://tests/verification_paths.gd")
## P3 守恒、时间 / 跳时、动作失败、存档与结算验证。全部使用隔离工作区档案。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var _generator := WildWorldGenerator.new(CONFIG)
var _world_record: Dictionary
var _checks: int = 0
var _failures := PackedStringArray()

class MemoryStore extends RefCounted:
	var primary: Dictionary = {}
	var backup: Dictionary = {}
	var fail: bool = false
	func load_records() -> WildOperationResult:
		return WildOperationResult.accept({"exists":not primary.is_empty(),"primary":primary.duplicate(true),"backup":backup.duplicate(true)})
	func save_record(data: Dictionary,preserve_backup: bool = false) -> WildOperationResult:
		if fail: return WildOperationResult.reject(&"SAVE_FAILED")
		if not preserve_backup: backup = primary.duplicate(true)
		primary = data.duplicate(true)
		return WildOperationResult.accept()

func _initialize() -> void:
	if not VERIFICATION.arguments_are_isolated():
		push_error("Tests require workspace verification paths")
		quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	_world_record = _generator.generate("17").payload["world"]
	_world_record["players"] = {"p":[(float(_world_record["spawn"][0])+0.5)*32,(float(_world_record["spawn"][1])+0.5)*32]}
	_test_body()
	_test_actions()
	_test_fire_and_sleep()
	_test_outputs_and_settlement()
	_test_transactions_and_files()
	_test_journeys()
	await _test_scene()
	for failure: String in _failures: push_error(failure)
	print("P3 checks: %d passed, %d failed" % [_checks-_failures.size(),_failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _fixture() -> WildBaseState:
	var state := WildBaseState.new("p",CONFIG)
	state.phase = WildRunFlow.Phase.WILDERNESS
	state.world = WildWorldCodec.decode(_world_record,CONFIG)
	state.survival = WildSurvivalSimulation.create("p","17")
	state.active_run = {"run_id":WildStableId.create("run"),"seed":"17","origin_containers":WildBaseState.new("p",CONFIG).record()["containers"]}
	return state

func _give(state: WildBaseState,kind: StringName,quantity: int = 1) -> String:
	var id: String = ""
	var definition: WildItemDefinition = CATALOG.find(kind)
	while quantity > 0:
		var amount: int = mini(quantity,definition.max_stack)
		var item := WildItemInstance.new(definition,amount)
		WildInventoryOperations.insert(state,CATALOG,CONFIG,item)
		id = WildInventoryOperations.choose(state,kind)
		quantity -= amount
	return id

func _resource(state: WildBaseState,kind: String) -> Dictionary:
	for entry: Dictionary in state.world.resources.values():
		if entry["kind"] == kind and entry["remaining"] > 0: return entry
	return {}

func _at_resource(state: WildBaseState,kind: String) -> Dictionary:
	var resource: Dictionary = _resource(state,kind)
	state.world.players["p"] = state.world.centre(Vector2i(resource["x"],resource["y"]))
	return resource

func _start(state: WildBaseState,payload: Dictionary) -> WildOperationResult:
	return WildSurvivalActions.start(state,"p",payload,CONFIG,CATALOG,CONTENT)

func _time(state: WildBaseState,seconds: float,activity: String = "idle") -> Dictionary:
	WildSurvivalSimulation.queue_time(state.survival,seconds,activity)
	return WildSurvivalSimulation.process(state,CONFIG,CATALOG,CONTENT,true)

func _test_body() -> void:
	var state: WildBaseState = _fixture()
	_time(state,3600)
	var body: WildBodyState = state.survival.bodies["p"]
	_check(is_equal_approx(body.water,96),"一游戏小时消耗水分4")
	_check(is_equal_approx(body.nutrition[0],96) and is_equal_approx(body.nutrition[2],98),"基础营养按小时消耗")
	_check(is_equal_approx(state.survival.elapsed_seconds,3600),"累计时间不以跨午夜算日期")
	var ration_id: String = _give(state,&"ration")
	var before: float = body.nutrition[0]
	_check(_start(state,{"action":"eat","item_id":ration_id}).successful,"选择食物创建有耗时的行动")
	_time(state,60)
	_check(WildInventoryOperations.find(state,ration_id).is_empty(),"进食完成只消耗一份")
	_check(not body.digestion.is_empty() and body.nutrition[0] < before,"食物不是瞬间全量补充")
	_time(state,600)
	_check(body.digestion.is_empty() and body.nutrition[0] <= 100,"十分钟消化封顶且丢弃溢出")
	body.stamina = 0
	_time(state,60,"walk")
	_check(body.stamina > 0,"零体力移动仍恢复")
	body.stamina = 100
	_time(state,60,"sprint")
	_check(is_equal_approx(body.stamina,96),"冲刺每游戏分钟消耗4体力")
	var hungry: WildBaseState = _fixture()
	hungry.survival.bodies["p"].nutrition[0] = 0
	hungry.survival.bodies["p"].nutrition[1] = 0
	_time(hungry,3600)
	_check(hungry.survival.bodies["p"].hp == 100,"饥饿危险有累计宽限")
	_time(hungry,7200)
	_check(hungry.survival.bodies["p"].hp < 100,"长期碳水脂肪耗尽造成基础伤害")
	var dry: WildBaseState = _fixture()
	dry.survival.bodies["p"].water = 0
	_time(dry,3600)
	_check(is_equal_approx(dry.survival.bodies["p"].hp,94),"脱水每小时伤害6")
	_time(dry,36*3600)
	_check(dry.survival.outcome == "lost","无补给可走完死亡路线")
	var quarter: WildBaseState = _fixture()
	var full: WildBaseState = quarter.copy(CONFIG)
	for index: int in range(240): _time(quarter,15,"walk")
	_time(full,3600,"walk")
	_check(quarter.survival.bodies["p"].water == full.survival.bodies["p"].water or is_equal_approx(quarter.survival.bodies["p"].water,full.survival.bodies["p"].water),"时间拆分保持同活动身体消耗一致")

func _test_actions() -> void:
	var state: WildBaseState = _fixture()
	_check(WildSurvivalActions.start(state,"outsider",{"action":"drink"},CONFIG,CATALOG,CONTENT).code == &"UNKNOWN_ACTOR","未知角色不能执行生存动作")
	var dry_land := WildWorldData.new()
	dry_land.size = Vector2i(3,3)
	dry_land.tiles.resize(9)
	dry_land.tiles.fill(WildWorldData.Terrain.GRASS)
	dry_land.blocked_cells[Vector2i(1,1)] = true
	_check(not dry_land.has_water_neighbor(Vector2i(0,1)),"建筑阻挡不能被当成岸边水源")
	var resource: Dictionary = _at_resource(state,"branch")
	var body: WildBodyState = state.survival.bodies["p"]
	_check(_start(state,{"action":"gather","resource_id":resource["id"],"version":99}).code == &"STALE_VERSION" and body.stamina == 100,"旧资源请求不扣体力")
	_check(_start(state,{"action":"gather","resource_id":resource["id"],"version":0}).successful,"落枝可空手采集")
	_check(body.stamina == 98 and _quantity(state,&"wood") == 0,"行动开始扣体力但尚无产出")
	_check(_start(state,{"action":"gather","resource_id":resource["id"],"version":0}).code == &"ACTION_BUSY","禁止重入动作")
	_time(state,240)
	_check(_quantity(state,&"wood") == 0,"动作耗时未满不产出")
	_time(state,60)
	_check(_quantity(state,&"wood") == 1 and resource["remaining"] == 0,"动作完成消耗资源并交付一次")
	_check(state.survival.actions.is_empty(),"完成释放动作锁")
	var tree: Dictionary = _at_resource(state,"tree")
	_check(_start(state,{"action":"gather","resource_id":tree["id"],"version":0}).code == &"MISSING_TOOL","伐木需要可用工具")
	var knife: String = _give(state,&"knife")
	_check(_start(state,{"action":"gather","resource_id":tree["id"],"version":0}).successful,"小刀伐木路线可用")
	_time(state,2700)
	_check(_quantity(state,&"wood") == 3 and (WildInventoryOperations.find(state,knife)["item"] as WildItemInstance).durability == 95,"小刀45分钟产木2并磨损5")
	var berry: Dictionary = _at_resource(state,"berry")
	body.stamina = 0
	_check(_start(state,{"action":"gather","resource_id":berry["id"],"version":0}).code == &"NOT_ENOUGH_STAMINA","体力不足劳动失败不耗资源")
	body.stamina = 100
	_start(state,{"action":"gather","resource_id":berry["id"],"version":0})
	_time(state,300)
	_check(_quantity(state,&"berry") == 3 and berry.has("regrow_at"),"采摘产三份并记录再生时刻")
	var ready: float = berry["regrow_at"]
	# 保持身体有补给的边界夹具，专门验证资源世界时钟，不用死亡阻断再生。
	state.survival.elapsed_seconds = ready - 60
	_time(state,60)
	_check(berry["remaining"] == 1 and berry["version"] == 2,"浆果24小时恢复且更新版本")
	var spring: Dictionary = _at_resource(state,"spring")
	body.water = 40
	_start(state,{"action":"drink","resource_id":spring["id"],"version":0,"litres":0.5})
	_time(state,60)
	_check(body.water > 64 and spring["remaining"] == 1,"无容器清泉饮水有效且不耗尽泉水")
	var bottle_id: String = _give(state,&"bottle")
	_start(state,{"action":"fill","resource_id":spring["id"],"version":0,"item_id":bottle_id,"litres":0.5})
	_time(state,60)
	var bottle: WildItemInstance = WildInventoryOperations.find(state,bottle_id)["item"]
	_check(bottle.water_l == 0.5 and is_equal_approx(bottle.weight(CATALOG.find(&"bottle")),0.75),"取水增加重量而不增加外部体积")
	_start(state,{"action":"drink","item_id":bottle_id,"litres":0.25})
	_time(state,60)
	_check(bottle.water_l == 0.25,"允许按0.25L饮用并扣实际水量")
	_check(_start(state,{"action":"fill","resource_id":spring["id"],"version":0,"item_id":bottle_id,"litres":1}).code == &"BOTTLE_FULL","容量不足不开始取水")

func _test_fire_and_sleep() -> void:
	var state: WildBaseState = _fixture()
	_give(state,&"wood",10)
	_give(state,&"fiber",6)
	_give(state,&"stone",3)
	_give(state,&"flint")
	_check(_start(state,{"action":"build","recipe":"camp"}).successful,"可在相邻空地建营地")
	_check(_quantity(state,&"wood") == 10,"建造开始仅锁定材料")
	_time(state,3600)
	_check(_quantity(state,&"wood") == 2 and _quantity(state,&"fiber") == 0,"营地完成才耗材料")
	_check(state.survival.buildings.size() == 1,"营地实体与占地记录")
	_check(not state.world.blocked_cells.is_empty(),"建筑占位加入权威通行规则")
	_check(_start(state,{"action":"build","recipe":"fire"}).successful,"剩余木材和石材可建火堆")
	_time(state,600)
	var fire_id: String = WildBuildingRules.nearby(state,"p","fire")
	_check(not fire_id.is_empty(),"火堆建在可交互位置")
	_give(state,&"root")
	_check(_start(state,{"action":"cook"}).code == &"FIRE_NOT_LIT" or _start(state,{"action":"cook"}).code == &"MISSING_FIRE","料理需要燃烧火堆")
	_check(_start(state,{"action":"light","building_id":fire_id}).successful,"打火石取火有时间和工具费用")
	_time(state,300)
	_check(state.survival.buildings[fire_id]["lit"],"取火完成点燃实际火源")
	_check(_start(state,{"action":"cook"}).successful,"烤根茎可开始")
	_time(state,600)
	_check(_quantity(state,&"root") == 0 and _quantity(state,&"roasted_root") == 1,"料理消耗原料并生成食物")
	var bottle_id: String = _give(state,&"bottle")
	var bottle: WildItemInstance = WildInventoryOperations.find(state,bottle_id)["item"]
	bottle.water_l = 0.5
	bottle.clean_water = false
	_check(_start(state,{"action":"boil","item_id":bottle_id}).successful,"生水可在燃烧火堆煮净")
	_time(state,300)
	_check(bottle.clean_water and bottle.water_l == 0.5,"煮水不凭空增加水量")
	var copy: WildBaseState = state.copy(CONFIG)
	_check(_start(state,{"action":"sleep","hours":1}).successful,"靠近营地可睡眠")
	_check(_start(copy,{"action":"sleep","hours":1}).successful,"实时睡眠对照动作")
	WildSurvivalSimulation.sleep(state,"p",CONFIG,CATALOG,CONTENT)
	for index: int in range(60): _time(copy,60,"sleep")
	_check(is_equal_approx(state.survival.bodies["p"].water,copy.survival.bodies["p"].water),"跳时与分钟推进水分一致")
	_check(is_equal_approx(state.survival.bodies["p"].nutrition[2],copy.survival.bodies["p"].nutrition[2]),"跳时与分钟推进营养一致")
	_check(is_equal_approx(state.survival.buildings[fire_id]["fuel_seconds"],copy.survival.buildings[fire_id]["fuel_seconds"]),"跳时不会冻结燃料")
	_check(_quantity(state,&"roasted_root") == _quantity(copy,&"roasted_root"),"跳时不复制食物")
	var body: WildBodyState = state.survival.bodies["p"]
	body.water = 21
	_start(state,{"action":"sleep","hours":8})
	var elapsed: float = state.survival.elapsed_seconds
	WildSurvivalSimulation.sleep(state,"p",CONFIG,CATALOG,CONTENT)
	_check(state.survival.elapsed_seconds - elapsed <= 1860 and state.survival.actions.is_empty(),"水分危急提前醒来而非跳过8小时")
	_check(body.water <= 20 and body.hp > 0,"危险跳时中断给玩家恢复机会")
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(state.record()))
	_check(WildBaseStateCodec.decode(encoded,"p",CONFIG,CATALOG) != null,"身体 / 建筑 / 燃料 / 腐坏实际JSON可恢复")
	var raw_id: String = _give(state,&"root")
	(WildInventoryOperations.find(state,raw_id)["item"] as WildItemInstance).freshness_hours = 0.01
	var cooked_before: int = _quantity(state,&"roasted_root")
	_start(state,{"action":"cook"})
	_time(state,300)
	var mid_action: WildBaseState = WildBaseStateCodec.decode(JSON.parse_string(JSON.stringify(state.record())),"p",CONFIG,CATALOG)
	_check(mid_action != null and mid_action.survival.actions.has("p"),"运行中料理与材料锁可读档，即使原料刚腐坏")
	_time(state,300)
	_check(_quantity(state,&"root") == 1 and _quantity(state,&"roasted_root") == cooked_before,"腐坏料理失败不消耗原料、不恢复新鲜")
	(WildInventoryOperations.find(state,raw_id)["item"] as WildItemInstance).freshness_hours = 72
	state.survival.buildings[fire_id]["fuel_seconds"] = 120
	_start(state,{"action":"cook"})
	_time(state,120)
	_check(state.survival.actions.is_empty() and _quantity(state,&"root") == 1,"火熄灭立即中断料理且保留原料")

func _test_outputs_and_settlement() -> void:
	var state: WildBaseState = _fixture()
	# 容量夹具故意缩小背包，用于验证产出无法入包仍可领取。
	state.containers["backpack"].grid_size = Vector2i(1,1)
	_give(state,&"bandage")
	var resource: Dictionary = _at_resource(state,"branch")
	_start(state,{"action":"gather","resource_id":resource["id"],"version":0})
	_time(state,300)
	_check(_quantity(state,&"wood") == 0 and state.survival.outputs.size() == 1,"满包产出留在原工作点")
	state.containers["backpack"].grid_size = CONFIG.backpack_grid
	var output_id: String = state.survival.outputs.keys()[0]
	var claim := WildGameCommand.new("p",&"survival.claim_output",{"id":output_id})
	_check(WildSurvivalCommands.execute(state,claim,CONFIG,CATALOG,CONTENT).successful and _quantity(state,&"wood") == 1,"空出空间后领取原产出")
	_check(state.survival.outputs.is_empty(),"领取后不能再复制产出")
	state.survival.elapsed_seconds = CONFIG.target_survival_hours*3600-60
	_time(state,60)
	_check(state.survival.outcome == "won","累计168小时才胜利")
	var balance: int = state.currency
	_check(WildSettlementRules.settle(state,CONFIG,CATALOG),"胜利事务返航")
	_check(state.phase == WildRunFlow.Phase.BASE and state.survival == null,"结算后回基地并清理运行中世界")
	_check(state.currency >= balance+600 and state.containers["backpack"].placements.is_empty(),"基础奖励600且随身物资转回仓库")
	var awarded: int = state.currency
	_check(not WildSettlementRules.settle(state,CONFIG,CATALOG) and state.currency == awarded,"重复结算不重复发奖")
	var lost: WildBaseState = _fixture()
	_give(lost,&"ration")
	var retained := WildItemInstance.new(CATALOG.find(&"axe"))
	lost.containers["warehouse"].placements[retained.instance_id] = {"item":retained,"position":Vector2i.ZERO,"rotated":false}
	lost.survival.bodies["p"].hp = 0.001
	lost.survival.bodies["p"].water = 0
	lost.survival.elapsed_seconds = CONFIG.target_survival_hours*3600-60
	_time(lost,60)
	_check(lost.survival.outcome == "lost","同刻死亡优先于胜利")
	WildSettlementRules.settle(lost,CONFIG,CATALOG)
	_check(lost.currency == 600 and _quantity(lost,&"ration") == 0 and lost.containers["warehouse"].placements.has(retained.instance_id),"失败丢随身、保留基地货币与仓库")
	var full: WildBaseState = _fixture()
	full.containers["warehouse"].capacity_l = 0.01
	_give(full,&"knife")
	full.survival.outcome = "won"
	WildSettlementRules.settle(full,CONFIG,CATALOG)
	_check(full.pending.size() == 1,"满仓返航进入持久待领取而非丢弃")
	full.containers["warehouse"].capacity_l = CONFIG.warehouse_capacity_l
	_check(WildSurvivalCommands.claim_pending(full,CONFIG,CATALOG).successful and full.pending.is_empty(),"返航待领取物资必须入仓后可使用")

func _test_transactions_and_files() -> void:
	var state: WildBaseState = _fixture()
	var resource: Dictionary = _at_resource(state,"branch")
	var memory := MemoryStore.new()
	memory.primary = state.record()
	var service := WildBaseService.new(CONFIG,CATALOG,memory.load_records,memory.save_record,Callable(),_generator.generate,CONTENT)
	_check(service.initialize("p").successful,"生存事务读入完整世界与身体")
	var command := WildGameCommand.new("p",&"survival.start",{"action":"gather","resource_id":resource["id"],"version":0})
	_check(service.submit(command).successful,"行动开始关键点保存")
	_check(service.submit(command).successful and service.body_snapshot("p")["stamina"] == 98,"重发开始不重复扣体力")
	var position: Vector2 = service.player_position("p")
	_check(service.move_player("p",Vector2.RIGHT,0.1,false) == position,"执行中不能离开工作点")
	_check(service.submit(WildGameCommand.new("p",&"inventory.transfer",{})).code == &"ACTION_BUSY","执行中库存材料锁不能被整理绕过")
	service.advance_world("p",2.0,"idle")
	_check(_snapshot_quantity(service.snapshot(),&"wood") == 0,"耗时未满仍无产出")
	memory.fail = true
	_check(service.advance_world("p",0.5,"idle").code == &"SAVE_FAILED","完成点保存失败不提交物资")
	_check(_snapshot_quantity(service.snapshot(),&"wood") == 0 and service.survival_snapshot("p")["save_blocked"],"失败冻结模拟，产出保持未提交")
	memory.fail = false
	_check(service.advance_world("p",0,"idle").successful and _snapshot_quantity(service.snapshot(),&"wood") == 1,"保存恢复后完成一次产出")
	var file_path: String = "res://.godot/verification/p3_state_%s.json" % WildStableId.create("test")
	var store := WildBaseStateStore.new(file_path)
	_check(store.save_record(memory.primary).successful,"完整运行状态写真实文件")
	var restart := WildBaseService.new(CONFIG,CATALOG,store.load_records,store.save_record,Callable(),_generator.generate,CONTENT)
	_check(restart.initialize("p").successful,"真实档案恢复时间和身体")
	_check(restart.survival_snapshot("p")["elapsed_seconds"] == service.survival_snapshot("p")["elapsed_seconds"],"读档不重置计时")
	_check(is_equal_approx(restart.body_snapshot("p")["hydration"],service.body_snapshot("p")["hydration"]),"读档不重置水分")
	var malformed: Dictionary = memory.primary.duplicate(true)
	malformed["active_run"]["survival"]["bodies"]["p"]["stamina"] = -1
	_check(WildBaseStateCodec.decode(malformed,"p",CONFIG,CATALOG) == null,"拒绝坏身体档案而非补满")
	var cancel_state: WildBaseState = _fixture()
	var point: Dictionary = _at_resource(cancel_state,"branch")
	_start(cancel_state,{"action":"gather","resource_id":point["id"],"version":0})
	_time(cancel_state,120)
	WildSurvivalCommands.execute(cancel_state,WildGameCommand.new("p",&"survival.cancel"),CONFIG,CATALOG,CONTENT)
	_check(cancel_state.survival.actions.is_empty() and point["remaining"] == 1 and _quantity(cancel_state,&"wood") == 0,"取消动作释放材料且不生成产出")
	_check(cancel_state.survival.elapsed_seconds == 120 and cancel_state.survival.bodies["p"].stamina == 98,"取消不退时间和体力")
	var nearing: WildBaseState = _fixture()
	_give(nearing,&"knife")
	nearing.survival.elapsed_seconds = CONFIG.target_survival_hours*3600-60
	var settlement_memory := MemoryStore.new()
	settlement_memory.primary = nearing.record()
	var settlement := WildBaseService.new(CONFIG,CATALOG,settlement_memory.load_records,settlement_memory.save_record,Callable(),_generator.generate,CONTENT)
	settlement.initialize("p")
	settlement_memory.fail = true
	_check(settlement.advance_world("p",0.5,"idle").code == &"SAVE_FAILED" and settlement.snapshot()["currency"] == 600,"结算写盘失败不发奖、不转移物资")
	settlement_memory.fail = false
	settlement.advance_world("p",0,"idle")
	var reward_balance: int = settlement.snapshot()["currency"]
	_check(reward_balance >= 1200 and settlement.current_phase() == WildRunFlow.Phase.BASE,"结算保存恢复后提交一次")
	settlement.advance_world("p",0,"idle")
	_check(settlement.snapshot()["currency"] == reward_balance,"重复推进结算不重复发钱")
	var resumed_settlement := WildBaseService.new(CONFIG,CATALOG,settlement_memory.load_records,settlement_memory.save_record,Callable(),_generator.generate,CONTENT)
	_check(resumed_settlement.initialize("p").successful and resumed_settlement.snapshot()["currency"] == reward_balance,"重开保留结算收据和奖励")
	var critical: WildBaseState = _fixture()
	critical.survival.bodies["p"].hp = 0.001
	critical.survival.bodies["p"].water = 0
	var critical_memory := MemoryStore.new()
	critical_memory.primary = critical.record()
	var critical_service := WildBaseService.new(CONFIG,CATALOG,critical_memory.load_records,critical_memory.save_record,Callable(),_generator.generate,CONTENT)
	critical_service.initialize("p")
	critical_service.advance_world("p",0.25,"idle")
	critical_service.submit(WildGameCommand.new("p",&"inventory.transfer",{}))
	_check(critical_service.current_phase() == WildRunFlow.Phase.BASE and WildBaseStateCodec.decode(critical_memory.primary,"p",CONFIG,CATALOG) != null,"操作前不足一分钟的死亡也保存有效失败结算")

func _test_journeys() -> void:
	for seed_text: String in ["17","18","7936","15855","31693"]:
		var journey := WildP3Journey.new()
		var state: WildBaseState = journey.run(seed_text)
		_check(state != null and journey.failure.is_empty(),"7日策略种子 %s 执行完整动作：%s" % [seed_text,journey.failure])
		if state == null: continue
		_check(state.survival.outcome == "won" and is_equal_approx(state.survival.elapsed_seconds,168*3600),"种子 %s 无改数值走满168小时成功" % seed_text)
		_check(state.survival.activities.get("p",[]).has("cooking") and state.survival.activities.get("p",[]).has("building"),"种子 %s 包含采集、建造、取火、料理与睡眠" % seed_text)
		var body: WildBodyState = state.survival.bodies["p"]
		print("P3 journey seed %s: %s, %.1fh, HP %.1f, hydration %.1f" % [seed_text,state.survival.outcome,state.survival.elapsed_seconds/3600,body.hp,body.water])
		if state.survival.outcome == "won":
			WildSettlementRules.settle(state,CONFIG,CATALOG)
			_check(state.currency >= 600 and state.phase == WildRunFlow.Phase.BASE,"种子 %s 奖励与返仓闭环" % seed_text)
			if seed_text == "17": WildBaseStateStore.new("res://.godot/verification/p3-journey-victory.json").save_record(state.record())

func _test_scene() -> void:
	var main: WildMain = MAIN.instantiate() as WildMain
	main._profile_path = "res://.godot/verification/p3_ui_%s.cfg" % WildStableId.create("ui")
	root.add_child(main)
	main.session.set_focus_lost(false)
	main.session.submit(WildGameCommand.new(main.local_player_id,&"expedition.prepare",{"seed":"17"}))
	main.session.submit(WildGameCommand.new(main.local_player_id,&"expedition.commit"))
	await process_frame
	_check(main.session.base_snapshot(main.local_player_id)["survival_enabled"],"真实主场景出发启用生存而非探索返还")
	main.wilderness_world.request_interaction()
	await process_frame
	_check(main.survival_panel.visible and paused,"E打开实际行动选择且暂停单机")
	var before: float = main.session.survival_snapshot(main.local_player_id)["elapsed_seconds"]
	main.session.advance_world(main.local_player_id,10,"idle")
	_check(main.session.survival_snapshot(main.local_player_id)["elapsed_seconds"] == before,"单机面板不推进模拟或免费生产")
	var gather_button: Button
	for child: Node in main.survival_panel.find_children("*","Button",true,false):
		if child.text.begins_with("采集"): gather_button = child
	_check(gather_button != null,"资源面板有实际采集按钮")
	if gather_button != null:
		gather_button.pressed.emit()
		await process_frame
		_check(not paused and not main.session.survival_snapshot(main.local_player_id)["action"].is_empty(),"按钮开始动作并关闭菜单恢复计时")
		main.session.advance_world(main.local_player_id,2.5,"idle")
		_check(not main.session.base_snapshot(main.local_player_id)["containers"]["backpack"]["entries"].is_empty(),"真实UI动作经过会话产出并保存")
	main.session.submit(WildGameCommand.new(main.local_player_id,&"survival.abandon"))
	await process_frame
	_check(main.base_world.visible and main.session.base_snapshot(main.local_player_id)["last_settlement"]["won"] == false,"放弃按失败结算并显示结果")
	main.session.submit(WildGameCommand.new(main.local_player_id,&"base.close_station"))
	main.queue_free()
	await process_frame

func _quantity(state: WildBaseState,kind: StringName) -> int:
	var quantity: int = 0
	for container: WildInventoryContainer in state.containers.values():
		if not container.carried: continue
		for entry: Dictionary in container.placements.values():
			var item: WildItemInstance = entry["item"]
			if item.item_id == kind: quantity += item.quantity
	return quantity

func _snapshot_quantity(view: Dictionary,kind: StringName) -> int:
	var count: int = 0
	for slot: String in ["backpack","main_hand","off_hand","armor"]:
		for entry: Dictionary in view["containers"][slot]["entries"]:
			if entry["item"]["item_id"] == str(kind): count += int(entry["item"]["quantity"])
	return count

func _check(condition: bool,label: String) -> void:
	_checks += 1
	if not condition: _failures.append(label)
