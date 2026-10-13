class_name WildSessionPolicy
extends RefCounted
## 按模式决定暂停策略。合作个人菜单不改变共享世界时钟。

enum Mode { SINGLE_PLAYER, COOPERATIVE }


static func pauses_world(mode: Mode, personal_menu_open: bool, focus_lost: bool) -> bool:
	return mode == Mode.SINGLE_PLAYER and (personal_menu_open or focus_lost)
