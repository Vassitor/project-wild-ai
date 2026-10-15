class_name WildCanonicalData
extends RefCounted
## JSON 往返将整数读为 float；先规范化，跨端摘要不能因 1 / 1.0 改变。
static func normalized(value: Variant) -> Variant:
	if value is float and is_finite(value) and absf(value) <= 9007199254740991.0 and floorf(value) == value: return int(value)
	# JSON 解析器可能造成一个 ULP 的差异；协议小数采用 6 位十进制精度，领域值本身不改写。
	if value is float and is_finite(value):
		var decimal: String = "%.6f" % value
		if floorf(decimal.to_float()) == decimal.to_float(): return int(decimal.to_float())
		return {"decimal":decimal}
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = normalized(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value: result.append(normalized(entry))
		return result
	return value

static func digest(value: Variant) -> String:
	return JSON.stringify(normalized(value),"",true,true).sha256_text()
