class_name WildCombatCodec
extends RefCounted
## P6 子版本校验：位置 / 栖息地 / 生命与捕获一致，投射与冷却不能读档复制或变更伤害。
static func restore(raw: Variant, run: WildSurvivalState, world: WildWorldData, config: WildGameConfig) -> bool:
	if raw == null: return true
	if not raw is Dictionary or raw.get("version",0) != 1 or not raw.get("initialized",null) is bool: return false
	for key: String in ["projectiles","attack_ready_at","feedback"]:
		if not raw.get(key,null) is Dictionary: return false
	if not raw.get("tracks",null) is Array or not WildWorldGenerator.valid_seed(raw.get("random_state",null),true): return false
	for key: String in ["departure_players","serial"]:
		if not WildDataValidation.whole(raw.get(key,null)): return false
	if raw["departure_players"] < 1 or raw["departure_players"] > 4 or raw["serial"] < 0: return false
	for key: String in ["next_refill","next_disturbance"]:
		if not WildDataValidation.number(raw.get(key,null)) or raw[key] < 0: return false
	run.combat_initialized = raw["initialized"]
	run.departure_players = int(raw["departure_players"])
	run.next_animal_serial = int(raw["serial"])
	run.next_animal_refill = float(raw["next_refill"])
	run.next_disturbance = float(raw["next_disturbance"])
	run.wildlife_random_state = raw["random_state"]
	if not run.combat_initialized: return raw["projectiles"].is_empty() and raw["attack_ready_at"].is_empty() and raw["feedback"].is_empty() and raw["tracks"].is_empty()
	if not run.progression_initialized or run.prey.size() > 4096 or run.next_animal_refill < run.elapsed_seconds or run.next_disturbance < run.elapsed_seconds: return false
	var living: Dictionary = {"rabbit":0,"boar":0,"wolf":0}
	for animal: Dictionary in run.prey.values():
		if str(animal["id"]).begins_with("wildlife:"):
			var parts: PackedStringArray = str(animal["id"]).split(":")
			if parts.size() != 3 or parts[1] != animal["kind"] or not parts[2].is_valid_int() or parts[2].to_int() < 0 or parts[2].to_int() >= run.next_animal_serial: return false
		if animal["alive"]: living[animal["kind"]] += 1
		for key: String in ["home_x","home_y"]:
			if not WildDataValidation.whole(animal.get(key,null)): return false
		for key: String in ["px","py","hp","max_hp","ready_at","wander_at","last_track"]:
			if not WildDataValidation.number(animal.get(key,null)) or animal[key] < 0: return false
		var home := Vector2i(animal["home_x"],animal["home_y"])
		var point := Vector2(animal["px"],animal["py"])
		if not world.contains(home) or world.tiles[home.y*world.size.x+home.x] != WildWorldData.Terrain.FOREST or home.distance_to(world.spawn) < 30 or not world.contains(world.cell_at(point)) or Vector2i(animal["x"],animal["y"]) != world.cell_at(point): return false
		if animal["alive"] and (not WildAnimalAI.clear(world,point) or WildCombatWorld.protected(world,run,point,config) and animal["kind"] != "rabbit"): return false
		if animal["hp"] > float(config.combat_rules.animals[animal["kind"]]["hp"])*WildCombatWorld.health_scale(run,animal["kind"])+0.000001 or animal["alive"] != (animal["hp"] > 0): return false
		if not is_equal_approx(float(animal["max_hp"]),float(config.combat_rules.animals[animal["kind"]]["hp"])*WildCombatWorld.health_scale(run,animal["kind"])): return false
		if not animal.get("loot_claimed",null) is bool or animal["loot_claimed"] != (not animal["alive"]): return false
		if animal.get("mode","") not in ["wander","alert","flee","chase","return","dead"] or (animal["mode"] == "dead") == animal["alive"]: return false
		if not animal.get("target",null) is String or (not animal["target"].is_empty() and not run.bodies.has(animal["target"])): return false
		if not WildWorldGenerator.valid_seed(animal.get("random_state",null),true) or not _direction(animal.get("direction",null)): return false
		if animal["last_track"] > run.elapsed_seconds: return false
	for kind: String in living:
		if living[kind] > WildCombatWorld.count(run,kind,"maximum",config): return false
	for actor: Variant in raw["attack_ready_at"]:
		if not run.bodies.has(actor) or not WildDataValidation.number(raw["attack_ready_at"][actor]) or raw["attack_ready_at"][actor] < 0: return false
	for id: Variant in raw["projectiles"]:
		var arrow: Variant = raw["projectiles"][id]
		if not id is String or id.is_empty() or not arrow is Dictionary or arrow.get("id",null) != id or not run.bodies.has(arrow.get("owner",null)): return false
		for key: String in ["x","y","dx","dy","remaining","damage"]:
			if not WildDataValidation.number(arrow.get(key,null)): return false
		if not _direction([arrow["dx"],arrow["dy"]]) or arrow["remaining"] <= 0 or arrow["remaining"] > config.combat_rules.arrow_range_tiles*world.tile_pixels or not is_equal_approx(float(arrow["damage"]),float(config.combat_rules.weapons["bow"]["damage"])) or not world.walkable(world.cell_at(Vector2(arrow["x"],arrow["y"]))): return false
	if raw["tracks"].size() > config.combat_rules.maximum_tracks: return false
	for track: Variant in raw["tracks"]:
		if not track is Dictionary or not run.prey.has(track.get("animal_id",null)) or track.get("kind",null) != run.prey[track["animal_id"]]["kind"] or not WildDataValidation.whole(track.get("x",null)) or not WildDataValidation.whole(track.get("y",null)) or not world.contains(Vector2i(track["x"],track["y"])) or not WildDataValidation.number(track.get("at",null)) or track["at"] < 0 or track["at"] > run.elapsed_seconds: return false
	for actor: Variant in raw["feedback"]:
		var event: Variant = raw["feedback"][actor]
		if not run.bodies.has(actor) or not event is Dictionary or event.get("kind","") not in ["hit","swing","hurt"]: return false
		for key: String in ["at","damage","x","y"]:
			if not WildDataValidation.number(event.get(key,null)): return false
		if event["at"] < 0 or event["at"] > run.elapsed_seconds or event["damage"] < 0 or event["damage"] > 1000 or not world.contains(world.cell_at(Vector2(event["x"],event["y"]))): return false
	run.projectiles = raw["projectiles"].duplicate(true)
	run.attack_ready_at = raw["attack_ready_at"].duplicate()
	run.tracks.assign(raw["tracks"].duplicate(true))
	run.combat_feedback = raw["feedback"].duplicate(true)
	return true

static func _direction(raw: Variant) -> bool:
	return raw is Array and raw.size() == 2 and WildDataValidation.number(raw[0]) and WildDataValidation.number(raw[1]) and absf(Vector2(raw[0],raw[1]).length()-1) < 0.00001
