class_name WildDurableStateStore
extends WildBaseStateStore
## 完整事务日志先写，再原子提交摘要头，最后更新可读主档。
## 提交头是唯一持久化边界；主档损坏可从同一次提交的完整日志恢复，绝不回退旧物资快照。
var _journal: WildBaseStateStore
var _head: WildBaseStateStore
## 测试可注入阶段失败；正式组合根不设置此回调。
var stage_check: Callable
## 只缓存已解析 / 已由本实例提交的字节摘要；每次仍重新读取主档和提交头核对。
var _validated_hash: String = ""

func _init(path: String) -> void:
	super(path)
	_journal = WildBaseStateStore.new(path+".journal")
	_head = WildBaseStateStore.new(path+".commit")

func load_records() -> WildOperationResult:
	if not FileAccess.file_exists(_path+".commit"):
		return WildOperationResult.reject(&"JOURNAL_INVALID") if FileAccess.file_exists(_path+".journal") else super.load_records()
	var head: Dictionary = _head.read_primary()
	if head.get("version",0) != 1 or not WildDataValidation.whole(head.get("sequence",null)) or head["sequence"] < 1 or not head.get("hash",null) is String: return WildOperationResult.reject(&"JOURNAL_INVALID")
	var main_json: String = FileAccess.get_file_as_string(_path) if FileAccess.file_exists(_path) else ""
	if main_json.sha256_text() == head["hash"]:
		var parser := JSON.new()
		if parser.parse(main_json) == OK and parser.data is Dictionary:
			_validated_hash = head["hash"]
			return WildOperationResult.accept({"exists":true,"primary":parser.data,"backup":{},"json":main_json})
	var records: Dictionary = _journal.load_records().payload
	for key: String in ["primary","backup"]:
		var journal: Dictionary = records[key]
		if journal.get("sequence",-1) == head["sequence"] and journal.get("data_json",null) is String and journal["data_json"].sha256_text() == head["hash"]:
			var parser := JSON.new()
			if parser.parse(journal["data_json"]) == OK and parser.data is Dictionary:
				_validated_hash = head["hash"]
				return WildOperationResult.accept({"exists":true,"primary":parser.data,"backup":{},"recovered_journal":true,"json":journal["data_json"]})
	return WildOperationResult.reject(&"JOURNAL_INVALID")

func save_record(data: Dictionary, preserve_backup: bool = false) -> WildOperationResult:
	var old_head: Dictionary = _head.read_primary()
	var sequence: int = int(old_head.get("sequence",0))+1
	if FileAccess.file_exists(_path+".commit") and old_head.get("version",0) != 1: return WildOperationResult.reject(&"JOURNAL_INVALID")
	# 重试前先修复上一完整提交的主档，避免连续失败覆盖唯一有效日志备份。
	if FileAccess.file_exists(_path+".commit"):
		if not WildDataValidation.whole(old_head.get("sequence",null)) or old_head["sequence"] < 1 or not old_head.get("hash",null) is String: return WildOperationResult.reject(&"JOURNAL_INVALID")
		# 正常连续提交只需核对原样字节摘要；不必每半秒解析上一份完整世界再丢弃。
		# 摘要不匹配才进入原恢复路径，完整日志和重复失败的保护边界不变。
		var previous_json: String = FileAccess.get_file_as_string(_path) if FileAccess.file_exists(_path) else ""
		if _validated_hash != old_head["hash"] or previous_json.is_empty() or previous_json.sha256_text() != old_head["hash"]:
			var previous: WildOperationResult = load_records()
			if not previous.successful: return previous
			var repaired: WildOperationResult = _write_primary(previous.payload["json"],false)
			if not repaired.successful: return repaired
	if not _allowed("journal"): return WildOperationResult.reject(&"SAVE_FAILED")
	# 日志内嵌整份 JSON；去掉展示缩进可减少二次转义、磁盘量和主线程阻塞。
	# 仍保留完整浮点精度，摘要继续针对原样字节，旧的缩进档案可原样恢复。
	var data_json: String = JSON.stringify(data,"",true,true)
	var journal: WildOperationResult = _journal.save_record({"sequence":sequence,"data_json":data_json},false)
	if not journal.successful: return journal
	if not _allowed("commit"): return WildOperationResult.reject(&"SAVE_FAILED")
	# 旧提交头从不用于自动恢复，避免为无效的头备份再做一次同步复制。
	var committed: WildOperationResult = _head.save_record({"version":1,"sequence":sequence,"hash":data_json.sha256_text()},true)
	if not committed.successful: return committed
	_validated_hash = data_json.sha256_text()
	# 摘要头落盘后已经提交；主档替换失败仍提交内存，由完整日志恢复。
	var primary: WildOperationResult = _write_primary(data_json,preserve_backup) if _allowed("primary") else WildOperationResult.reject(&"SAVE_FAILED")
	return WildOperationResult.accept({"primary_repair_pending":not primary.successful})

func _allowed(stage: String) -> bool:
	return not stage_check.is_valid() or bool(stage_check.call(stage))

## 原样写日志中的 JSON；恢复时重序列化 float 会改变摘要，不能用领域对象重建提交内容。
func _write_primary(data_json: String, preserve_backup: bool) -> WildOperationResult:
	var absolute: String = ProjectSettings.globalize_path(_path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK: return WildOperationResult.reject(&"SAVE_FAILED")
	var file := FileAccess.open(absolute+".tmp",FileAccess.WRITE)
	if file == null: return WildOperationResult.reject(&"SAVE_FAILED")
	file.store_string(data_json)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK: return WildOperationResult.reject(&"SAVE_FAILED")
	if FileAccess.file_exists(absolute) and not preserve_backup and DirAccess.copy_absolute(absolute,absolute+".bak") != OK: return WildOperationResult.reject(&"SAVE_FAILED")
	return WildOperationResult.accept() if DirAccess.rename_absolute(absolute+".tmp",absolute) == OK else WildOperationResult.reject(&"SAVE_FAILED")
