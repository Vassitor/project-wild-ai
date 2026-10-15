class_name WildCoopGifts
extends RefCounted
## 赠送需收件人明确接受；锁定整个实例，双方在线 / 存活 / 距离与容量在接受时再校验。
static func locked(room: WildCoopState, actor: String) -> bool:
	for gift: Dictionary in room.lifecycle["gifts"].values():
		if gift["from"] == actor: return true
	return false

static func execute(room: WildCoopState, actor: String, operation: String, data: Dictionary, online: Dictionary, config: WildGameConfig, catalog: WildItemCatalog) -> WildOperationResult:
	var gifts: Dictionary = room.lifecycle["gifts"]
	if operation == "gift.offer":
		var target: String = str(data.get("target",""))
		if target == actor or not room.members.has(target) or not online.get(target,false) or room.survival.bodies[target].hp <= 0: return WildOperationResult.reject(&"INVALID_RECIPIENT")
		if locked(room,actor) or room.survival.actions.has(actor): return WildOperationResult.reject(&"ACTION_BUSY")
		var item_id: String = str(data.get("item_id",""))
		if WildInventoryOperations.find(room.members[actor],item_id).is_empty(): return WildOperationResult.reject(&"ITEM_NOT_FOUND")
		if room.world.players[actor].distance_to(room.world.players[target]) > room.world.tile_pixels*2: return WildOperationResult.reject(&"OUT_OF_REACH")
		var offered_id: String = WildStableId.create("gift")
		gifts[offered_id] = {"id":offered_id,"from":actor,"target":target,"item_id":item_id}
		return WildOperationResult.accept({"gift_id":offered_id})
	var id: String = str(data.get("gift_id",""))
	if not gifts.has(id): return WildOperationResult.reject(&"GIFT_NOT_FOUND")
	var gift: Dictionary = gifts[id]
	if operation == "gift.cancel":
		if actor not in [gift["from"],gift["target"]]: return WildOperationResult.reject(&"FORBIDDEN")
		gifts.erase(id)
		return WildOperationResult.accept()
	if operation != "gift.accept" or actor != gift["target"]: return WildOperationResult.reject(&"FORBIDDEN")
	var sender: String = gift["from"]
	if not online.get(sender,false) or room.survival.bodies[sender].hp <= 0 or room.survival.actions.has(actor): return WildOperationResult.reject(&"ACTION_BUSY")
	if room.world.players[actor].distance_to(room.world.players[sender]) > room.world.tile_pixels*2: return WildOperationResult.reject(&"OUT_OF_REACH")
	var found: Dictionary = WildInventoryOperations.find(room.members[sender],gift["item_id"])
	if found.is_empty(): return WildOperationResult.reject(&"ITEM_NOT_FOUND")
	var item: WildItemInstance = found["item"]
	if not WildInventoryOperations.insert(room.members[actor],catalog,config,item.copy()): return WildOperationResult.reject(&"NO_SPACE")
	var source: WildInventoryContainer = found["container"]
	source.placements.erase(item.instance_id)
	source.version += 1
	gifts.erase(id)
	return WildOperationResult.accept()

static func cancel_member(room: WildCoopState, actor: String) -> void:
	for id: String in room.lifecycle["gifts"].keys():
		var gift: Dictionary = room.lifecycle["gifts"][id]
		if actor in [gift["from"],gift["target"]]: room.lifecycle["gifts"].erase(id)
