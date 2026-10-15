class_name WildCoopSleep
extends RefCounted
## 三十秒投票与有界跳时：每次最多一分钟，任一留存角色遇险即全体醒来。
static func safe(room: WildCoopState) -> bool:
	for actor: String in room.members:
		var body: WildBodyState = room.survival.bodies[actor]
		if body.hp <= 0: continue
		if body.hp <= 20 or body.water <= 20 or body.bleeding: return false
		for animal: Dictionary in room.survival.prey.values():
			if animal["alive"] and animal["kind"] in ["boar","wolf"] and WildCombatWorld.position(animal,room.world).distance_to(room.world.players[actor]) <= room.world.tile_pixels*5: return false
	return true

static func cancel(room: WildCoopState, reason: String) -> void:
	for actor: String in room.survival.actions.keys():
		if room.survival.actions[actor]["type"] == "sleep": room.survival.actions.erase(actor)
	room.lifecycle["vote"] = {}
	room.survival.notice = reason

static func execute(room: WildCoopState, actor: String, data: Dictionary, online: Dictionary, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent) -> WildOperationResult:
	if not room.started or room.lifecycle["phase"] != "running" or room.survival.bodies[actor].hp <= 0: return WildOperationResult.reject(&"INVALID_PHASE")
	var previous: Dictionary = room.lifecycle["vote"]
	if not previous.is_empty() and not previous["sleeping"] and room.lifecycle["real_seconds"] >= previous["expires"]: cancel(room,"睡眠投票超时，需重新确认。")
	if data.get("agree",true) == false:
		cancel(room,"睡眠提案已取消。")
		return WildOperationResult.accept()
	var hours: Variant = data.get("hours",1)
	if not WildDataValidation.whole(hours) or int(hours) not in [1,2,4,8]: return WildOperationResult.reject(&"INVALID_QUANTITY")
	if not safe(room): return WildOperationResult.reject(&"SLEEP_UNSAFE")
	if not room.survival.actions.is_empty(): return WildOperationResult.reject(&"ACTION_BUSY")
	var vote: Dictionary = room.lifecycle["vote"]
	if vote.is_empty():
		vote = {"hours":int(hours),"expires":room.lifecycle["real_seconds"]+30,"agree":{},"sleeping":false,"remaining":float(hours)*3600}
		room.lifecycle["vote"] = vote
	if vote["sleeping"] or vote["hours"] != int(hours): return WildOperationResult.reject(&"VOTE_CONFLICT")
	vote["agree"][actor] = true
	for member: String in room.members:
		if online.get(member,false) and room.survival.bodies[member].hp > 0 and not vote["agree"].get(member,false): return WildOperationResult.accept()
	# 全部动作在同一候选事务创建；一人不在营地则全部回滚。
	for member: String in room.members:
		if not online.get(member,false) or room.survival.bodies[member].hp <= 0: continue
		var result: WildOperationResult = WildSurvivalActions.start(room.members[member],member,{"action":"sleep","hours":int(hours)},config,catalog,content)
		if not result.successful: return result
	vote["sleeping"] = true
	return WildOperationResult.accept()
