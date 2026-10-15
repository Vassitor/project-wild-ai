extends SceneTree
## P7 使用真实领域动作的控制实验；预置位置 / 公共火源，明确不测寻路追猎耗时。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const F = preload("res://tests/p5_fixtures.gd")
const COMBAT = preload("res://tests/p6_fixtures.gd")
const PATHS = preload("res://tests/verification_paths.gd")
var passed: int = 0
var failed: int = 0
var metrics: Dictionary = {}
var disk: Dictionary = {}
var fail_save: bool = false
var fire_site: Dictionary = {}
var fire_point: Vector2

func _initialize() -> void:
	if not PATHS.arguments_are_isolated(): quit(1); return
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		push_error(label)

func _save(raw: Dictionary, _backup: bool = false) -> WildOperationResult:
	if fail_save: return WildOperationResult.reject(&"SAVE_FAILED")
	disk = raw.duplicate(true)
	return WildOperationResult.accept()

func _load() -> WildOperationResult:
	return WildOperationResult.accept({"exists":not disk.is_empty(),"primary":disk.duplicate(true),"backup":{}})

func _run() -> void:
	var original: PackedByteArray = var_to_bytes([CONTENT.foods,CONTENT.recipes,CONTENT.advanced_recipes])
	_reports()
	_boundaries()
	_economy()
	_routes()
	check(original == var_to_bytes([CONTENT.foods,CONTENT.recipes,CONTENT.advanced_recipes]),"read-only content preserved")
	var output := FileAccess.open("res://.godot/verification/p7-routes.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(metrics,"\t"))
	output.close()
	print("P7 integration checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _reports() -> void:
	var state: WildBaseState = F.create_state()
	F.give(state,"ration",2)
	state.survival.mark_activity("p","gathering")
	state.survival.mark_activity("p","gathering")
	state.survival.mark_activity("p","fishing")
	WildSurvivalSimulation.explore(state,"p")
	state.survival.outcome = "won"
	check(WildSettlementRules.settle(state,CONFIG,CATALOG),"single report committed with settlement")
	var report: Dictionary = state.last_settlement["report"]
	check(report["activity"] == 20 and report["base"] == 600 and report["returned_units"] == 2,"activity deduplicated and carried quantities counted")
	check(WildExpeditionReport.valid(report,state.last_settlement["reward"],true),"report matches actual reward")
	var money: int = state.currency
	check(not WildSettlementRules.settle(state,CONFIG,CATALOG) and state.currency == money,"report display cannot reissue reward")
	var raw: Dictionary = JSON.parse_string(JSON.stringify(state.record()))
	check(WildBaseStateCodec.decode(raw,"p",CONFIG,CATALOG) != null,"new result JSON roundtrip")
	raw["last_settlement"].erase("report")
	check(WildBaseStateCodec.decode(raw,"p",CONFIG,CATALOG) != null,"legacy result remains readable without invented detail")
	raw["last_settlement"]["report"] = report.duplicate(true)
	raw["last_settlement"]["report"]["base"] += 1
	check(WildBaseStateCodec.decode(raw,"p",CONFIG,CATALOG) == null,"inconsistent new result rejected")
	var profiles: Dictionary = {}
	var service := WildFullCoopService.new(CONFIG,CATALOG,CONTENT,func(_raw: Dictionary,_backup: bool) -> WildOperationResult: return WildOperationResult.accept())
	check(service.create("p0","host","17","secret").successful and service.join("p1","guest","").successful,"isolated two player result fixture")
	for actor: String in ["p0","p1"]:
		var personal := WildBaseState.new(actor,CONFIG)
		profiles[actor] = personal
		F.give(personal,"ration",2)
		var lease: WildOperationResult = WildCoopProfileRules.execute(personal,"coop.reserve",{"room_id":service.state.room_id,"run_id":service.state.run_id},CONFIG,CATALOG)
		check(WildCoopLifecycle.offer(service.state,actor,{"manifest":lease.payload["manifest"]},CONFIG,CATALOG).successful,"personal result lease accepted")
		service.state.lifecycle["ready"][actor] = true
	check(WildCoopLifecycle.start(service.state,service.online,CONFIG).successful,"two player loading")
	service.state.lifecycle["phase"] = "running"
	service.state.survival.mark_activity("p0","hunting")
	service.state.survival.bodies["p1"].hp = 0
	service.state.survival.outcome = "won"
	WildCoopLifecycle.reconcile(service.state,CONFIG,CATALOG)
	for actor: String in profiles:
		var summary: Dictionary = {}
		for event: Dictionary in WildCoopDeliveries.pending(service.state,actor):
			check(WildCoopProfileRules.apply_event(profiles[actor],event,CONFIG,CATALOG).successful,"apply real per-player event "+event["kind"])
			if event["kind"] == "settlement": summary = event
		check(not summary.is_empty() and summary["report"]["returned_units"] == (2 if actor == "p0" else 0),"survivor only reports returned carry")
		var balance: int = profiles[actor].currency
		check(WildCoopProfileRules.apply_event(profiles[actor],summary,CONFIG,CATALOG).successful and profiles[actor].currency == balance,"cooperative report replay cannot pay twice")
		check(WildBaseStateCodec.decode(profiles[actor].record(),actor,CONFIG,CATALOG) != null,"cooperative result profile roundtrip")
	check(profiles["p0"].last_settlement["report"]["activity"] == 10 and profiles["p1"].last_settlement["reward"] == 0,"personal activities / dead no reward")
	check(service.state.corpses["corpse:p1"].placements.size() == 1,"dead carry stays in corpse, never returned twice")

func _boundaries() -> void:
	for offset: float in [30,600]:
		var state: WildBaseState = F.create_state()
		F.give(state,"fiber",4)
		state.survival.elapsed_seconds = CONFIG.target_survival_hours*3600-offset
		check(F.start(state,{"action":"craft","recipe":"rope"}).successful,"long action near target starts")
		F.time(state,600)
		check(state.survival.outcome == "won" and F.quantity(state,"rope") == 0 and F.quantity(state,"fiber") == 4,"at / across target cancels output before consumption")
		check(WildSettlementRules.settle(state,CONFIG,CATALOG) and state.last_settlement["report"]["returned_units"] == 4,"unfinished materials return with carry")
	var dead: WildBaseState = F.create_state()
	dead.survival.elapsed_seconds = CONFIG.target_survival_hours*3600-60
	dead.survival.bodies["p"].hp = 0.001
	dead.survival.bodies["p"].water = 0
	F.time(dead,60)
	check(dead.survival.outcome == "lost","death takes priority at target")
	check(WildSettlementRules.settle(dead,CONFIG,CATALOG) and dead.last_settlement["reward"] == 0,"death result cannot include win reward")
	var state: WildBaseState = F.create_state()
	F.give(state,"ration",4)
	state.survival.elapsed_seconds = CONFIG.target_survival_hours*3600-60
	for id: String in state.survival.fish_refills: state.survival.fish_refills[id] = state.survival.elapsed_seconds+CONTENT.fish_refill_seconds
	disk = state.record()
	var service := WildBaseService.new(CONFIG,CATALOG,_load,_save,Callable(),Callable(),CONTENT)
	var initialized: WildOperationResult = service.initialize("p")
	check(initialized.successful,"settlement transaction fixture: "+str(initialized.code))
	if not initialized.successful: return
	fail_save = true
	check(service.advance_world("p",0.5,"idle").code == &"SAVE_FAILED" and service.snapshot()["last_settlement"].is_empty(),"failed save exposes neither reward nor report")
	fail_save = false
	check(service.advance_world("p",0,"idle").successful and service.snapshot()["last_settlement"].has("report"),"retry commits reward and report together")
	var restored := WildBaseService.new(CONFIG,CATALOG,_load,_save,Callable(),Callable(),CONTENT)
	check(restored.initialize("p").successful and restored.snapshot()["currency"] == service.snapshot()["currency"],"scene reentry does not settle twice")
	var overflow: WildBaseState = F.create_state()
	F.give(overflow,"ration",4)
	# 以每格 1 打火石填满合法 12×10 仓库；不能伪造容量或重叠几何来逃过恢复校验。
	for y: int in range(CONFIG.warehouse_grid.y):
		for x: int in range(CONFIG.warehouse_grid.x):
			var item := WildItemInstance.new(CATALOG.find(&"flint"))
			overflow.containers["warehouse"].placements[item.instance_id] = {"item":item,"position":Vector2i(x,y),"rotated":false}
	overflow.survival.outcome = "won"
	WildSettlementRules.settle(overflow,CONFIG,CATALOG)
	check(overflow.pending.size() == 1 and overflow.last_settlement["report"]["returned_units"] == 4,"full warehouse persists actual returned stacks")
	check(WildBaseStateCodec.decode(overflow.record(),"p",CONFIG,CATALOG) != null,"full warehouse / pending report restore together")

func _economy() -> void:
	fail_save = false
	disk = WildBaseState.new("p",CONFIG).record()
	disk["currency"] = 0
	var generator := WildWorldGenerator.new(CONFIG)
	var service := WildBaseService.new(CONFIG,CATALOG,_load,_save,func() -> bool: return true,generator.generate,CONTENT)
	check(service.initialize("p").successful,"zero currency base fixture")
	check(service.submit(WildGameCommand.new("p",&"supply.claim")).successful,"zero currency free supply available")
	for entry: Dictionary in service.snapshot()["containers"]["warehouse"]["entries"]:
		var view: Dictionary = service.snapshot()
		check(service.submit(WildGameCommand.new("p",&"inventory.transfer",{"source":"warehouse","target":"backpack","item_id":entry["item"]["id"],"quantity":1,"auto":true,"source_version":view["containers"]["warehouse"]["version"],"target_version":view["containers"]["backpack"]["version"]})).successful,"free supply can actually be packed")
	check(service.submit(WildGameCommand.new("p",&"expedition.prepare",{"seed":"17"})).successful and service.submit(WildGameCommand.new("p",&"expedition.commit")).successful,"zero currency / zero permanent skills can enter survival")
	var beginner: WildBaseState = service._state
	# 本节验证经济 / 技能门槛；预先移除测试世界的威胁，寻路和生存难度另由正常七日验证覆盖。
	for animal: Dictionary in beginner.survival.prey.values():
		animal["alive"] = false
		animal["hp"] = 0.0
		animal["loot_claimed"] = true
		animal["mode"] = "dead"
		animal["target"] = ""
	var resource: Dictionary = F.at_resource(beginner,"branch")
	check(F.start(beginner,{"action":"gather","resource_id":resource["id"],"version":resource["version"]}).successful,"free loadout gathers wood without skill gate")
	F.finish(beginner)
	check(F.quantity(beginner,"wood") > 0,"zero money start produces useful materials")
	for kind: String in ["branch","fiber","stone"]:
		var output: String = "wood" if kind == "branch" else kind
		var required: int = {"wood":10,"fiber":6,"stone":3}[output]
		while F.quantity(beginner,output)<required:
			var point: Dictionary = F.at_resource(beginner,kind)
			if not _action(beginner,{"action":"gather","resource_id":point["id"],"version":point["version"]}): break
	var site: Dictionary = F.open_site(beginner,Vector2i(2,2))
	check(not site.is_empty() and _action(beginner,{"action":"build","recipe":"camp","x":site["x"],"y":site["y"]}),"zero currency path builds actual camp without learned skill")
	var fire: Dictionary = F.open_site(beginner,Vector2i.ONE)
	check(not fire.is_empty() and _action(beginner,{"action":"build","recipe":"fire","x":fire["x"],"y":fire["y"]}),"zero currency path builds actual fire")
	check(_action(beginner,{"action":"light"}),"free flint lights fire without permanent training")
	var options: Dictionary = {"supplies":{"ration":17,"bandage":2},"fishing":{"fishing_kit":1,"ration":10,"bandage":2},"training":{"ration":7,"bandage":2}}
	metrics["loadouts"] = {}
	for option: String in options:
		var cost: int = CONFIG.skill_rules.training_costs[0] if option == "training" else 0
		for kind: String in options[option]: cost += CATALOG.find(StringName(kind)).price*int(options[option][kind])
		check(cost <= CONFIG.starting_currency,"viable first expedition spending: "+option)
		var packed := WildBaseState.new("p",CONFIG)
		for kind: String in ["knife","flint","bottle"]: F.give(packed,kind)
		for kind: String in options[option]: F.give(packed,kind,int(options[option][kind]))
		check(packed.carried_weight(CATALOG,CONFIG)<=CONFIG.soft_weight_limit_kg,"beginner loadout stays light: "+option)
		metrics["loadouts"][option] = {"cost":cost,"remaining_currency":CONFIG.starting_currency-cost,"packed_weight_kg":packed.carried_weight(CATALOG,CONFIG),"packed_volume_l":packed.containers["backpack"].volume(CATALOG)}
	check(CONFIG.success_base_reward >= 590 and CONFIG.skill_rules.training_costs[0] == 300,"success replenishes tested consumable loadout / learning remains optional")

func _fire(state: WildBaseState) -> void:
	if fire_site.is_empty():
		fire_site = F.open_site(state,Vector2i.ONE)
		fire_point = state.world.players["p"]
	state.world.players["p"] = fire_point
	state.survival.buildings["fixture-fire"] = {"id":"fixture-fire","kind":"fire","x":fire_site["x"],"y":fire_site["y"],"width":1,"height":1,"lit":true,"fuel_seconds":CONTENT.fire_initial_seconds,"level":1}

func _action(state: WildBaseState, data: Dictionary) -> bool:
	var start: WildOperationResult = F.start(state,data)
	if not start.successful:
		check(false,"route action "+str(data)+": "+str(start.code))
		return false
	F.finish(state)
	return true

func _routes() -> void:
	for route: String in ["gathering","fishing","hunting"]:
		var minutes: float = 0
		var water_cost: float = 0
		var attempts: int = 0
		var successes: int = 0
		# 植物产出与近战命中夹具为确定性；只对随机捕鱼做 100 条独立随机流采样。
		var samples: int = 100 if route == "fishing" else 1
		for sample: int in range(samples):
			var state: WildBaseState = COMBAT.create() if route == "hunting" else F.create_state()
			var body: WildBodyState = state.survival.bodies["p"]
			body.nutrition = [50.0,50.0,50.0,50.0,50.0]
			var cooked: String = ""
			if route == "gathering":
				var root: Dictionary = F.at_resource(state,"root")
				if not _action(state,{"action":"gather","resource_id":root["id"],"version":root["version"]}): continue
				cooked = "roasted_root"
				attempts += 1
			elif route == "fishing":
				F.give(state,"fishing_kit")
				F.give(state,"fiber",20)
				state.survival.fishing_random_states["p"] = str(WildWorldGenerator._stream(str(sample),"p7-fishing").state)
				var fish: Dictionary = F.at_resource(state,"fish")
				var local_attempts: int = 0
				while F.quantity(state,"raw_fish") == 0 and local_attempts < 20:
					attempts += 1
					local_attempts += 1
					if not _action(state,{"action":"fish","bait":"fiber","resource_id":fish["id"],"version":fish["version"]}): break
				if F.quantity(state,"raw_fish") == 0: continue
				cooked = "cooked_fish"
			else:
				var animal: Dictionary = COMBAT.focus(state)
				COMBAT.equip(state,"knife")
				check(COMBAT.attack(state).successful,"unskilled knife attack")
				F.time(state,float(CONFIG.combat_rules.weapons["knife"]["cooldown"])*CONFIG.game_seconds_per_real_second)
				# 重新贴近真实移动的兔；本实验不把夹具定位冒充追猎与寻路时间。
				state.world.players["p"] = WildCombatWorld.position(animal,state.world)-Vector2(20,0)
				check(COMBAT.attack(state).successful and not animal["alive"],"unskilled actual rabbit death / loot")
				cooked = "cooked_meat"
				attempts += 1
			_fire(state)
			if not _action(state,{"action":"cook"} if route == "gathering" else {"action":"craft","recipe":cooked}): continue
			if not _action(state,{"action":"eat","item_id":WildInventoryOperations.choose(state,StringName(cooked))}): continue
			F.time(state,CONTENT.digestion_seconds)
			check(body.pollution == 0 and body.hp > 0 and body.digestion.is_empty(),"safe prepared meal actually digested: "+route)
			var index: int = 0 if route == "gathering" else 2
			check(body.nutrition[index] > 65,"meal supplies useful nutrition without skill: "+route)
			minutes += state.survival.elapsed_seconds/60
			water_cost += 100-body.water
			successes += 1
		check(successes == samples,"all controlled meals complete: "+route)
		metrics[route] = {"samples":samples,"successes":successes,"attempts":attempts,"average_minutes_to_digested_meal":minutes/maxi(1,successes),"average_water_cost":water_cost/maxi(1,successes),"nutrition_per_meal":CONTENT.foods[{"gathering":"roasted_root","fishing":"cooked_fish","hunting":"cooked_meat"}[route]],"scope":"Prepared fire and reachable targets; excludes travel, pursuit, fuel procurement; fishing bait pre-stocked."}
		print("P7 route "+route+": "+JSON.stringify(metrics[route]))
