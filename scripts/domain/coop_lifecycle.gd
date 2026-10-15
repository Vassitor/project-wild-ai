class_name WildCoopLifecycle
extends RefCounted
## 完整房间的准备屏障、租约接收、死亡 / 尸体与逐人结算；不依赖网络 peer 或 UI。
static func offer(room: WildCoopState, actor: String, data: Dictionary, config: WildGameConfig, catalog: WildItemCatalog) -> WildOperationResult:
	if room.lifecycle["phase"] not in ["lobby","cancelled"]: return WildOperationResult.reject(&"INVALID_PHASE")
	var manifest: Variant = data.get("manifest",null)
	var imported: WildBaseState = WildCoopProfileRules.manifest_state(manifest,config,catalog)
	if imported == null or imported.player_id != actor or manifest["room_id"] != room.room_id or manifest["run_id"] != room.run_id: return WildOperationResult.reject(&"INVALID_LOADOUT")
	var previous: Dictionary = room.lifecycle["offers"].get(actor,{})
	if not previous.is_empty() and not previous["active"] and previous["manifest"]["lease_id"] == manifest["lease_id"]:
		return WildOperationResult.accept() if room.lifecycle["phase"] == "cancelled" and previous["manifest"]["hash"] == manifest["hash"] else WildOperationResult.reject(&"LEASE_CLOSED")
	if not previous.is_empty() and previous["active"]:
		return WildOperationResult.accept() if previous["manifest"]["hash"] == manifest["hash"] else WildOperationResult.reject(&"COOP_RESERVED")
	var ids: Dictionary = {}
	for other: String in room.members:
		if other == actor: continue
		for slot: String in WildCoopProfileRules.SLOTS:
			for id: String in room.members[other].containers[slot].placements: ids[id] = true
	for slot: String in WildCoopProfileRules.SLOTS:
		for id: String in imported.containers[slot].placements:
			if ids.has(id): return WildOperationResult.reject(&"DUPLICATE_ITEM")
		room.members[actor].containers[slot] = imported.containers[slot].copy()
	room.members[actor].skills = imported.skills.copy()
	room.members[actor].currency = imported.currency
	room.lifecycle["offers"][actor] = {"manifest":manifest.duplicate(true),"active":true,"seq":0,"skills_hash":""}
	room.lifecycle["ready"][actor] = false
	WildCoopDeliveries.emit_event(room,actor,"accepted")
	if room.lifecycle["phase"] == "cancelled": return withdraw(room,actor)
	return WildOperationResult.accept()

static func withdraw(room: WildCoopState, actor: String) -> WildOperationResult:
	if room.lifecycle["phase"] not in ["lobby","cancelled"]: return WildOperationResult.reject(&"INVALID_PHASE")
	var lease: Dictionary = room.lifecycle["offers"].get(actor,{})
	if lease.is_empty() or not lease["active"]: return WildOperationResult.accept()
	WildCoopDeliveries.emit_event(room,actor,"release")
	lease["active"] = false
	room.lifecycle["ready"][actor] = false
	for slot: String in WildCoopProfileRules.SLOTS:
		room.members[actor].containers[slot].placements.clear()
		room.members[actor].containers[slot].version += 1
	return WildOperationResult.accept()

static func start(room: WildCoopState, online: Dictionary, config: WildGameConfig) -> WildOperationResult:
	if room.lifecycle["phase"] != "lobby" or room.members.size() < 2 or room.members.size() > 4: return WildOperationResult.reject(&"ROOM_NOT_READY")
	for actor: String in room.members:
		if not online.get(actor,false) or not room.lifecycle["ready"].get(actor,false) or not room.lifecycle["offers"].get(actor,{}).get("active",false): return WildOperationResult.reject(&"ROOM_NOT_READY")
	if not WildCoopWorldRules.scale(room.world,room.members.size()): return WildOperationResult.reject(&"GENERATION_FAILED")
	var cells: Array[Vector2i] = []
	var near: Dictionary = room.world.distances(room.world.spawn,3)
	for cell: Vector2i in near:
		if WildWorldRules.feet_clear(room.world,room.world.centre(cell)): cells.append(cell)
	cells.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return (a.y*room.world.size.x+a.x < b.y*room.world.size.x+b.x) if near[a] == near[b] else near[a] < near[b])
	if cells.size() < room.members.size(): return WildOperationResult.reject(&"GENERATION_FAILED")
	var actors: Array = room.members.keys()
	actors.sort()
	var index: int = 0
	for actor: String in actors:
		room.world.players[actor] = room.world.centre(cells[index])
		WildSurvivalSimulation.explore(room.members[actor],actor)
		index += 1
	WildCombatWorld.initialize(room.members[room.host_id],config,room.members.size())
	room.started = true
	room.lifecycle["phase"] = "loading"
	room.lifecycle["world_hash"] = WildCanonicalData.digest(room.world.record())
	room.lifecycle["loaded"] = {}
	return WildOperationResult.accept()

static func loaded(room: WildCoopState, actor: String, data: Dictionary) -> WildOperationResult:
	if room.lifecycle["phase"] not in ["loading","running"] or data.get("world_hash","") != room.lifecycle["world_hash"]: return WildOperationResult.reject(&"INVALID_WORLD_ACK")
	room.lifecycle["loaded"][actor] = true
	if room.lifecycle["loaded"].size() == room.members.size(): room.lifecycle["phase"] = "running"
	return WildOperationResult.accept()

static func reward(room: WildCoopState, actor: String, config: WildGameConfig) -> int:
	return WildExpeditionReport.reward(WildExpeditionReport.create(room.world,room.survival,actor,config,true,[],true))

## 先转移死者随身物资，再结算存活者；到期同刻死亡无成功奖励，也不复制尸体物资。
static func reconcile(room: WildCoopState, config: WildGameConfig, _catalog: WildItemCatalog) -> void:
	if not room.started: return
	for actor: String in room.members:
		if room.survival.bodies[actor].hp > 0 or room.lifecycle["dead"].has(actor): continue
		room.survival.actions.erase(actor)
		var point: Vector2 = room.world.players[actor]
		var id: String = "corpse:"+actor
		var corpse := WildInventoryContainer.new(id,"",Vector2i(maxi(12,config.backpack_grid.x),config.backpack_grid.y+6),1000)
		corpse.public_access = true
		var gear_index: int = 0
		for slot: String in WildCoopProfileRules.SLOTS:
			var container: WildInventoryContainer = room.members[actor].containers[slot]
			for item_id: String in container.placements:
				var entry: Dictionary = container.placements[item_id]
				var position: Vector2i = entry["position"] if slot == "backpack" else Vector2i(gear_index*4,config.backpack_grid.y)
				corpse.placements[item_id] = {"item":entry["item"],"position":position,"rotated":entry["rotated"] if slot == "backpack" else false}
			if slot != "backpack": gear_index += 1
			container.placements.clear()
			container.version += 1
		room.corpses[id] = corpse
		room.lifecycle["dead"][actor] = {"id":id,"x":point.x,"y":point.y,"at":room.survival.elapsed_seconds}
		WildCoopSleep.cancel(room,"成员死亡，睡眠已中断。")
	if room.survival.outcome == "running" or room.lifecycle["phase"] == "settled": return
	for actor: String in room.members:
		var won: bool = room.survival.outcome == "won" and room.survival.bodies[actor].hp > 0
		var items: Array[Dictionary] = []
		for slot: String in WildCoopProfileRules.SLOTS:
			var container: WildInventoryContainer = room.members[actor].containers[slot]
			if won:
				for entry: Dictionary in container.placements.values(): items.append({"item":entry["item"].record(),"rotated":entry["rotated"]})
			container.placements.clear()
			container.version += 1
		if room.lifecycle["offers"].get(actor,{}).get("active",false):
			var report: Dictionary = WildExpeditionReport.create(room.world,room.survival,actor,config,won,items,true)
			WildCoopDeliveries.emit_event(room,actor,"settlement",{"items":items,"won":won,"reward":WildExpeditionReport.reward(report),"report":report,"reason":"合作存活到期" if won else "合作死亡 / 全员失败"})
			room.lifecycle["offers"][actor]["active"] = false
	room.lifecycle["phase"] = "settled"
	room.lifecycle["vote"] = {}
	room.lifecycle["gifts"] = {}

static func corpse_in_reach(room: WildCoopState, actor: String, id: String) -> bool:
	for entry: Dictionary in room.lifecycle["dead"].values():
		if entry["id"] != id: continue
		var point := Vector2(entry["x"],entry["y"])
		return room.world.players[actor].distance_to(point) <= 1.5*room.world.tile_pixels and WildCombatRules.line_clear(room.world,room.world.players[actor],point)
	return false
