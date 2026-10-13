class_name WildExplorerAnimation
extends RefCounted
## 人物表现状态：只接收实际位移与现实秒，不读取输入、库存、身体或节点路径。
## NinjaGreen 每格 32px；四列依次下 / 上 / 左 / 右，四行动作帧沿纵向排列。

const FRAME_PIXELS: int = 32
const FRAME_COUNT: int = 4
const IDLE_FPS: float = 4.0
const WALK_FPS: float = 10.0
const FAST_WALK_FPS: float = 14.0
var direction_index: int = 0
var moving: bool = false
var elapsed_seconds: float = 0.0


## 朝向优先取较大的轴；零向量保留最后朝向，斜向相等时取纵向。
func face(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	if absf(direction.x) > absf(direction.y):
		direction_index = 3 if direction.x > 0 else 2
	else:
		direction_index = 0 if direction.y > 0 else 1


## 根据实际位移判断行走；顶墙时回到待机。暂停时调用方不推进本接口。
func advance(actual_displacement: Vector2, seconds: float, fast: bool = false) -> void:
	var next_moving: bool = not actual_displacement.is_zero_approx()
	if moving != next_moving:
		elapsed_seconds = 0.0
	moving = next_moving
	face(actual_displacement)
	var fps: float = (FAST_WALK_FPS if fast else WALK_FPS) if moving else IDLE_FPS
	elapsed_seconds = fmod(elapsed_seconds + maxf(0.0, seconds) * fps, float(FRAME_COUNT))


## 返回原图像素区域；固定四帧循环避免越出方向列或相邻动作。
func region() -> Rect2:
	return Rect2(direction_index * FRAME_PIXELS, floori(elapsed_seconds) * FRAME_PIXELS, FRAME_PIXELS, FRAME_PIXELS)
