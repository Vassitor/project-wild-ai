class_name WildExpeditionText
extends RefCounted
## 快照到中文说明的纯投影。检查仅供参考，不替代会话的权威操作校验。
static func checklist(view: Dictionary, config: WildGameConfig, content: WildSurvivalContent) -> String:
	var counts: Dictionary = {}
	for slot: String in WildCoopProfileRules.SLOTS:
		for entry: Dictionary in view.get("containers",{}).get(slot,{}).get("entries",[]):
			var item: Dictionary = entry["item"]
			if item.get("durability",100) > 0: counts[item["item_id"]] = int(counts.get(item["item_id"],0))+int(item["quantity"])
	var food: int = 0
	for kind: String in content.foods: food += int(counts.get(kind,0))
	var notes: PackedStringArray = []
	notes.append("刀 / 斧：%s" % ("已携带" if counts.get("knife",0)+counts.get("axe",0) > 0 else "未携带；落枝仍可徒手采集"))
	notes.append("水壶：%s" % ("已携带" if counts.get("bottle",0)>0 else "未携带；找到清泉可直接饮水"))
	notes.append("食物 %d 份 · 绷带 %d · 钓具 %s" % [food,counts.get("bandage",0),"有" if counts.get("fishing_kit",0)>0 else "无"])
	notes.append("%s；没有件数上限。" % ("已超轻装线，移动会变慢" if view.get("carried_weight_kg",0)>config.soft_weight_limit_kg else "轻装范围内"))
	notes.append("目标 %.0f 日 · 上述提醒不阻止出发。F1 查看生存手册。" % (config.target_survival_hours/24.0))
	return "\n".join(notes)

## elapsed 是已模拟及排队的游戏秒；不足一分钟向上取整，胜负仍由权威模拟决定。
static func countdown(elapsed: float, config: WildGameConfig) -> String:
	var minutes: int = ceili(maxf(0,config.target_survival_hours*3600-elapsed)/60)
	return "距返航 %d 日 %02d:%02d" % [floori(float(minutes)/1440),floori(float(minutes)/60)%24,minutes%60]

## 只显示已持久化结果；旧收据没有明细时保留原总额，不重算历史奖励。
static func result(summary: Dictionary, config: WildGameConfig) -> String:
	if summary.is_empty(): return "尚无已结算任务。"
	var lines: PackedStringArray = ["%s · 生存 %.1f 小时" % [summary.get("reason","本局结束"),summary.get("elapsed_seconds",0)/3600.0],"获得货币 %d" % summary.get("reward",0)]
	var report: Dictionary = summary.get("report",{})
	if not report.is_empty():
		lines.append("基础 %d + 探索 %d + 活动 %d" % [report["base"],report["exploration"],report["activity"]])
		var names: PackedStringArray = []
		for kind: String in report["activities"]: names.append(config.skill_rules.branch_names.get(kind,kind))
		lines.append("有效活动：%s" % ("、".join(names) if not names.is_empty() else "无"))
		lines.append("返航物资 %d 组 / %d 件" % [report["returned_stacks"],report["returned_units"]])
	lines.append("随身物资返仓，公共箱、尸体剩余与营地产出不自动带回。" if summary.get("won",false) else "本局随身物资失去；基地货币、仓库与永久技能保留。")
	if summary.get("pending_count",0)>0: lines.append("结算时有 %d 组待领取；在基地仓库腾出空间后领取。" % summary["pending_count"])
	return "\n".join(lines)
