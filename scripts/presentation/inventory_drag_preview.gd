class_name WildInventoryDragPreview
extends Control
## 只持有本次拖拽字典，R 旋转后自动更新图形，由 Godot 在拖拽结束时销毁。

var _data: Dictionary
var _definition: WildItemDefinition


func configure(data: Dictionary, catalog: WildItemCatalog) -> void:
	_data = data
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_definition = catalog.find(StringName(data["definition_id"]))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _definition == null:
		return
	var dimensions: Vector2i = Vector2i(_definition.grid_size.y, _definition.grid_size.x) if _data["rotated"] else _definition.grid_size
	var bounds := Rect2(Vector2.ZERO, Vector2(dimensions) * 32)
	draw_rect(bounds, Color(_definition.color, 0.8))
	draw_rect(bounds, Color("f1d493"), false, 2)
	if not WildArtLibrary.draw_icon(self, _definition.item_id, bounds, _data["rotated"]):
		draw_string(get_theme_font("font", "Label"), Vector2(5, 22), _definition.display_name.left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("ffffff"))
