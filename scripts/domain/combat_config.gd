class_name WildCombatConfig
extends Resource
## P6 只读动物 / 武器规则。伤害和冷却为现实单位，刷新 / 足迹寿命为游戏秒。
@export var animals: Dictionary = {
	"rabbit":{"initial":20,"maximum":24,"refill":4,"hp":20.0,"damage":0.0,"cooldown":1.0,"alert":6.0,"speed":64.0,"meat":1,"hide":1},
	"boar":{"initial":6,"maximum":8,"refill":1,"hp":70.0,"damage":15.0,"cooldown":1.5,"alert":4.0,"speed":56.0,"meat":3,"hide":2},
	"wolf":{"initial":3,"maximum":4,"refill":1,"hp":50.0,"damage":12.0,"cooldown":1.2,"alert":8.0,"speed":80.0,"meat":2,"hide":1}}
@export var weapons: Dictionary = {"knife":{"damage":14.0,"cooldown":0.7,"stamina":4.0},"axe":{"damage":22.0,"cooldown":1.0,"stamina":7.0},"bow":{"damage":30.0,"cooldown":1.0,"stamina":6.0}}
@export var melee_range_tiles: float = 1.0
@export var arrow_range_tiles: float = 8.0
@export var arrow_speed_tiles_per_second: float = 8.0
@export var leash_tiles: float = 16.0
@export var wander_tiles: float = 4.0
@export var safe_radius_tiles: float = 6.0
@export var safe_seconds: float = 21600.0
@export var refill_seconds: float = 86400.0
@export var track_lifetime_seconds: float = 21600.0
@export var maximum_tracks: int = 128
@export var sleep_disturbance_per_hour: float = 0.2

func validate() -> bool:
	for property: Dictionary in get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and property["type"] == TYPE_FLOAT:
			if not is_finite(float(get(property["name"]))): return false
	for kind: String in ["rabbit","boar","wolf"]:
		if not animals.has(kind): return false
		for key: String in ["initial","maximum","refill"]:
			if not WildDataValidation.whole(animals[kind].get(key,null)) or animals[kind][key] < 1: return false
		if animals[kind]["maximum"] < animals[kind]["initial"]: return false
		for key: String in ["hp","cooldown","alert","speed"]:
			if not WildDataValidation.number(animals[kind].get(key,null)) or animals[kind][key] <= 0: return false
		if not WildDataValidation.number(animals[kind].get("damage",null)) or animals[kind]["damage"] < 0: return false
		for key: String in ["meat","hide"]:
			if not WildDataValidation.whole(animals[kind].get(key,null)) or animals[kind][key] < 1: return false
	for weapon: String in ["knife","axe","bow"]:
		for key: String in ["damage","cooldown","stamina"]:
			if not WildDataValidation.number(weapons.get(weapon,{}).get(key,null)) or weapons[weapon][key] <= 0: return false
	return melee_range_tiles > 0 and arrow_range_tiles > 0 and arrow_speed_tiles_per_second > 0 and wander_tiles > 0 and leash_tiles > wander_tiles and safe_radius_tiles > 0 and safe_seconds >= 0 and refill_seconds > 0 and track_lifetime_seconds > 0 and maximum_tracks > 0 and sleep_disturbance_per_hour >= 0 and sleep_disturbance_per_hour <= 1
