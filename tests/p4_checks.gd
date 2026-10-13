extends SceneTree
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const FIXTURE = preload("res://tests/p4_fixtures.gd")
const PATHS = preload("res://tests/verification_paths.gd")
var passed: int = 0
var failed: int = 0
var world: Dictionary
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

func near(value: float, expected: float, label: String, tolerance: float = 0.0001) -> void:
	check(absf(value-expected)<tolerance,"%s: %.6f vs %.6f" % [label,value,expected])

func fresh_body() -> WildBodyState:
	var body := WildBodyState.new()
	WildIllnessRules.seed_body(body,"17","p")
	return body

func fixture() -> WildBaseState:
	return FIXTURE.create_state(CONFIG,"p",world)

func time(state: WildBaseState, seconds: float, activity: String = "idle") -> void:
	WildSurvivalSimulation.queue_time(state.survival,seconds,activity)
	WildSurvivalSimulation.process(state,CONFIG,CATALOG,CONTENT,true)

func start(state: WildBaseState, item: WildItemInstance) -> WildOperationResult:
	return WildSurvivalActions.start(state,"p",{"action":"treat","item_id":item.instance_id},CONFIG,CATALOG,CONTENT)

func _save(raw: Dictionary, _preserve: bool = false) -> WildOperationResult:
	if save_fail: return WildOperationResult.reject(&"SAVE_FAILED")
	saved = raw.duplicate(true)
	return WildOperationResult.accept()

func _load() -> WildOperationResult:
	return WildOperationResult.accept({"exists":not saved.is_empty(),"primary":saved.duplicate(true),"backup":{}})

func _run() -> void:
	world = WildWorldGenerator.new(CONFIG).generate("17").payload["world"]
	check(CONFIG.validate().is_empty(),"valid P4 config")
	print("P4 config valid")
	var invalid := WildGameConfig.new()
	invalid.health_rules.pollution_check_seconds = 0
	check(not invalid.validate().is_empty(),"reject zero illness interval")
	_test_shortages()
	print("P4 shortages complete")
	_test_illness()
	print("P4 illness complete")
	_test_food_and_recovery()
	print("P4 foods complete")
	_test_armor_and_sleep()
	print("P4 armor complete")
	_test_medical_and_codec()
	print("P4 medical complete")
	_test_transactions_and_coop()
	print("P4 domain checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _test_shortages() -> void:
	var body: WildBodyState = fresh_body()
	body.nutrition[4] = 19
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	near(body.health,99,"one shortage health loss")
	body.nutrition[4] = 25
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	near(body.health,98,"hysteresis persists in 20 to 30")
	body.nutrition[4] = 31
	WildBodyRules.advance(body,CONFIG,CONTENT,60,"idle",0)
	check(not body.shortages[4],"shortage clears at 30")
	body = fresh_body()
	body.nutrition.fill(19)
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	near(body.health,96,"five shortages capped at four")
	body = fresh_body()
	body.water = 19
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	near(body.health,98,"dehydration health deducted once")
	check(body.dehydrated,"dehydrated active")
	body.water = 25
	WildBodyRules.advance(body,CONFIG,CONTENT,60,"idle",0)
	check(body.dehydrated,"dehydration hysteresis")
	WildBodyRules.drink(body,CONFIG,0.25,true)
	check(not body.dehydrated,"drink clears at 30")
	body = fresh_body()
	body.water = 2
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	near(body.hp,97,"water-zero damage only final half hour")
	body = fresh_body()
	body.nutrition[0] = 0
	body.nutrition[1] = 0
	WildBodyRules.advance(body,CONFIG,CONTENT,7200,"idle",0)
	near(body.hp,100,"no retrospective starvation damage at delay")
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	near(body.hp,97,"starvation after two hours")
	body.nutrition[0] = 25
	WildBodyRules.advance(body,CONFIG,CONTENT,60,"idle",0)
	check(body.starvation_seconds == 0,"starvation resets when fuel restored")
	body.nutrition[0] = 0
	body.nutrition[1] = 0
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	body.nutrition[0] = 15
	WildBodyRules.advance(body,CONFIG,CONTENT,60,"idle",0)
	check(body.starvation_seconds == 0,"before onset two hours must be continuous")

func _test_illness() -> void:
	var config: WildGameConfig = CONFIG.duplicate(true)
	config.nutrition_consumption_per_hour = PackedFloat32Array([0,0,0,0,0])
	config.water_consumption_per_hour = 0
	var body: WildBodyState = fresh_body()
	body.nutrition[4] = 19
	WildBodyRules.advance(body,config,CONTENT,86340,"idle",0)
	check(not body.weakness,"no weakness before 24h")
	WildBodyRules.advance(body,config,CONTENT,60,"idle",0)
	check(body.weakness,"24h low nutrient weakness")
	near(WildIllnessRules.movement_multiplier(body,config.health_rules),0.85,"weakness speed")
	body.nutrition.fill(31)
	WildBodyRules.advance(body,config,CONTENT,10800,"idle",0)
	near(body.weakness_recovery_seconds,10800,"three hours recovery progress")
	body.nutrition[0] = 29
	WildBodyRules.advance(body,config,CONTENT,60,"idle",0)
	check(body.weakness_recovery_seconds == 0,"low nutrient resets recovery")
	body.nutrition.fill(31)
	WildBodyRules.advance(body,config,CONTENT,21600,"idle",0)
	check(not body.weakness,"six continuous hours clears weakness")
	body = fresh_body()
	body.nutrition[0] = 19
	WildBodyRules.advance(body,config,CONTENT,43200,"idle",0)
	body.nutrition[0] = 50
	body.nutrition[1] = 19
	WildBodyRules.advance(body,config,CONTENT,43200,"idle",0)
	check(not body.weakness,"rotating nutrients do not combine timers")
	body = fresh_body()
	body.gastro_remaining_seconds = 43200
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	near(body.water,94,"gastro extra water two per hour")
	near(body.health,98,"gastro health two per hour")
	near(body.gastro_remaining_seconds,39600,"gastro course ticks")
	body.gastro_remaining_seconds = 1800
	body.water = 100
	body.health = 100
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	near(body.water,95,"course expiry separates water rates")
	near(body.health,99,"course expiry separates health loss")
	body = fresh_body()
	body.bleeding = true
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	near(body.hp,96,"bleeding hp per hour")
	near(body.health,99,"bleeding health per hour")
	body = fresh_body()
	body.pollution = 100
	var before: String = body.health_random_state
	WildBodyRules.advance(body,CONFIG,CONTENT,3599,"idle",0)
	check(body.health_random_state == before,"no random checks before hourly boundary")
	var copy: WildBodyState = body.copy()
	WildBodyRules.advance(body,CONFIG,CONTENT,1,"idle",0)
	WildBodyRules.advance(copy,CONFIG,CONTENT,1,"idle",0)
	check(body.record() == copy.record() and body.health_random_state != before,"saved random stream deterministic boundary")
	var other: WildBodyState = fresh_body()
	WildIllnessRules.seed_body(other,"17","guest")
	check(other.health_random_state != fresh_body().health_random_state,"personal actor random streams")
	body = fresh_body()
	body.pollution = 49
	before = body.health_random_state
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	check(body.health_random_state == before,"below risk threshold no draw")
	var sick_count: int = 0
	for index: int in range(1000):
		var trial: WildBodyState = fresh_body()
		WildIllnessRules.seed_body(trial,str(index),"pollution")
		trial.pollution = 100
		WildIllnessRules.check_pollution(trial,CONFIG.health_rules)
		if trial.gastro_remaining_seconds > 0:
			sick_count += 1
			if trial.pollution != 0 or trial.gastro_remaining_seconds != 43200: check(false,"onset resets pollution and starts twelve hours"); break
	check(sick_count > 500 and sick_count < 700,"pollution onset sampled at expected 60 percent")
	body = fresh_body()
	body.health = 0
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"idle",0)
	check(body.hp == 100 and body.gastro_remaining_seconds == 0,"zero health no direct death or fourth random illness")

func _test_food_and_recovery() -> void:
	var berry: WildBodyState = fresh_body()
	berry.nutrition.fill(40)
	var ration: WildBodyState = berry.copy()
	WildBodyRules.eat(berry,CONTENT,WildItemInstance.new(CATALOG.find(&"berry")))
	WildBodyRules.eat(ration,CONTENT,WildItemInstance.new(CATALOG.find(&"ration")))
	WildBodyRules.advance(berry,CONFIG,CONTENT,600,"idle",0)
	WildBodyRules.advance(ration,CONFIG,CONTENT,600,"idle",0)
	check(ration.nutrition[0] > berry.nutrition[0] and berry.nutrition[4] > ration.nutrition[4],"distinct foods distinct trajectories")
	var raw := WildItemInstance.new(CATALOG.find(&"raw_fish"))
	raw.freshness_hours = 0
	var body: WildBodyState = fresh_body()
	body.nutrition.fill(0)
	WildBodyRules.eat(body,CONTENT,raw)
	near(body.pollution,40,"raw and spoiled pollution counted once")
	WildBodyRules.advance(body,CONFIG,CONTENT,600,"idle",0)
	near(body.nutrition[2],11-2.0/6,"spoiled nutrition half")
	WildBodyRules.drink(body,CONFIG,0.5,false)
	near(body.pollution,40-5.0/6+25,"dirty water risk")
	body = fresh_body()
	body.stamina = 0
	body.water = 20
	body.health = 30
	near(WildBodyRules.recovery_factor(body,CONFIG),0.5,"water health recovery limit")
	body.weakness = true
	near(WildBodyRules.recovery_factor(body,CONFIG),0.35,"weakness recovery multiplier")
	body.nutrition[0] = 0
	near(WildBodyRules.recovery_factor(body,CONFIG),0.175,"minimum recovery then weakness")
	body = fresh_body()
	body.stamina = 100
	WildBodyRules.advance(body,CONFIG,CONTENT,60,"sprint",1)
	near(body.stamina,93,"heavy sprint fee")
	body.stamina = 25
	WildBodyRules.advance(body,CONFIG,CONTENT,60,"work",0)
	near(body.stamina,25,"work no duplicate continuous fee or recovery")
	body.hp = 0
	WildBodyRules.advance(body,CONFIG,CONTENT,3600,"rest",0)
	check(body.hp == 0,"dead body cannot rest revive")
	var normal: WildBodyState = fresh_body()
	normal.hp = 70
	normal.bleeding = true
	normal.gastro_remaining_seconds = 7500
	normal.pollution = 100
	var jumped: WildBodyState = normal.copy()
	for index: int in range(120): WildBodyRules.advance(normal,CONFIG,CONTENT,60,"sleep",0)
	WildBodyRules.advance(jumped,CONFIG,CONTENT,7200,"sleep",0)
	check(normal.record() == jumped.record(),"ordinary minutes identical to sleep-sized batch")
	var rested: WildBodyState = fresh_body()
	rested.hp = 70
	rested.health = 50
	var weak_rest: WildBodyState = rested.copy()
	weak_rest.weakness = true
	WildBodyRules.advance(rested,CONFIG,CONTENT,3600,"rest",0)
	WildBodyRules.advance(weak_rest,CONFIG,CONTENT,3600,"rest",0)
	near(rested.health,50.5,"safe camp health recovery")
	near(weak_rest.hp-70,(rested.hp-70)*0.7,"weakness reduces HP recovery")

func _test_armor_and_sleep() -> void:
	var state: WildBaseState = fixture()
	var armor := WildItemInstance.new(CATALOG.find(&"leather_armor"))
	state.containers["armor"].placements[armor.instance_id] = {"item":armor,"position":Vector2i.ZERO,"rotated":false}
	var initial: float = armor.durability
	var result: WildOperationResult = WildDamageRules.apply(state,"p",10,"physical",CONFIG.health_rules)
	near(result.payload["damage"],6.5,"leather physical reduction")
	near(armor.durability,initial-2,"armor durability wear per hit")
	check(not state.survival.bodies["p"].bleeding,"final physical below 10 cannot bleed")
	var rolls: int = 0
	for index: int in range(1000):
		var trial := WildBaseState.new("p",CONFIG)
		trial.survival = WildSurvivalSimulation.create("p",str(index))
		WildIllnessRules.seed_body(trial.survival.bodies["p"],str(index),"p")
		WildDamageRules.apply(trial,"p",10,"physical",CONFIG.health_rules)
		if trial.survival.bodies["p"].bleeding: rolls += 1
	check(rolls >= 140 and rolls <= 260,"20 percent bleeding fixed seed sample: %d / 1000" % rolls)
	var rng: String = state.survival.bodies["p"].health_random_state
	WildDamageRules.apply(state,"p",10,"disease",CONFIG.health_rules)
	near(state.survival.bodies["p"].hp,83.5,"disease bypasses armor")
	check(armor.durability == initial-2 and state.survival.bodies["p"].health_random_state == rng,"disease neither armor wear nor bleeding roll")
	armor.durability = 0
	near(WildDamageRules.apply(state,"p",10,"physical",CONFIG.health_rules).payload["damage"],10,"broken armor inactive")
	state.survival.actions["p"] = {"type":"sleep"}
	WildDamageRules.apply(state,"p",1,"environment",CONFIG.health_rules)
	check(not state.survival.actions.has("p"),"attack interrupts sleep")
	check(WildDamageRules.apply(state,"guest",1,"physical",CONFIG.health_rules).code == &"UNKNOWN_ACTOR","damage actor ownership")
	state = fixture()
	var site: WildOperationResult = WildBuildingRules.auto_site(state,"p",Vector2i(2,2))
	check(site.successful,"sleep camp fixture valid")
	state.survival.buildings["camp"] = {"id":"camp","kind":"camp","x":site.payload["x"],"y":site.payload["y"],"width":2,"height":2,"lit":false,"fuel_seconds":0.0}
	state.survival.bodies["p"].bleeding = true
	check(WildSurvivalActions.start(state,"p",{"action":"sleep","building_id":"camp","hours":1},CONFIG,CATALOG,CONTENT).code == &"SLEEP_UNSAFE","cannot sleep through bleeding")

func _test_medical_and_codec() -> void:
	var state: WildBaseState = fixture()
	var bandage: WildItemInstance = FIXTURE.give(state,&"bandage",CATALOG,CONFIG,2)
	check(start(state,bandage).code == &"NO_BLEEDING","no pointless bandage use")
	state.survival.bodies["p"].bleeding = true
	check(start(state,bandage).successful,"bandage starts")
	check(bandage.quantity == 2 and state.survival.bodies["p"].bleeding,"materials consumed at completion")
	check(WildBaseStateCodec.decode(state.record(),"p",CONFIG,CATALOG) != null,"pending treatment restore")
	time(state,300)
	check(not state.survival.bodies["p"].bleeding and bandage.quantity == 1,"effective bandage consumes one")
	check(state.survival.activities["p"].has("healing"),"effective treatment activity")
	state.survival.bodies["p"].bleeding = true
	check(start(state,bandage).successful,"second bandage starts")
	state.survival.bodies["p"].bleeding = false
	time(state,300)
	check(bandage.quantity == 1,"condition gone no consumption")
	state.survival.bodies["p"].bleeding = true
	check(start(state,bandage).successful,"cancellable medical action")
	time(state,120)
	WildSurvivalCommands.execute(state,WildGameCommand.new("p",&"survival.cancel"),CONFIG,CATALOG,CONTENT)
	check(bandage.quantity == 1 and state.survival.bodies["p"].bleeding and not state.survival.actions.has("p"),"cancel medicine keeps material and illness")
	state.survival.bodies["p"].bleeding = false
	var medicine: WildItemInstance = FIXTURE.give(state,&"herbal_medicine",CATALOG,CONFIG,2)
	check(start(state,medicine).code == &"NO_GASTRO","no pointless medicine use")
	state.survival.bodies["p"].gastro_remaining_seconds = 43200
	check(start(state,medicine).successful,"medicine starts")
	time(state,600)
	near(state.survival.bodies["p"].gastro_remaining_seconds,21000,"medicine subtracts six hours after action")
	near(state.survival.bodies["p"].medicine_cooldown_seconds,7200,"cooldown starts on effect")
	check(start(state,medicine).code == &"MEDICINE_COOLDOWN" and medicine.quantity == 1,"cooldown no consumption")
	var raw: Dictionary = state.record()
	var restored: WildBaseState = WildBaseStateCodec.decode(raw,"p",CONFIG,CATALOG)
	check(restored != null and restored.survival.bodies["p"].record() == state.survival.bodies["p"].record(),"P4 save all timers and RNG")
	for field: String in ["gastro_remaining_seconds","medicine_cooldown_seconds","pollution_check_elapsed","weakness_recovery_seconds"]:
		var malformed: Dictionary = raw.duplicate(true)
		malformed["active_run"]["survival"]["bodies"]["p"][field] = -1
		check(WildBaseStateCodec.decode(malformed,"p",CONFIG,CATALOG) == null,"reject negative "+field)
	var bad: Dictionary = raw.duplicate(true)
	bad["active_run"]["survival"]["bodies"]["p"]["body_version"] = 2
	check(WildBaseStateCodec.decode(bad,"p",CONFIG,CATALOG) == null,"future body version rejected")
	bad = raw.duplicate(true)
	bad["active_run"]["survival"]["bodies"]["p"]["weakness"] = true
	bad["active_run"]["survival"]["bodies"]["p"]["weakness_recovery_seconds"] = 21600
	check(WildBaseStateCodec.decode(bad,"p",CONFIG,CATALOG) == null,"reject completed recovery with active weakness")
	var legacy: Dictionary = raw.duplicate(true)
	legacy["active_run"]["survival"]["bodies"]["p"].erase("body_version")
	var old: WildBaseState = WildBaseStateCodec.decode(legacy,"p",CONFIG,CATALOG)
	check(old != null and old.survival.bodies["p"].hp == state.survival.bodies["p"].hp and old.survival.elapsed_seconds == state.survival.elapsed_seconds,"legacy preserves HP time")
	check(old != null and old.survival.bodies["p"].health_random_state == fresh_body().health_random_state,"legacy stable disease stream")

func _test_transactions_and_coop() -> void:
	var state: WildBaseState = fixture()
	var bandage: WildItemInstance = FIXTURE.give(state,&"bandage",CATALOG,CONFIG,2)
	state.survival.bodies["p"].bleeding = true
	saved = state.record()
	var service := WildBaseService.new(CONFIG,CATALOG,_load,_save,Callable(),Callable(),CONTENT)
	check(service.initialize("p").successful,"service P4 restore")
	var command := WildGameCommand.new("p",&"survival.start",{"action":"treat","item_id":bandage.instance_id})
	save_fail = true
	check(service.submit(command).code == &"SAVE_FAILED" and service.survival_snapshot("p")["action"].is_empty(),"treatment start save rollback")
	save_fail = false
	check(service.submit(command).successful,"same treatment request retry")
	check(service.submit(command).successful and service.survival_snapshot("p")["action"]["duration"] == 300,"treatment request dedup")
	save_fail = true
	check(service.advance_world("p",2.5,"idle").code == &"SAVE_FAILED" and service.body_snapshot("p")["bleeding"],"completion save failure retains disease and material")
	save_fail = false
	check(service.advance_world("p",0,"idle").successful and not service.body_snapshot("p")["bleeding"],"completion retry heals once")
	var before: float = service.body_snapshot("p")["health_points"]
	save_fail = true
	check(service.apply_world_damage("p",10,"physical").code == &"SAVE_FAILED" and service.body_snapshot("p")["health_points"] == before,"damage save rollback")
	save_fail = false
	check(not service.submit(WildGameCommand.new("p",&"body.damage",{"amount":1})).successful,"no client damage operation")
	var coop := WildCoopService.new(CONFIG,CATALOG,CONTENT,_save)
	check(coop.create("host","host","17","secret").successful,"cooperative illness fixture")
	check(coop.join("guest","guest","").successful,"second independent body")
	var host_stream: String = coop.state.survival.bodies["host"].health_random_state
	coop.state.started = true
	coop.state.survival.bodies["guest"].gastro_remaining_seconds = 43200
	coop.online["guest"] = false
	WildSurvivalSimulation.queue_time(coop.state.survival,3600,"idle")
	coop._simulate(coop.state,true)
	near(coop.state.survival.bodies["guest"].gastro_remaining_seconds,39600,"offline illness continues")
	near(coop.state.survival.bodies["host"].water,96,"one actor illness leaves other water normal")
	check(coop.state.survival.bodies["host"].health_random_state == host_stream,"other actor illness no shared random draw")
	check(WildCoopCodec.decode(coop.state.record(),CONFIG,CATALOG,CONTENT) != null,"cooperative health restore")
	check(not coop.snapshot("guest")["players"]["guest"]["body"].has("health_random_state"),"RNG never exposed in network view")
