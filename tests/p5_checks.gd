extends SceneTree
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const F = preload("res://tests/p5_fixtures.gd")
const PATHS = preload("res://tests/verification_paths.gd")
var passed: int = 0
var failed: int = 0
var saved: Dictionary = {}
var save_fail: bool = false

func _initialize() -> void:
	if not PATHS.arguments_are_isolated(): quit(1); return
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		push_error(label)

func near(value: float, expected: float, label: String, tolerance: float = 0.001) -> void:
	check(absf(value-expected)<tolerance,"%s %.5f vs %.5f" % [label,value,expected])

func _save(raw: Dictionary, _preserve: bool = false) -> WildOperationResult:
	if save_fail: return WildOperationResult.reject(&"SAVE_FAILED")
	saved = raw.duplicate(true)
	return WildOperationResult.accept()

func _load() -> WildOperationResult:
	return WildOperationResult.accept({"exists":not saved.is_empty(),"primary":saved.duplicate(true),"backup":{}})

func _run() -> void:
	_test_skills()
	print("P5 skills complete")
	_test_modifiers()
	print("P5 modifiers complete")
	_test_fishing()
	print("P5 fishing complete")
	_test_crafting_and_camp()
	print("P5 craft / camp complete")
	_test_traps()
	print("P5 traps complete")
	_test_transactions_and_saves()
	print("P5 transactions complete")
	_test_cooperative()
	_test_boundaries()
	_test_large_trap()
	print("P5 domain checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _test_skills() -> void:
	var state := WildBaseState.new("p",CONFIG)
	check(CONFIG.validate().is_empty(),"P5 configuration validates")
	for branch: String in WildSkillCatalog.BRANCHES:
		state.skills.experience[branch] = 600
		check(WildSkillRules.learn(state,{"branch":branch,"tier":2},CONFIG.skill_rules,false).code == &"SKILL_PREREQUISITE","ordered "+branch)
		for tier: int in range(1,4):
			check(WildSkillRules.learn(state,{"branch":branch,"tier":tier},CONFIG.skill_rules,false).successful,"learn %s %d" % [branch,tier])
		check(WildSkillRules.points(state.skills,branch,CONFIG.skill_rules) == 0 and state.skills.spent_points[branch] == 6,"point costs "+branch)
		check(WildSkillRules.learn(state,{"branch":branch,"tier":3},CONFIG.skill_rules,true).code == &"SKILL_ALREADY_LEARNED","already learned no fee "+branch)
	check(WildSkillCodec.decode(state.skills.record(),CONFIG.skill_rules) != null,"all 27 nodes persist")
	state = WildBaseState.new("p",CONFIG)
	state.skills.experience["gathering"] = 99
	check(WildSkillRules.points(state.skills,"gathering",CONFIG.skill_rules) == 0,"99 XP no point")
	state.skills.experience["gathering"] = 100
	check(WildSkillRules.points(state.skills,"gathering",CONFIG.skill_rules) == 1,"100 XP one point")
	check(WildSkillRules.learn(state,{"branch":"gathering","tier":1},CONFIG.skill_rules,true).successful,"base currency learning")
	check(state.currency == 300 and state.skills.experience["gathering"] == 100 and WildSkillRules.points(state.skills,"gathering",CONFIG.skill_rules) == 1,"money grants no XP or points and consumes no points")
	check(WildSkillRules.learn(state,{"branch":"gathering","tier":2},CONFIG.skill_rules,true).code == &"INSUFFICIENT_CURRENCY","tier two money cost")
	state.phase = WildRunFlow.Phase.WILDERNESS
	check(WildSkillRules.learn(state,{"branch":"fire","tier":1},CONFIG.skill_rules,true).code == &"BASE_LEARNING_ONLY","money learning base only")
	check(WildSkillRules.learn(state,{"branch":"hacked","tier":1},CONFIG.skill_rules,false).code == &"INVALID_SKILL","unknown branch")
	check(WildSkillRules.learn(state,{"branch":"fire","tier":1.5},CONFIG.skill_rules,false).code == &"INVALID_SKILL","fractional tier")
	var malformed: Dictionary = state.skills.record()
	malformed["spent_points"]["gathering"] = 5
	check(WildSkillCodec.decode(malformed,CONFIG.skill_rules) == null,"forged point balance rejected")
	malformed = state.skills.record()
	malformed["skills_version"] = 2
	check(WildSkillCodec.decode(malformed,CONFIG.skill_rules) == null,"future skill version rejected")

func _test_modifiers() -> void:
	var state: WildBaseState = F.create_state()
	var resource: Dictionary = F.at_resource(state,"root")
	state.skills.levels["gathering"] = 3
	check(F.start(state,{"action":"gather","resource_id":resource["id"],"version":resource["version"]}).successful,"skilled gathering")
	near(state.survival.actions["p"]["duration"],225,"gather duration 25 percent lower")
	F.finish(state)
	check(F.quantity(state,"root") == 4 and state.skills.experience["gathering"] == 4,"plant extra yield and experience")
	state = F.create_state()
	var axe_id: String = F.give(state,"axe")
	state.skills.levels["logging"] = 3
	resource = F.at_resource(state,"tree")
	check(F.start(state,{"action":"gather","resource_id":resource["id"],"version":resource["version"]}).successful,"skilled logging")
	near(state.survival.actions["p"]["duration"],765,"logging time modifier")
	F.finish(state)
	check(F.quantity(state,"wood") == 5 and state.skills.experience["logging"] == 8,"logging output and experience")
	near((WildInventoryOperations.find(state,axe_id)["item"] as WildItemInstance).durability,98.5,"fractional tool wear")
	state = F.create_state()
	state.skills.levels["fire"] = 3
	F.give(state,"wood",4)
	F.give(state,"stone",3)
	F.give(state,"flint")
	check(F.start(state,{"action":"build","recipe":"fire"}).successful,"skilled fire building")
	F.finish(state)
	var fire: Dictionary = state.survival.buildings.values()[0]
	near(fire["fuel_seconds"],18000,"initial fuel multiplier")
	check(F.start(state,{"action":"light","building_id":fire["id"]}).successful,"skilled ignition")
	near(state.survival.actions["p"]["duration"],150,"ignition duration half")
	F.finish(state)
	check(state.skills.experience["fire"] == 4,"effective ignition XP")
	fire["lit"] = false # 测试重燃同一份燃料，不是正式灭火 UI。
	check(F.start(state,{"action":"light","building_id":fire["id"]}).successful,"same fuel relight fixture")
	F.finish(state)
	check(state.skills.experience["fire"] == 4,"repeated relight cannot farm XP")
	check(F.start(state,{"action":"fuel","building_id":fire["id"]}).successful,"skilled add fuel")
	var before: float = fire["fuel_seconds"]
	F.finish(state)
	near(fire["fuel_seconds"],before-60+9000,"fuel addition multiplied and elapsed consumed")
	check(WildBaseStateCodec.decode(state.record(),"p",CONFIG,CATALOG) != null,"boosted fuel / skill restore")

func _test_fishing() -> void:
	var state: WildBaseState = F.create_state()
	var fish: Dictionary = F.at_resource(state,"fish")
	var payload: Dictionary = {"action":"fish","resource_id":fish["id"],"version":fish["version"],"bait":"fiber"}
	check(F.start(state,payload).code == &"MISSING_FISHING_KIT","fishing requires kit")
	F.give(state,"fishing_kit")
	check(F.start(state,payload).code == &"MISSING_MATERIALS","fishing requires actual bait")
	F.give(state,"fiber",4)
	payload["version"] = 99
	check(F.start(state,payload).code == &"STALE_VERSION" and F.quantity(state,"fiber") == 4,"stale fish no bait loss")
	payload["version"] = fish["version"]
	check(F.start(state,payload).successful and F.quantity(state,"fiber") == 3,"fishing consumes bait at start")
	WildSurvivalCommands.execute(state,WildGameCommand.new("p",&"survival.cancel"),CONFIG,CATALOG,CONTENT)
	check(F.quantity(state,"fiber") == 3 and state.skills.experience["fishing"] == 0,"cancel no bait refund or XP")
	state.survival.fishing_random_states["p"] = F.random_state_for(false,0.6)
	check(F.start(state,payload).successful,"failed outcome fishing starts")
	F.finish(state)
	check(fish["remaining"] == 6 and F.quantity(state,"raw_fish") == 0 and state.skills.experience["fishing"] == 0,"failed attempt no fish depletion or XP")
	state.skills.levels["fishing"] = 3
	state.survival.fishing_random_states["p"] = F.random_state_for(true,0.7,2)
	payload["double"] = true
	check(F.start(state,payload).successful,"double fishing unlock")
	near(state.survival.actions["p"]["duration"],1350,"fishing duration reduced")
	check(WildBaseStateCodec.decode(state.record(),"p",CONFIG,CATALOG) != null,"in flight fishing saves consumed bait and RNG")
	F.finish(state)
	check(fish["remaining"] == 4 and F.quantity(state,"raw_fish") == 2 and state.skills.experience["fishing"] == 8,"independent two successes and one completion reward")
	near((WildInventoryOperations.find(state,WildInventoryOperations.choose(state,&"fishing_kit"))["item"] as WildItemInstance).durability,98,"each completed fishing action wear")
	state.survival.elapsed_seconds = 43200
	WildProgressionWorld.tick(state,{},CONTENT,CONFIG)
	check(fish["remaining"] == 6 and state.survival.fish_refills[fish["id"]] == 86400,"12 hour replenishment +2 capped at six")
	var rng: String = state.survival.fishing_random_states["p"]
	var restored: WildBaseState = WildBaseStateCodec.decode(state.record(),"p",CONFIG,CATALOG)
	check(restored != null and restored.survival.fishing_random_states["p"] == rng,"fishing stream saved independently")

func _build(state: WildBaseState, recipe: String, site: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"action":"build","recipe":recipe}
	payload.merge(site)
	var result: WildOperationResult = F.start(state,payload)
	check(result.successful,"build "+recipe+" "+str(result.code))
	if not result.successful: return {}
	F.finish(state)
	for building: Dictionary in state.survival.buildings.values():
		if building["kind"] == recipe: return building
	return {}

func _test_crafting_and_camp() -> void:
	var state: WildBaseState = F.create_state()
	check(F.start(state,{"action":"craft","recipe":"bow"}).code == &"SKILL_REQUIRED","bow gated by hunting")
	F.give(state,"fiber",4)
	check(F.start(state,{"action":"craft","recipe":"rope"}).successful,"basic rope no skill")
	F.finish(state)
	check(F.quantity(state,"rope") == 1 and F.quantity(state,"fiber") == 0,"rope material conservation")
	state.skills.levels["hunting"] = 1
	F.give(state,"wood",3)
	check(F.start(state,{"action":"craft","recipe":"bow"}).successful,"bow production after learning")
	F.finish(state)
	check(F.quantity(state,"bow") == 1 and F.quantity(state,"rope") == 0,"bow craft consumes inputs")
	state = F.create_state()
	var site: Dictionary = F.open_site(state,Vector2i(4,4))
	check(not site.is_empty(),"camp expansion fixture")
	F.give(state,"wood",8)
	F.give(state,"fiber",6)
	var camp: Dictionary = _build(state,"camp",site)
	if camp.is_empty(): return
	check(F.start(state,{"action":"upgrade","building_id":camp["id"]}).code == &"SKILL_REQUIRED","camp two gated")
	state.skills.levels["building"] = 3
	F.give(state,"wood",12)
	F.give(state,"rope",2)
	F.give(state,"hide",2)
	check(F.start(state,{"action":"upgrade","building_id":camp["id"]}).successful,"camp upgrade two")
	check(camp["width"] == 2,"expansion only commits on completion")
	check(WildBaseStateCodec.decode(state.record(),"p",CONFIG,CATALOG) != null,"pending camp upgrade restores")
	F.finish(state)
	check(camp["level"] == 2 and camp["width"] == 3 and F.quantity(state,"wood") == 0,"camp two expands consumes")
	state.survival.bodies["p"].hp = 60
	check(F.start(state,{"action":"rest","building_id":camp["id"],"hours":1}).successful,"upgraded camp rest")
	F.finish(state)
	near(state.survival.bodies["p"].hp,63,"camp two health points recovery multiplier")
	F.give(state,"wood",18)
	F.give(state,"stone",6)
	F.give(state,"rope",3)
	F.give(state,"hide",3)
	check(F.start(state,{"action":"upgrade","building_id":camp["id"]}).successful,"camp upgrade three")
	F.finish(state)
	check(camp["level"] == 3 and camp["width"] == 4 and camp["investment"]["wood"] == 38,"camp three cumulative investment")
	check(F.start(state,{"action":"upgrade","building_id":camp["id"]}).code == &"CAMP_MAX_LEVEL","camp max level")
	check(F.start(state,{"action":"demolish","building_id":camp["id"]}).successful,"camp demolition")
	var xp: int = state.skills.experience["building"]
	F.finish(state)
	check(state.survival.buildings.is_empty() and F.quantity(state,"wood") == 19 and state.skills.experience["building"] == xp,"cumulative half refund no demolition XP")
	# 独立料理夹具：营地消耗与复杂材料不会影响食物效果验证。
	state = F.create_state()
	state.skills.levels["cooking"] = 3
	state.skills.levels["healing"] = 2
	F.give(state,"wood",2)
	F.give(state,"stone",3)
	F.give(state,"flint")
	var fire: Dictionary = _build(state,"fire")
	check(F.start(state,{"action":"light","building_id":fire["id"]}).successful,"cooking fire ignition")
	F.finish(state)
	F.give(state,"raw_fish")
	check(F.start(state,{"action":"craft","recipe":"cooked_fish"}).successful,"basic cooked fish")
	F.finish(state)
	var cooked: WildItemInstance = WildInventoryOperations.find(state,WildInventoryOperations.choose(state,&"cooked_fish"))["item"]
	near(cooked.nutrition_multiplier,1.15,"chef nutrition persisted on instance")
	near(cooked.shelf_life_multiplier,1.5,"chef shelf life persisted on instance")
	check(cooked.freshness_hours > 24 and cooked.valid(CATALOG.find(&"cooked_fish")),"boosted food valid beyond original shelf life")
	check(WildBaseStateCodec.decode(state.record(),"p",CONFIG,CATALOG) != null,"boosted cooked food restore")
	F.give(state,"herb",2)
	var bottle: WildItemInstance = WildInventoryOperations.find(state,F.give(state,"bottle"))["item"]
	check(F.start(state,{"action":"craft","recipe":"herbal_medicine"}).code == &"CLEAN_WATER_REQUIRED","medicine requires actual clean water")
	bottle.water_l = 0.5
	check(F.start(state,{"action":"craft","recipe":"herbal_medicine"}).successful,"herbal medicine recipe")
	check(WildBaseStateCodec.decode(state.record(),"p",CONFIG,CATALOG) != null,"water reservation pending craft restore")
	F.finish(state)
	near(bottle.water_l,0.25,"medicine consumes quarter litre")
	check(F.quantity(state,"herbal_medicine") == 1 and F.quantity(state,"herb") == 0 and state.skills.experience["healing"] == 0,"drug craft no ineffective healing XP")
	state.survival.bodies["p"].gastro_remaining_seconds = 43200
	check(F.start(state,{"action":"treat","item_id":WildInventoryOperations.choose(state,&"herbal_medicine")}).successful,"skilled medicinal treatment")
	F.finish(state)
	near(state.survival.bodies["p"].gastro_remaining_seconds,13800,"medical node two extra two hours")
	check(state.skills.experience["healing"] == 6,"effective medical XP")

func _test_traps() -> void:
	var state: WildBaseState = F.create_state()
	check(state.survival.prey.size() == 26,"26 actual passive prey entities")
	check(F.create_state().survival.prey == state.survival.prey,"independent prey stream reproducible")
	check(F.start(state,{"action":"build","recipe":"small_trap"}).code == &"SKILL_REQUIRED","small trap skill gate")
	state.skills.levels["trap"] = 1
	var animal: Dictionary = state.survival.prey.values()[0]
	var site: Dictionary = F.open_site(state,Vector2i.ONE,Vector2i(animal["x"],animal["y"]))
	check(not site.is_empty(),"trap habitat placement fixture")
	F.give(state,"fiber",4)
	F.give(state,"wood")
	var trap: Dictionary = _build(state,"small_trap",site)
	if trap.is_empty(): return
	check(F.start(state,{"action":"trap_collect","building_id":trap["id"]}).code == &"TRAP_EMPTY","empty trap cannot collect")
	F.give(state,"berry",3)
	check(F.start(state,{"action":"trap_bait","building_id":trap["id"],"quantity":3}).successful,"bait actual berries")
	F.finish(state)
	check(trap["bait"] == 3 and F.quantity(state,"berry") == 0,"bait conservation")
	trap["trap_random_state"] = F.random_state_for(true,0.4)
	F.time(state,CONTENT.small_trap_seconds-60)
	check(trap["capture"].is_empty(),"no early six hour capture")
	F.time(state,60)
	check(not trap["capture"].is_empty() and trap["bait"] == 2 and trap["uses_left"] == 2,"actual capture consumes bait and use")
	var prey_id: String = trap["capture"].get("prey_id","")
	check(not prey_id.is_empty() and not state.survival.prey[prey_id]["alive"],"caught actual prey removed from living population")
	check(WildBaseStateCodec.decode(state.record(),"p",CONFIG,CATALOG) != null,"occupied trap and dead prey restore")
	F.time(state,3600)
	check(F.start(state,{"action":"trap_collect","building_id":trap["id"]}).successful,"collect actual catch")
	F.finish(state)
	check(F.quantity(state,"raw_meat") == 1 and F.quantity(state,"hide") == 1 and state.skills.experience["trap"] == 8,"one loot set and collecting actor experience")
	check(F.start(state,{"action":"trap_collect","building_id":trap["id"]}).code == &"TRAP_EMPTY","repeat catch cannot duplicate")
	var meat: WildItemInstance = WildInventoryOperations.find(state,WildInventoryOperations.choose(state,&"raw_meat"))["item"]
	check(meat.freshness_hours < 11,"capture food aged before collection")
	F.give(state,"fiber",2)
	check(F.start(state,{"action":"trap_maintain","building_id":trap["id"]}).successful,"trap maintenance")
	F.finish(state)
	check(trap["uses_left"] == 3 and F.quantity(state,"fiber") == 0,"maintenance +1 cap three")
	check(F.start(state,{"action":"trap_maintain","building_id":trap["id"]}).code == &"TRAP_NOT_READY","full trap no maintenance")
	for prey: Dictionary in state.survival.prey.values(): prey["alive"] = false
	var bait_before: int = trap["bait"]
	var stream_before: String = trap["trap_random_state"]
	F.time(state,CONTENT.small_trap_seconds)
	check(trap["bait"] == bait_before and trap["trap_random_state"] == stream_before,"no prey no bait or random check")
	check(not WildProgressionActions.trap_limit(_five_trap_fixture(),CONTENT.maximum_traps,"p"),"five effective traps world cap")
	var capped: WildSurvivalState = _five_trap_fixture()
	capped.buildings["0"]["uses_left"] = 0
	capped.actions["other"] = {"type":"trap_maintain","building_id":"0"}
	check(not WildProgressionActions.trap_limit(capped,CONTENT.maximum_traps,"p"),"pending exhausted trap repair reserves final slot")
	check(WildProgressionActions.trap_limit(capped,CONTENT.maximum_traps,"other"),"repair completion excludes its own reservation")
	for index: int in range(5): state.survival.buildings["cap-%d" % index] = {"kind":"small_trap","uses_left":1}
	trap["uses_left"] = 0
	F.give(state,"fiber",2)
	check(F.start(state,{"action":"trap_maintain","building_id":trap["id"]}).code == &"TRAP_LIMIT" and F.quantity(state,"fiber") == 2,"sixth effective trap repair rejected without material loss")
	var repair: Dictionary = {"type":"trap_maintain","building_id":trap["id"],"fire_id":""}
	check(not WildProgressionActions.completion_valid(state,"p",repair,CONFIG,CONTENT),"repair cap rechecked at completion")

func _five_trap_fixture() -> WildSurvivalState:
	var run := WildSurvivalState.new()
	for index: int in range(5): run.buildings[str(index)] = {"kind":"small_trap","uses_left":1}
	return run

func _test_transactions_and_saves() -> void:
	var state: WildBaseState = F.create_state()
	var resource: Dictionary = F.at_resource(state,"branch")
	saved = state.record()
	var service := WildBaseService.new(CONFIG,CATALOG,_load,_save,Callable(),Callable(),CONTENT)
	check(service.initialize("p").successful,"P5 service restore")
	var command := WildGameCommand.new("p",&"survival.start",{"action":"gather","resource_id":resource["id"],"version":resource["version"]})
	check(service.submit(command).successful,"practice action starts")
	save_fail = true
	check(service.advance_world("p",2.5,"idle").code == &"SAVE_FAILED" and service.snapshot()["skills"]["experience"]["gathering"] == 0,"XP save failure rollback")
	save_fail = false
	check(service.advance_world("p",0,"idle").successful and service.snapshot()["skills"]["experience"]["gathering"] == 4,"XP completion retry commits once")
	check(service.submit(command).successful and service.snapshot()["skills"]["experience"]["gathering"] == 4,"request replay cannot duplicate XP")
	check(service.submit(WildGameCommand.new("p",&"survival.abandon")).successful,"abandon with earned growth")
	check(service.current_phase() == WildRunFlow.Phase.BASE and service.snapshot()["skills"]["experience"]["gathering"] == 4,"failure retains growth")
	var loaded := WildBaseService.new(CONFIG,CATALOG,_load,_save,Callable(),Callable(),CONTENT)
	check(loaded.initialize("p").successful and loaded.snapshot()["skills"]["experience"]["gathering"] == 4,"permanent XP survives restart")
	var train := WildGameCommand.new("p",&"skill.train",{"branch":"trap","tier":1})
	save_fail = true
	check(loaded.submit(train).code == &"SAVE_FAILED" and loaded.snapshot()["currency"] == 600,"learning write failure no money loss")
	save_fail = false
	check(loaded.submit(train).successful and loaded.submit(train).successful and loaded.snapshot()["currency"] == 300,"training retry and dedup charge once")
	var malformed: Dictionary = saved.duplicate(true)
	malformed["skills"]["experience"]["trap"] = -1
	check(WildBaseStateCodec.decode(malformed,"p",CONFIG,CATALOG) == null,"bad skills reject full save")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("skills")
	check(WildBaseStateCodec.decode(legacy,"p",CONFIG,CATALOG) != null,"legacy base save without skill fields")
	# 同配方四次完工最多三次经验，不需要通过拆建快速刷点。
	state = F.create_state()
	for index: int in range(4): WildProgressionActions.award_build(state,"p","camp",CONFIG.skill_rules)
	check(state.skills.experience["building"] == 24 and state.survival.build_experience_counts["p"]["camp"] == 3,"per recipe first three builds only")
	var path: String = PATHS.profile("p5-record").get_basename()+".json"
	var store := WildBaseStateStore.new(path)
	check(store.save_record(state.record()).successful,"P5 isolated JSON write")
	check(WildBaseStateCodec.decode(store.load_records().payload["primary"],"p",CONFIG,CATALOG) != null,"P5 isolated JSON restore")

func _command(coop: WildCoopService, actor: String, operation: String, payload: Dictionary = {}, id: String = "") -> WildOperationResult:
	return coop.submit(actor,{"room_id":coop.state.room_id,"run_id":coop.state.run_id,"request_id":id if not id.is_empty() else WildStableId.create("request"),"operation":operation,"payload":payload})

func _test_cooperative() -> void:
	var coop := WildCoopService.new(CONFIG,CATALOG,CONTENT,_save)
	check(coop.create("host","host","17","secret").successful and coop.join("guest","guest","").successful,"cooperative progression fixture")
	check(_command(coop,"host","room.start").successful,"cooperative start")
	coop.state.members["guest"].skills.experience["fishing"] = 100
	check(_command(coop,"guest","skill.unlock",{"branch":"fishing","tier":1},"learn-one").successful,"bound actor point learning")
	check(_command(coop,"guest","skill.unlock",{"branch":"fishing","tier":1},"learn-one").successful,"cooperative learning dedup")
	check(coop.state.members["guest"].skills.levels["fishing"] == 1 and coop.state.members["host"].skills.levels["fishing"] == 0,"skill ownership isolated")
	check(not _command(coop,"guest","skill.train",{"branch":"trap","tier":1}).successful,"cooperative prototype cannot spend permanent base money")
	var fish: Dictionary = {}
	for resource: Dictionary in coop.state.world.resources.values():
		if resource["kind"] == "fish": fish = resource; break
	for actor: String in ["host","guest"]: coop.state.world.players[actor] = coop.state.world.centre(Vector2i(fish["x"],fish["y"]))
	var payload: Dictionary = {"action":"fish","resource_id":fish["id"],"version":fish["version"],"bait":"fiber"}
	var guest_before: int = F.quantity(coop.state.members["guest"],"fiber")
	check(_command(coop,"host","survival.start",payload,"fish-lock").successful,"host reserves fish point")
	check(_command(coop,"guest","survival.start",payload).code == &"RESOURCE_RESERVED" and F.quantity(coop.state.members["guest"],"fiber") == guest_before,"fish race rollback includes immediate bait")
	coop.state.survival.fishing_random_states["host"] = F.random_state_for(true,0.6)
	WildSurvivalSimulation.queue_time(coop.state.survival,1800,"idle")
	coop._simulate(coop.state,true)
	check(F.quantity(coop.state.members["host"],"raw_fish") == 1 and F.quantity(coop.state.members["guest"],"raw_fish") == 0,"fishing output private")
	check(coop.state.members["host"].skills.experience["fishing"] == 8 and coop.state.members["guest"].skills.experience["fishing"] == 100,"experience executing actor only")
	var restored := WildCoopService.new(CONFIG,CATALOG,CONTENT,_save)
	check(restored.restore(coop.state.record(),"host").successful,"cooperative individual growth restore")
	check(restored.state.members["guest"].skills.record() == coop.state.members["guest"].skills.record(),"cooperative learned node and spent point restore")

func _test_boundaries() -> void:
	var state: WildBaseState = F.create_state()
	var axe: WildItemInstance = WildInventoryOperations.find(state,F.give(state,"axe"))["item"]
	axe.durability = 1.5
	state.skills.levels["logging"] = 3
	var tree: Dictionary = F.at_resource(state,"tree")
	check(F.start(state,{"action":"gather","resource_id":tree["id"],"version":tree["version"]}).successful,"reduced wear permits last fractional tool use")
	F.finish(state)
	near(axe.durability,0,"fractional worn tool ends at zero")
	state = F.create_state()
	state.skills.levels["cooking"] = 3
	state.skills.levels["building"] = 2
	F.give(state,"wood",8)
	F.give(state,"stone",7)
	F.give(state,"rope")
	F.give(state,"flint")
	var large_site: Dictionary = F.open_site(state,Vector2i(4,4))
	var fire: Dictionary = _build(state,"fire",large_site)
	check(F.start(state,{"action":"light","building_id":fire["id"]}).successful,"stew fire")
	F.finish(state)
	var table_site: Dictionary = {"x":large_site["x"]+1,"y":large_site["y"]}
	var table: Dictionary = _build(state,"cooking_table",table_site)
	check(not table.is_empty(),"cooking table actual built footprint")
	var empty_bottle: WildItemInstance = WildInventoryOperations.find(state,F.give(state,"bottle"))["item"]
	var extra_bottle := WildItemInstance.new(CATALOG.find(&"bottle"))
	extra_bottle.water_l = 0.5
	check(WildInventoryOperations.insert(state,CATALOG,CONFIG,extra_bottle),"second full clean water bottle fixture")
	F.give(state,"root")
	F.give(state,"berry")
	F.give(state,"raw_meat")
	check(F.start(state,{"action":"craft","recipe":"stew"}).successful,"stew chooses meat alternative and usable second bottle")
	check(WildBaseStateCodec.decode(state.record(),"p",CONFIG,CATALOG) != null,"pending stew input alternatives restore")
	F.finish(state)
	near(empty_bottle.water_l,0,"empty bottle remains untouched")
	near(extra_bottle.water_l,0.25,"stew quarter litre consumed from usable bottle")
	check(F.quantity(state,"stew") == 1 and F.quantity(state,"raw_meat") == 0 and state.skills.experience["cooking"] == 4,"stew all inputs consumed and effective XP")
	var stew: WildItemInstance = WildInventoryOperations.find(state,WildInventoryOperations.choose(state,&"stew"))["item"]
	near(stew.nutrition_multiplier,1.15,"stew chef bonus persists")
	var ordinary := WildItemInstance.new(CATALOG.find(&"stew"))
	check(WildInventoryOperations.insert(state,CATALOG,CONFIG,ordinary),"different food quality fits separate stack")
	check(ordinary.quantity == 1 and F.quantity(state,"stew") == 2,"food quality not silently merged or downgraded")
	var backpack: WildInventoryContainer = state.containers["backpack"]
	var merged: WildOperationResult = WildInventoryRules.transfer(state,CATALOG,CONFIG,"p",{"source":"backpack","target":"backpack","source_version":backpack.version,"target_version":backpack.version,"item_id":ordinary.instance_id,"x":backpack.placements[stew.instance_id]["position"].x,"y":backpack.placements[stew.instance_id]["position"].y})
	check(merged.code == &"DIFFERENT_FOOD_QUALITY" and stew.nutrition_multiplier == 1.15 and stew.quantity == 1,"explicit mismatched quality merge rejected without mutation")
	F.give(state,"raw_fish")
	var raw: WildItemInstance = WildInventoryOperations.find(state,WildInventoryOperations.choose(state,&"raw_fish"))["item"]
	raw.freshness_hours = 0
	check(F.start(state,{"action":"craft","recipe":"cooked_fish"}).code == &"MISSING_MATERIALS","spoiled input cannot be cooked fresh")
	state = F.create_state()
	state.skills.levels["building"] = 1
	var site: Dictionary = F.open_site(state,Vector2i(4,4))
	F.give(state,"wood",8)
	F.give(state,"fiber",6)
	var camp: Dictionary = _build(state,"camp",site)
	F.give(state,"wood",12)
	F.give(state,"rope",2)
	F.give(state,"hide",2)
	check(F.start(state,{"action":"upgrade","building_id":camp["id"]}).successful,"expansion before dynamic obstruction")
	var resource: Dictionary = state.world.resources.values()[0]
	var original_x: int = int(resource["x"])
	var original_y: int = int(resource["y"])
	resource["x"] = camp["x"]+2
	resource["y"] = camp["y"]
	F.finish(state)
	check(camp["level"] == 1 and F.quantity(state,"wood") == 12 and F.quantity(state,"rope") == 2,"late obstructed expansion fails without material consumption")
	resource["x"] = original_x
	resource["y"] = original_y
	var malformed: Dictionary = state.record()
	malformed["active_run"]["survival"]["progression"]["version"] = 2
	check(WildBaseStateCodec.decode(malformed,"p",CONFIG,CATALOG) == null and WildSaveVersions.future(malformed),"future world schema refused")
	saved = WildBaseState.new("p",CONFIG).record()
	saved["skills"]["skills_version"] = 2
	var primary_before: Dictionary = saved.duplicate(true)
	var future_loader: Callable = func() -> WildOperationResult: return WildOperationResult.accept({"exists":true,"primary":primary_before.duplicate(true),"backup":WildBaseState.new("p",CONFIG).record()})
	var service := WildBaseService.new(CONFIG,CATALOG,future_loader,_save)
	check(service.initialize("p").code == &"INVALID_SAVE" and saved == primary_before,"future skill primary not overwritten")
	var coop := WildCoopService.new(CONFIG,CATALOG,CONTENT,_save)
	check(coop.create("host","host","17","secret").successful,"lobby learning fixture")
	check(_command(coop,"host","skill.train",{"branch":"trap","tier":1},"lobby-training").successful,"cooperative lobby validation money learning")
	check(coop.state.members["host"].currency == 300 and coop.state.members["host"].skills.levels["trap"] == 1 and coop.state.members["host"].skills.experience["trap"] == 0,"lobby learning no XP subsidy")
	check(_command(coop,"host","skill.train",{"branch":"trap","tier":1},"lobby-training").successful and coop.state.members["host"].currency == 300,"lobby learning dedup")

func _test_large_trap() -> void:
	var state: WildBaseState = F.create_state()
	state.skills.levels["trap"] = 2
	var animal: Dictionary = {}
	for prey: Dictionary in state.survival.prey.values():
		if prey["kind"] == "boar": animal = prey; break
	var site: Dictionary = F.open_site(state,Vector2i(2,2),Vector2i(animal["x"],animal["y"]))
	check(not site.is_empty(),"large trap habitat fixture")
	F.give(state,"wood",4)
	F.give(state,"rope",2)
	F.give(state,"stone",2)
	var trap: Dictionary = _build(state,"large_trap",site)
	F.give(state,"berry",2)
	check(F.start(state,{"action":"trap_bait","building_id":trap["id"],"quantity":1}).successful,"large trap actual bait")
	F.finish(state)
	trap["trap_random_state"] = F.random_state_for(false,0.35)
	F.time(state,28800)
	check(trap["capture"].is_empty() and trap["bait"] == 0 and trap["uses_left"] == 3,"failed large trap consumes bait without use or loot")
	state.skills.levels["trap"] = 3
	check(F.start(state,{"action":"trap_bait","building_id":trap["id"],"quantity":1}).successful,"rebait empty large trap")
	F.finish(state)
	trap["trap_random_state"] = F.random_state_for(true,0.5)
	F.time(state,28800)
	check(trap["capture"].get("kind","") == "boar" and trap["uses_left"] == 2,"large trap catches actual boar")
	near(trap["probability_bonus"],0.15,"new skill applies to already placed trap")
	check(WildBaseStateCodec.decode(state.record(),"p",CONFIG,CATALOG) != null,"large trap restore")
	var bad: Dictionary = state.record()
	bad["active_run"]["survival"]["buildings"][trap["id"]]["capture"]["kind"] = "rabbit"
	check(WildBaseStateCodec.decode(bad,"p",CONFIG,CATALOG) == null,"capture species mismatch rejected")
	check(F.start(state,{"action":"trap_collect","building_id":trap["id"]}).successful,"large prey collection")
	F.finish(state)
	check(F.quantity(state,"raw_meat") == 3 and F.quantity(state,"hide") == 2 and state.skills.experience["trap"] == 8,"boar loot 3 meat 2 hide with one effective XP reward")
