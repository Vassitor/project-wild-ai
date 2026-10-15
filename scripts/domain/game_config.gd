class_name WildGameConfig
extends Resource
## 静态规则配置。数值单位明确，运行状态不得写回这个共享 Resource。

@export var design_version: String = "0.2"
@export var save_version: int = 1
@export var generator_version: int = 1
@export var protocol_version: int = 1

@export_group("Time")
@export var game_seconds_per_real_second: float = 120.0
@export var simulation_step_seconds: float = 60.0
@export var target_survival_hours: float = 168.0

@export_group("Inventory")
@export var backpack_grid: Vector2i = Vector2i(8, 6)
@export var backpack_capacity_l: float = 30.0
@export var backpack_empty_weight_kg: float = 0.8
@export var warehouse_grid: Vector2i = Vector2i(12, 10)
@export var warehouse_capacity_l: float = 120.0
@export var camp_storage_grid: Vector2i = Vector2i(6, 6)
@export var camp_storage_capacity_l: float = 40.0
@export var soft_weight_limit_kg: float = 18.0
@export var hard_weight_limit_kg: float = 30.0
@export var maximum_weight_slowdown: float = 0.35
@export var maximum_weight_stamina_penalty: float = 0.75

@export_group("Body")
@export var health_rules: WildHealthConfig = WildHealthConfig.new()
@export var skill_rules: WildSkillCatalog = WildSkillCatalog.new()
@export var combat_rules: WildCombatConfig = WildCombatConfig.new()
@export var initial_stat_value: float = 100.0
## 顺序固定为碳水、脂肪、蛋白质、矿物质、维生素；单位为每游戏小时。
@export var nutrition_consumption_per_hour: PackedFloat32Array = PackedFloat32Array([4.0, 1.5, 2.0, 1.2, 1.0])
@export var water_consumption_per_hour: float = 4.0
@export var sleeping_water_consumption_per_hour: float = 2.0
@export var working_water_consumption_per_hour: float = 6.0
@export var hydration_per_half_litre: float = 25.0
@export var sprint_stamina_per_game_minute: float = 4.0
@export var idle_stamina_recovery_per_game_minute: float = 2.0
@export var resting_stamina_recovery_per_game_minute: float = 4.0

@export_group("World and Movement")
@export var wilderness_grid: Vector2i = Vector2i(128, 128)
@export var terrain_tile_pixels: int = 32
@export var generation_max_attempts: int = 5
@export var terrain_noise_frequency: float = 0.035
@export var minimum_connected_land_ratio: float = 0.8
@export var spawn_food_path_tiles: int = 8
@export var spawn_wood_path_tiles: int = 10
@export var spawn_water_path_tiles: int = 12
@export var exploration_autosave_seconds: float = 120.0
@export var walking_speed_pixels_per_second: float = 96.0
@export var sprinting_speed_pixels_per_second: float = 144.0
@export var exhausted_speed_pixels_per_second: float = 72.0

@export_group("Economy and Cooperation")
@export var starting_currency: int = 600
@export var success_base_reward: int = 600
@export var maximum_cooperative_players: int = 4
@export var default_network_port: int = 7000


## 在启动时拒绝无效配置；不默默纠正会改变玩法的参数。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if combat_rules == null or not combat_rules.validate(): errors.append("动物与武器配置无效。")
	if skill_rules == null or not skill_rules.validate(): errors.append("技能节点、成本或经验配置无效。")
	if health_rules == null or not health_rules.validate(): errors.append("身体阈值、时间、概率或恢复系数无效。")
	if game_seconds_per_real_second <= 0.0 or simulation_step_seconds <= 0.0 or target_survival_hours <= 0.0:
		errors.append("时间参数必须大于零。")
	if soft_weight_limit_kg < 0.0 or hard_weight_limit_kg <= soft_weight_limit_kg:
		errors.append("硬负重上限必须高于软上限。")
	if nutrition_consumption_per_hour.size() != 5:
		errors.append("营养配置必须恰好包含五项。")
	for grid: Vector2i in [backpack_grid, warehouse_grid, camp_storage_grid, wilderness_grid]:
		if grid.x <= 0 or grid.y <= 0:
			errors.append("网格宽高必须大于零。")
	if backpack_capacity_l <= 0.0 or warehouse_capacity_l <= 0.0 or camp_storage_capacity_l <= 0.0:
		errors.append("容器体积必须大于零。")
	if maximum_cooperative_players < 2 or maximum_cooperative_players > 4:
		errors.append("首版合作人数上限必须在 2–4 之间。")
	if wilderness_grid.x < 64 or wilderness_grid.y < 64 or wilderness_grid.x > 256 or wilderness_grid.y > 256 or terrain_tile_pixels != 32:
		errors.append("生成器版本 1 支持 64–256 格地图与 32 px 地形格。")
	if generation_max_attempts < 1 or generation_max_attempts > 5 or terrain_noise_frequency <= 0.0 or minimum_connected_land_ratio < 0.8 or minimum_connected_land_ratio > 1.0:
		errors.append("生成重试、噪声或连通性配置无效。")
	if spawn_food_path_tiles < 4 or spawn_wood_path_tiles < 4 or spawn_water_path_tiles < 4 or exploration_autosave_seconds <= 0.0:
		errors.append("出生路径或自动保存配置无效。")
	return errors
