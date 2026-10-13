class_name WildSkillPanel
extends PanelContainer
## 只读技能树与学习意图；房主确认后刷新，不在 UI 修改经验 / 货币。
signal close_requested
var _session: WildLocalSession
var _actor: String
var _config: WildGameConfig
var _rows: VBoxContainer
var _status: Label
var _summary: Label
var _pending: String = ""
var _signature: String = ""
var _elapsed: float = 0

func configure(session: WildLocalSession, config: WildGameConfig) -> void:
	_session = session
	_config = config
	_session.command_resolved.connect(_resolved)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102219")
	style.set_content_margin_all(20)
	add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	add_child(column)
	_summary = Label.new()
	column.add_child(_summary)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 365
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation",14)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var close := Button.new()
	close.text = "关闭 · K / Esc"
	close.custom_minimum_size.y = 38
	close.pressed.connect(func() -> void: close_requested.emit())
	column.add_child(close)

func reset_pending() -> void:
	_pending = ""

func open(actor: String) -> void:
	_actor = actor
	visible = true
	_signature = ""
	_status.text = "每分支 100 经验获 1 点；依序解锁，点数 1 / 2 / 3，基地钱学 300 / 600 / 1200。"
	refresh()

func _process(delta: float) -> void:
	if not visible: return
	_elapsed += delta
	if _elapsed >= 0.5:
		_elapsed = 0
		refresh()

func refresh() -> void:
	var view: Dictionary = _session.base_snapshot(_actor)
	if not view.has("skills"): return
	var skills: Dictionary = view["skills"]
	var money: bool = view.get("can_train",false) if _session.is_cooperative() else view.get("phase",-1) == WildRunFlow.Phase.BASE
	var signature: String = JSON.stringify(skills)+str(view.get("currency",0))+str(money)+_pending
	if signature == _signature: return
	_signature = signature
	_summary.text = "合作验证技能 · K   |   独立验证资金 %d\n本房间成长由房主保存；出发前可钱学。跨端基地成长将在 P6.5 接入。" % view.get("currency",0) if _session.is_cooperative() else "永久生存技能 · K   |   基地货币 %d\n有效实践保留经验与点数；失败不失去成长。" % view.get("currency",0)
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for branch: String in WildSkillCatalog.BRANCHES:
		var title := Label.new()
		title.text = "%s · 经验 %d · 可用点数 %d · 等级 %d / 3" % [_config.skill_rules.branch_names[branch],skills["experience"][branch],skills["points"][branch],skills["levels"][branch]]
		title.add_theme_font_size_override("font_size",20)
		_rows.add_child(title)
		for tier: int in range(1,4):
			var row := HBoxContainer.new()
			_rows.add_child(row)
			var learned: bool = int(skills["levels"][branch]) >= tier
			var can_learn: bool = int(skills["levels"][branch])+1 == tier and _pending.is_empty()
			var label := Label.new()
			label.text = "%d · %s%s" % [tier,_config.skill_rules.descriptions[branch][tier-1]," ✓" if learned else ""]
			label.add_theme_font_size_override("font_size",16)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var unlock := Button.new()
			unlock.name = "%s_%d_points" % [branch,tier]
			unlock.text = "%d 点解锁" % _config.skill_rules.point_costs[tier-1]
			unlock.disabled = not can_learn or skills["points"][branch] < _config.skill_rules.point_costs[tier-1]
			unlock.pressed.connect(_learn.bind(branch,tier,false))
			row.add_child(unlock)
			if money:
				var train := Button.new()
				train.name = "%s_%d_train" % [branch,tier]
				train.text = "学习 %d" % _config.skill_rules.training_costs[tier-1]
				train.disabled = not can_learn or view["currency"] < _config.skill_rules.training_costs[tier-1]
				train.pressed.connect(_learn.bind(branch,tier,true))
				row.add_child(train)

func _learn(branch: String, tier: int, money: bool) -> void:
	if not _pending.is_empty(): return
	var command := WildGameCommand.new(_actor,&"skill.train" if money else &"skill.unlock",{"branch":branch,"tier":tier})
	var result: WildOperationResult = _session.submit(command)
	if result.code == &"PENDING": _pending = result.payload["request_id"]
	else: _status.text = "技能已学习。" if result.successful else WildErrorMessages.describe(result.code)
	refresh()

func _resolved(request: String, result: WildOperationResult) -> void:
	if request != _pending: return
	_pending = ""
	_status.text = "房主确认技能已解锁。" if result.successful else WildErrorMessages.describe(result.code)
	refresh()
