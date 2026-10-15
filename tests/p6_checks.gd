extends SceneTree
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const F = preload("res://tests/p6_fixtures.gd")
const P5 = preload("res://tests/p5_fixtures.gd")
const PATHS = preload("res://tests/verification_paths.gd")
var passed: int = 0
var failed: int = 0
var saved: Dictionary = {}
var fail_save: bool = false

func _initialize() -> void:
	if not PATHS.arguments_are_isolated(): quit(1); return
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if condition: passed += 1
	else:
		failed += 1
		push_error(label)

func near(value: float, expected: float, label: String) -> void:
	check(absf(value-expected)<0.0001,label+" %.5f / %.5f" % [value,expected])

func _load() -> WildOperationResult:
	return WildOperationResult.accept({"exists":true,"primary":saved.duplicate(true),"backup":{}})

func _save(raw: Dictionary, _preserve: bool = false) -> WildOperationResult:
	if fail_save: return WildOperationResult.reject(&"SAVE_FAILED")
	saved = raw.duplicate(true)
	return WildOperationResult.accept()

func _run() -> void:
	_generation()
	_melee()
	_arrows()
	_ai()
	_traps_and_sleep()
	_saves()
	print("P6 domain checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _generation() -> void:
	check(CONFIG.combat_rules.validate(),"combat config valid")
	var state: WildBaseState = F.create()
	check(state.survival.prey.size() == 29,"20 rabbit / 6 boar / 3 wolf")
	var repeated: WildBaseState = F.create()
	check(state.survival.prey == repeated.survival.prey,"deterministic independent animal stream")
	for animal: Dictionary in state.survival.prey.values():
		check(state.world.distances(state.world.spawn).has(Vector2i(animal["home_x"],animal["home_y"])) and Vector2(animal["home_x"],animal["home_y"]).distance_to(state.world.spawn) >= 30,"reachable safe initial animal")
	check(not WildCombatWorld.initialize(state,CONFIG),"initialization cannot duplicate population")
	var coop: WildBaseState = F.create("p",2)
	check(coop.survival.prey.size() == 42 and coop.survival.departure_players == 2,"locked party animal scaling")
	for animal: Dictionary in coop.survival.prey.values():
		if animal["kind"] == "boar": near(animal["hp"],77,"cooperative boar health"); break
	near(WildCombatWorld.health_scale(coop.survival,"wolf"),1.1,"danger damage scaling")
	var legacy: WildBaseState = P5.create_state()
	var dead: Dictionary = legacy.survival.prey.values()[0]
	dead["alive"] = false
	WildCombatWorld.initialize(legacy,CONFIG)
	check(not dead["alive"] and dead["hp"] == 0 and legacy.survival.prey.size() == 29,"P5 captured entity not revived on migration")
	check(WildCombatWorld.protected(state.world,state.survival,state.world.centre(state.world.spawn),CONFIG),"first six hour spawn protection")
	state.survival.elapsed_seconds = CONFIG.combat_rules.safe_seconds
	check(not WildCombatWorld.protected(state.world,state.survival,state.world.centre(state.world.spawn),CONFIG),"protection expires at six hours")

func _melee() -> void:
	var state: WildBaseState = F.create()
	var animal: Dictionary = F.focus(state)
	check(F.attack(state).code == &"MISSING_WEAPON","weapon must be equipped")
	var tool: WildItemInstance = F.equip(state,"knife")
	check(F.attack(state).successful,"knife hits actual rabbit")
	near(animal["hp"],6,"knife damage 14")
	near(state.survival.bodies["p"].stamina,96,"knife fee 4")
	near(tool.durability,99,"attack wear 1")
	check(F.attack(state).code == &"ATTACK_COOLDOWN","same actor cooldown blocks spam")
	state.survival.elapsed_seconds = 84
	check(F.attack(state).successful and not animal["alive"] and animal["loot_claimed"],"lethal hit commits once")
	check(F.quantity(state,"raw_meat") == 1 and F.quantity(state,"hide") == 1 and state.skills.experience["hunting"] == 12,"kill loot and experience")
	WildCombatRules.hit(state,"p",animal,100,CONFIG,CATALOG)
	check(F.quantity(state,"raw_meat") == 1 and state.skills.experience["hunting"] == 12,"dead entity cannot duplicate loot")
	state.survival.elapsed_seconds += 84
	check(F.attack(state,Vector2.LEFT).successful and state.skills.experience["hunting"] == 12,"empty swing no XP")
	near(tool.durability,97,"empty swing still wears weapon")
	var axe_state: WildBaseState = F.create()
	var rabbit: Dictionary = F.focus(axe_state)
	F.equip(axe_state,"axe")
	axe_state.skills.levels["hunting"] = 3
	check(F.attack(axe_state).successful and not rabbit["alive"] and F.quantity(axe_state,"raw_meat") == 2,"axe damage 22 and hunter3 extra meat")
	near(axe_state.survival.bodies["p"].stamina,93,"axe stamina 7")
	var blocked: WildBaseState = F.create()
	var boar: Dictionary = F.focus(blocked,"boar")
	F.equip(blocked,"knife")
	var cell: Vector2i = blocked.world.cell_at(blocked.world.players["p"]+Vector2(12,0))
	blocked.world.blocked_cells[cell] = true
	var hp: float = boar["hp"]
	F.attack(blocked)
	near(boar["hp"],hp,"wall stops melee")
	blocked.survival.elapsed_seconds += 84
	blocked.survival.bodies["p"].stamina = 0
	check(F.attack(blocked).code == &"INSUFFICIENT_STAMINA","exhaustion rejects attack without effects")
	check(not WildCombatRules.attack(blocked,"p",{"direction":[NAN,0]},CONFIG,CATALOG).successful,"nonfinite direction rejected")
	check(not WildCombatRules.attack(blocked,"p",{"direction":[0,0]},CONFIG,CATALOG).successful,"zero direction rejected")

func _arrows() -> void:
	var state: WildBaseState = F.create()
	var rabbit: Dictionary = F.focus(state)
	F.equip(state,"bow")
	check(F.attack(state).code == &"SKILL_REQUIRED","bow skill gate")
	state.skills.levels["hunting"] = 1
	check(F.attack(state).code == &"NO_ARROWS","bow ammo gate")
	P5.give(state,"arrow",3)
	state.world.players["p"] = WildCombatWorld.position(rabbit,state.world)-Vector2(96,0)
	check(F.attack(state).successful and F.quantity(state,"arrow") == 2 and state.survival.projectiles.size() == 1,"launch consumes one actual arrow")
	check(rabbit["hp"] == 20,"projectile not instant target damage")
	check(WildBaseStateCodec.decode(state.record(),"p",CONFIG,CATALOG) != null,"in flight arrow / cooldown restores")
	for index: int in range(5):
		if state.survival.projectiles.is_empty(): break
		WildCombatRules._projectiles(state,{},CONFIG,CATALOG,0.1)
	check(not rabbit["alive"] and state.survival.projectiles.is_empty() and F.quantity(state,"raw_meat") == 1,"swept arrow collision / one loot")
	var wall: WildBaseState = F.create()
	var target: Dictionary = F.focus(wall)
	F.equip(wall,"bow")
	wall.skills.levels["hunting"] = 1
	P5.give(wall,"arrow")
	wall.world.players["p"] = WildCombatWorld.position(target,wall.world)-Vector2(96,0)
	wall.world.blocked_cells[wall.world.cell_at(wall.world.players["p"]+Vector2(32,0))] = true
	F.attack(wall)
	WildCombatRules._projectiles(wall,{},CONFIG,CATALOG,0.5)
	check(target["hp"] == 20 and wall.survival.projectiles.is_empty() and F.quantity(wall,"arrow") == 0,"wall blocks arrow / no ammo refund")
	var miss: WildBaseState = F.create()
	F.focus(miss)
	F.equip(miss,"bow")
	miss.skills.levels["hunting"] = 1
	P5.give(miss,"arrow")
	F.attack(miss,Vector2.LEFT)
	WildCombatRules._projectiles(miss,{},CONFIG,CATALOG,2)
	check(miss.survival.projectiles.is_empty() and miss.skills.experience["hunting"] == 0,"range lifetime bounded / misses zero experience")

func _ai() -> void:
	var state: WildBaseState = F.create()
	var rabbit: Dictionary = F.focus(state)
	var before: Vector2 = WildCombatWorld.position(rabbit,state.world)
	WildAnimalAI.tick(state,{},CONFIG,0.25)
	check(rabbit["mode"] == "flee" and WildCombatWorld.position(rabbit,state.world).distance_to(state.world.players["p"]) > before.distance_to(state.world.players["p"]),"rabbit alarm flees")
	var pig: WildBaseState = F.create()
	var boar: Dictionary = F.focus(pig,"boar")
	WildAnimalAI.tick(pig,{},CONFIG,0.25)
	check(boar["mode"] == "alert" and pig.survival.bodies["p"].hp == 100,"boar warns but does not attack unprovoked")
	F.equip(pig,"knife")
	F.attack(pig)
	check(boar["target"] == "p" and boar["mode"] == "chase","hit provokes boar")
	pig.survival.bodies["p"].health_random_state = P5.random_state_for(true,CONFIG.health_rules.bleeding_probability)
	WildAnimalAI.tick(pig,{},CONFIG,0.25)
	near(pig.survival.bodies["p"].hp,85,"boar actual damage 15")
	check(pig.survival.bodies["p"].bleeding,"actual animal hit triggers physical bleeding rule")
	WildAnimalAI.tick(pig,{},CONFIG,0.25)
	near(pig.survival.bodies["p"].hp,85,"animal cooldown prevents repeated same tick damage")
	var wolf_state: WildBaseState = F.create()
	var wolf: Dictionary = F.focus(wolf_state,"wolf")
	WildAnimalAI.tick(wolf_state,{},CONFIG,0.25)
	check(wolf["mode"] == "chase" and wolf_state.survival.bodies["p"].hp == 88,"wolf senses and attacks")
	var armor: WildItemInstance = WildItemInstance.new(CATALOG.find(&"leather_armor"))
	wolf_state.containers["armor"].placements[armor.instance_id] = {"item":armor,"position":Vector2i.ZERO,"rotated":false}
	wolf_state.survival.elapsed_seconds = 144
	WildAnimalAI.tick(wolf_state,{},CONFIG,0.25)
	near(wolf_state.survival.bodies["p"].hp,80.2,"armor reduces wolf damage to 7.8")
	near(armor.durability,98,"armor hit wear")
	wolf_state.world.players["p"] = wolf_state.world.centre(Vector2i(wolf["home_x"],wolf["home_y"]))+Vector2(600,0)
	WildAnimalAI.tick(wolf_state,{},CONFIG,0.25)
	check(wolf["target"].is_empty() and wolf["mode"] != "chase","leash breaks pursuit")
	var geometry: WildBaseState = F.create()
	var moving: Dictionary = F.focus(geometry)
	var stop: Vector2 = WildCombatWorld.position(moving,geometry.world)
	geometry.world.blocked_cells[geometry.world.cell_at(stop+Vector2(32,0))] = true
	WildAnimalAI.move(moving,geometry.world,Vector2.RIGHT,2,300,geometry.survival,CONFIG)
	check(WildCombatWorld.position(moving,geometry.world).x < stop.x+16 and WildAnimalAI.clear(geometry.world,WildCombatWorld.position(moving,geometry.world)),"large displacement cannot tunnel through building")
	geometry.world.blocked_cells.clear()
	var water: Vector2i = geometry.world.cell_at(stop+Vector2(32,0))
	geometry.world.tiles[water.y*geometry.world.size.x+water.x] = WildWorldData.Terrain.WATER
	F.place(moving,geometry.world,geometry.world.cell_at(stop))
	WildAnimalAI.move(moving,geometry.world,Vector2.RIGHT,2,300,geometry.survival,CONFIG)
	check(WildCombatWorld.position(moving,geometry.world).x < stop.x+16,"water blocks animal")
	var track_state: WildBaseState = F.create()
	var tracked: Dictionary = F.focus(track_state)
	track_state.survival.elapsed_seconds = 300
	WildAnimalAI.move(tracked,track_state.world,Vector2.RIGHT,0.5,64,track_state.survival,CONFIG)
	check(not track_state.survival.tracks.is_empty(),"movement emits persistent tracks")
	check(WildCombatView.create(track_state,"p")["tracks"].is_empty(),"unskilled view hides tracks")
	track_state.skills.levels["hunting"] = 2
	check(not WildCombatView.create(track_state,"p")["tracks"].is_empty(),"hunter2 sees actual tracks")
	check(not WildCombatView.animals(track_state.survival)[tracked["id"]].has("random_state"),"future animal random not exposed")

func _traps_and_sleep() -> void:
	var state: WildBaseState = F.create()
	var rabbit: Dictionary = F.focus(state)
	var trap: Dictionary = {"id":"test-trap","kind":"small_trap","x":rabbit["x"]-1,"y":rabbit["y"],"width":1,"height":1,"owner":"p","bait":1,"uses_left":3,"capture":{},"next_check":0.0,"trap_random_state":P5.random_state_for(true,0.4),"probability_bonus":0.0}
	check(WildTrapRules.tick(trap,state.survival,state.world,CONTENT,CONFIG) and not rabbit["alive"] and rabbit["hp"] == 0 and rabbit["loot_claimed"],"trap consumes same dynamic entity")
	WildCombatRules.hit(state,"p",rabbit,100,CONFIG,CATALOG)
	check(F.quantity(state,"raw_meat") == 0,"trapped animal cannot also drop hunting loot")
	var sleep_state: WildBaseState = F.create()
	var wolf: Dictionary = F.focus(sleep_state,"wolf")
	sleep_state.survival.actions["p"] = {"type":"sleep"}
	WildAnimalAI.tick(sleep_state,{},CONFIG,0.25)
	check(not sleep_state.survival.actions.has("p") and sleep_state.survival.bodies["p"].hp == 88,"actual attack wakes sleep")
	var integrated: WildBaseState = F.create()
	F.focus(integrated,"wolf")
	integrated.survival.actions["p"] = {"type":"sleep","remaining":3600.0,"duration":3600.0,"activity":"sleep","building_id":""}
	WildSurvivalSimulation.sleep(integrated,"p",CONFIG,CATALOG,CONTENT)
	check(integrated.survival.elapsed_seconds <= 12.001 and integrated.survival.pending_seconds == 0 and integrated.survival.actions.is_empty(),"shared simulation attack stops remaining sleep jump at danger boundary")
	var lethal: WildBaseState = F.create()
	F.focus(lethal,"wolf")
	lethal.survival.bodies["p"].hp = 1
	F.time(lethal,60)
	check(lethal.survival.outcome == "lost" and lethal.survival.bodies["p"].hp == 0,"animal death ends single run without later action output")
	var refill: WildBaseState = F.create()
	F.focus(refill)
	refill.world.players["p"] = refill.world.centre(refill.world.spawn)
	refill.survival.elapsed_seconds = 86400
	check(WildCombatWorld.hourly(refill,{},CONFIG,CONTENT),"daily wildlife refill")
	var populations: Dictionary = {"rabbit":0,"boar":0,"wolf":0}
	for animal: Dictionary in refill.survival.prey.values():
		if animal["alive"]:
			populations[animal["kind"]] += 1
			check(WildCombatWorld.position(animal,refill.world).distance_to(refill.world.players["p"]) >= 12*32,"refill outside player view")
	check(populations == {"rabbit":5,"boar":1,"wolf":1},"actual dead population replenished by limited daily amount")
	check(refill.survival.next_animal_refill == 172800,"refill schedule persists")
	var disturbance: WildBaseState = F.create()
	F.focus(disturbance,"boar")
	disturbance.survival.elapsed_seconds = 3600
	disturbance.survival.actions["p"] = {"type":"sleep","building_id":""}
	var strict: WildGameConfig = CONFIG.duplicate(true)
	strict.combat_rules = WildCombatConfig.new()
	strict.combat_rules.sleep_disturbance_per_hour = 1
	var illness_rng: String = disturbance.survival.bodies["p"].health_random_state
	var refill_rng: String = disturbance.survival.wildlife_random_state
	WildCombatWorld.hourly(disturbance,{},strict,CONTENT)
	check(not disturbance.survival.actions.has("p"),"nearby danger interrupts sleep at hourly risk check")
	check(disturbance.survival.sleep_random_states.has("p") and disturbance.survival.bodies["p"].health_random_state == illness_rng and disturbance.survival.wildlife_random_state == refill_rng,"sleep RNG independent from illness / refill streams")
	check(WildBaseStateCodec.decode(disturbance.record(),"p",CONFIG,CATALOG) != null,"personal sleep RNG survives restore")
	var capped: WildBaseState = F.create()
	for day: int in range(1,4):
		capped.survival.elapsed_seconds = 86400*day
		WildCombatWorld.hourly(capped,{},CONFIG,CONTENT)
		for kind: String in ["rabbit","boar","wolf"]:
			var living: int = 0
			for animal: Dictionary in capped.survival.prey.values():
				if animal["alive"] and animal["kind"] == kind: living += 1
			check(living <= CONFIG.combat_rules.animals[kind]["maximum"],"daily population never exceeds configured cap")

func _saves() -> void:
	var state: WildBaseState = F.create()
	F.focus(state)
	F.equip(state,"knife")
	saved = state.record()
	var service := WildBaseService.new(CONFIG,CATALOG,_load,_save,Callable(),Callable(),CONTENT)
	check(service.initialize("p").successful,"P6 authority restores dynamic world")
	var command := WildGameCommand.new("p",&"combat.attack",{"direction":[1.0,0.0],"damage":9999,"target":"other"})
	fail_save = true
	check(service.submit(command).code == &"SAVE_FAILED" and service.world_dynamic()["prey"][state.survival.prey.values()[0]["id"]]["hp"] == 20,"attack save failure rollback")
	fail_save = false
	check(service.submit(command).successful,"same request retry commits")
	var committed: Dictionary = saved.duplicate(true)
	check(service.submit(command).successful and saved == committed,"same request replay cannot duplicate damage or spend")
	check(service.snapshot()["skills"]["experience"]["hunting"] == 0,"client damage payload ignored / actual damage 14 not lethal")
	check(service.submit(WildGameCommand.new("other",&"combat.attack",{"direction":[1,0]})).code == &"UNKNOWN_ACTOR","forged actor rejected")
	var json: Dictionary = JSON.parse_string(JSON.stringify(saved))
	check(WildBaseStateCodec.decode(json,"p",CONFIG,CATALOG) != null,"JSON position HP cooldown and RNG restore")
	var invalid: Dictionary = json.duplicate(true)
	invalid["active_run"]["survival"]["combat"]["version"] = 2
	check(WildSaveVersions.future(invalid) and WildBaseStateCodec.decode(invalid,"p",CONFIG,CATALOG) == null,"future combat version protected")
	invalid = json.duplicate(true)
	var prey: Dictionary = invalid["active_run"]["survival"]["progression"]["prey"]
	for animal: Dictionary in prey.values():
		if animal["alive"]:
			animal["alive"] = false
			break
	check(WildBaseStateCodec.decode(invalid,"p",CONFIG,CATALOG) == null,"alive HP mismatch rejected")
	invalid = json.duplicate(true)
	invalid["active_run"]["survival"]["combat"]["attack_ready_at"]["stranger"] = 99
	check(WildBaseStateCodec.decode(invalid,"p",CONFIG,CATALOG) == null,"unknown cooldown actor rejected")
	invalid = json.duplicate(true)
	invalid["active_run"]["survival"]["combat"]["serial"] = 0
	check(WildBaseStateCodec.decode(invalid,"p",CONFIG,CATALOG) == null,"invalid serial cannot overwrite an existing wildlife ID on refill")
	check(service.inspect_resource("p",{"resource_id":state.survival.prey.values()[0]["id"],"version":0}).successful,"actual nearby animal inspect")
