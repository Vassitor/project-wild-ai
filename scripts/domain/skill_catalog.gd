class_name WildSkillCatalog
extends Resource
## 九个稳定分支、27 节点与规则参数；永久实例不写回此共享定义。
const BRANCHES: Array[String] = ["gathering","logging","fire","fishing","hunting","trap","building","cooking","healing"]
@export var experience_per_point: int = 100
@export var point_costs: PackedInt32Array = PackedInt32Array([1,2,3])
@export var training_costs: PackedInt32Array = PackedInt32Array([300,600,1200])
@export var experience_rewards: Dictionary = {"gathering":4,"logging":8,"fire":4,"fishing":8,"hunting":12,"trap":8,"building":8,"cooking":4,"healing":6}
@export var branch_names: Dictionary = {"gathering":"采集","logging":"伐木","fire":"取火","fishing":"捕鱼","hunting":"狩猎","trap":"陷阱","building":"建造","cooking":"料理","healing":"医疗"}
@export var descriptions: Dictionary = {
	"gathering":["植物辨识提示","植物产出 +1","采集耗时 −25%"],"logging":["伐木耗时 −15%","木材产出 +1","工具磨损 −25%"],
	"fire":["钻木成功率 +20 百分点","燃料时长 +25%","取火耗时 −50%"],"fishing":["捕鱼成功率 +10 百分点","双份捕鱼：耗饵 2、独立判定","捕鱼耗时 −25%"],
	"hunting":["简弓 / 箭制作（攻击使用待 P6）","猎物 / 栖息地提示（动态足迹待 P6）","狩猎掉肉 +1（P6）"],"trap":["小型套索","大型陷阱","捕获率 +15 百分点"],
	"building":["营地升级至 2","料理台 / 皮甲制作","营地升级至 3"],"cooking":["炖食","熟食营养 ×1.15","熟食保质期 ×1.5"],"healing":["草药药剂制作","治疗额外缩短 2 小时","疗养回血 ×1.25"]}
@export var logging_duration_multiplier: float = 0.85
@export var gathering_duration_multiplier: float = 0.75
@export var logging_wear_multiplier: float = 0.75
@export var fire_success_bonus: float = 0.2
@export var fuel_multiplier: float = 1.25
@export var fire_duration_multiplier: float = 0.5
@export var fishing_success_bonus: float = 0.1
@export var fishing_duration_multiplier: float = 0.75
@export var trap_success_bonus: float = 0.15
@export var cooked_nutrition_multiplier: float = 1.15
@export var cooked_shelf_life_multiplier: float = 1.5
@export var medicine_bonus_seconds: float = 7200
@export var healing_multiplier: float = 1.25
@export var maximum_build_experience_per_recipe: int = 3

func validate() -> bool:
	for field: Dictionary in get_property_list():
		if field["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and field["type"] == TYPE_FLOAT:
			var value: float = get(field["name"])
			if not is_finite(value) or value <= 0: return false
	if experience_per_point <= 0 or point_costs.size() != 3 or training_costs.size() != 3 or maximum_build_experience_per_recipe < 1: return false
	for value: int in point_costs:
		if value <= 0: return false
	for value: int in training_costs:
		if value <= 0: return false
	for branch: String in BRANCHES:
		if not experience_rewards.has(branch) or not WildDataValidation.whole(experience_rewards[branch]) or experience_rewards[branch] <= 0 or not descriptions.get(branch,null) is Array or descriptions[branch].size() != 3: return false
	return cooked_nutrition_multiplier >= 1 and cooked_nutrition_multiplier <= 2 and cooked_shelf_life_multiplier >= 1 and cooked_shelf_life_multiplier <= 2 and fire_success_bonus <= 0.4 and fishing_success_bonus <= 0.3 and trap_success_bonus <= 0.6
