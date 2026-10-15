class_name WildFullCoopCodec
extends RefCounted
## 完整房间子版本与交付链校验。拒绝跨玩家收据、重复实例与不一致的死亡 / 结算阶段。
static func restore(raw: Dictionary, room: WildCoopState, ids: Dictionary, config: WildGameConfig, catalog: WildItemCatalog) -> bool:
	var life: Dictionary = raw["lifecycle"]
	if life.get("version",0) != 1 or life.get("phase","") not in ["lobby","loading","running","settled","cancelled"]: return false
	for key: String in ["ready","loaded","offers","outbox","acks","dead","vote","gifts"]:
		if not life.get(key,null) is Dictionary: return false
	if not WildDataValidation.number(life.get("real_seconds",null)) or life["real_seconds"] < 0 or not life.get("world_hash",null) is String: return false
	if room.started != (life["phase"] in ["loading","running","settled"]): return false
	if room.started and life["world_hash"].length() != 64: return false
	if room.started and (room.world.resource_players != room.members.size() or room.survival.departure_players != room.members.size()): return false
	if (life["phase"] == "settled") != (room.survival.outcome != "running"): return false
	for key: String in ["ready","loaded"]:
		for actor: Variant in life[key]:
			if not room.members.has(actor) or not life[key][actor] is bool: return false
	for actor: Variant in life["offers"]:
		var offer: Variant = life["offers"][actor]
		if not room.members.has(actor) or not offer is Dictionary or not offer.get("active",null) is bool or not WildDataValidation.whole(offer.get("seq",null)) or offer["seq"] < 1 or not offer.get("skills_hash",null) is String: return false
		var imported: WildBaseState = WildCoopProfileRules.manifest_state(offer.get("manifest",null),config,catalog)
		if imported == null or imported.player_id != actor or offer["manifest"]["room_id"] != room.room_id or offer["manifest"]["run_id"] != room.run_id: return false
		if life["phase"] in ["loading","running"] and not offer["active"]: return false
		if life["phase"] in ["settled","cancelled"] and offer["active"]: return false
	if room.started and life["offers"].size() != room.members.size(): return false
	var event_ids: Dictionary = {}
	for actor: Variant in life["outbox"]:
		if not room.members.has(actor) or not life["outbox"][actor] is Dictionary: return false
		for id: Variant in life["outbox"][actor]:
			var event: Variant = life["outbox"][actor][id]
			if not WildCoopProfileRules.event_valid(event,config,catalog) or event["owner"] != actor or event["event_id"] != id or event["room_id"] != room.room_id or event["run_id"] != room.run_id or event_ids.has(id): return false
			event_ids[id] = event["hash"]
	for id: Variant in life["acks"]:
		if not event_ids.has(id) or life["acks"][id] != event_ids[id]: return false
	# 完整日志不能只保留“已发送”摘要；当前租约必须包含连续的接收 / 成长 / 终态链。
	for actor: String in life["offers"]:
		var offer: Dictionary = life["offers"][actor]
		var events: Dictionary = {}
		for event: Dictionary in life["outbox"].get(actor,{}).values():
			if event["lease_id"] == offer["manifest"]["lease_id"]:
				if events.has(int(event["seq"])) or event["seq"] > offer["seq"]: return false
				events[int(event["seq"])] = event
			if event["kind"] == "settlement":
				for entry: Dictionary in event["items"]:
					if ids.has(entry["item"]["id"]): return false
					ids[entry["item"]["id"]] = true
		if events.size() != int(offer["seq"]) or events.get(1,{}).get("kind","") != "accepted": return false
		for sequence: int in range(1,int(offer["seq"])+1):
			if not events.has(sequence): return false
			if sequence < int(offer["seq"]) and events[sequence]["kind"] in ["release","settlement"]: return false
		var terminal: bool = events[int(offer["seq"])]["kind"] in ["release","settlement"]
		if offer["active"] == terminal: return false
	if not raw.get("corpses",null) is Dictionary or raw["corpses"].size() != life["dead"].size(): return false
	for actor: Variant in life["dead"]:
		if not room.members.has(actor) or room.survival.bodies[actor].hp > 0: return false
		var dead: Variant = life["dead"][actor]
		if not dead is Dictionary or dead.get("id","") != "corpse:"+actor: return false
		for key: String in ["x","y","at"]:
			if not WildDataValidation.number(dead.get(key,null)): return false
		if Vector2(dead["x"],dead["y"]) != room.world.players[actor] or dead["at"] < 0 or dead["at"] > room.survival.elapsed_seconds: return false
		var corpse: WildInventoryContainer = WildCoopCodec.decode_container(raw["corpses"].get(dead["id"],null),dead["id"],Vector2i(maxi(12,config.backpack_grid.x),config.backpack_grid.y+6),1000,room,ids,config,catalog)
		if corpse == null: return false
		room.corpses[corpse.container_id] = corpse
		for slot: String in WildCoopProfileRules.SLOTS:
			if not room.members[actor].containers[slot].placements.is_empty(): return false
	for actor: String in room.members:
		if room.started and room.survival.bodies[actor].hp <= 0 and not life["dead"].has(actor): return false
		if life["phase"] == "settled" or not life["offers"].has(actor):
			for slot: String in WildCoopProfileRules.SLOTS:
				if not room.members[actor].containers[slot].placements.is_empty(): return false
	var vote: Dictionary = life["vote"]
	if not vote.is_empty():
		if life["phase"] != "running" or not WildDataValidation.whole(vote.get("hours",null)) or int(vote["hours"]) not in [1,2,4,8] or not vote.get("sleeping",null) is bool or not vote.get("agree",null) is Dictionary: return false
		for key: String in ["expires","remaining"]:
			if not WildDataValidation.number(vote.get(key,null)) or vote[key] < 0: return false
		for actor: Variant in vote["agree"]:
			if not room.members.has(actor) or vote["agree"][actor] != true: return false
	for id: Variant in life["gifts"]:
		var gift: Variant = life["gifts"][id]
		if not gift is Dictionary or gift.get("id",null) != id or not room.members.has(gift.get("from",null)) or not room.members.has(gift.get("target",null)) or gift["from"] == gift["target"] or not gift.get("item_id",null) is String: return false
		if WildInventoryOperations.find(room.members[gift["from"]],gift["item_id"]).is_empty(): return false
	room.lifecycle = life.duplicate(true)
	return true
