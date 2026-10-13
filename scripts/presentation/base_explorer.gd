class_name WildBaseExplorer
extends CharacterBody2D
## 基地移动视图，只拥有局部输入与碰撞表现，不计算营养 / 货币 / 技能。

var player_id: String
var _config: WildGameConfig
var animation := WildExplorerAnimation.new()


func configure(id: String, config: WildGameConfig) -> void:
	player_id = id
	_config = config
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func face(direction: Vector2) -> void:
	if not direction.is_zero_approx():
		animation.face(direction)
		queue_redraw()


func _physics_process(delta: float) -> void:
	if _config == null:
		return
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var speed: float = _config.sprinting_speed_pixels_per_second if Input.is_action_pressed(&"sprint") else _config.walking_speed_pixels_per_second
	velocity = direction * speed
	if not direction.is_zero_approx():
		animation.face(direction)
		queue_redraw()
	var before: Vector2 = position
	move_and_slide()
	animate_motion(position - before, delta, Input.is_action_pressed(&"sprint"))


## 荒野由权威会话移动后调用；本节点停用物理处理也能同步表现，不重复执行输入。
func animate_motion(displacement: Vector2, seconds: float, fast: bool = false) -> void:
	animation.advance(displacement, seconds, fast)
	queue_redraw()


func _draw() -> void:
	# 32px 原帧包含留白，放大两倍后原脚底 y=24 对齐既有碰撞足部 y=8。
	draw_set_transform(Vector2(0, 7), 0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, 10, Color(0.03, 0.06, 0.04, 0.3))
	draw_set_transform(Vector2.ZERO)
	var image: Texture2D = WildArtLibrary.EXPLORER_WALK if animation.moving else WildArtLibrary.EXPLORER_IDLE
	draw_texture_rect_region(image, Rect2(-32, -40, 64, 64), animation.region())
