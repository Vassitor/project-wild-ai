class_name WildDataValidation
extends RefCounted
## 消息 / 存档共享的数字校验，拒绝小数数量、NaN 和错误类型。


static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func whole(value: Variant) -> bool:
	return number(value) and absf(float(value)) <= 9007199254740991.0 and float(value) == floorf(float(value))
