class_name WildUiFeedback
extends Node
## 本地界面音效与偏好；不进入领域存档或网络协议。音色由代码合成，不引入第三方音频。
var volume: float = 0.35
var _path: String
var _player: AudioStreamPlayer
var _owner: Node

func configure(owner_node: Node, profile_path: String) -> void:
	_owner = owner_node
	_path = profile_path.get_basename()+"_audio.cfg"
	var prefs := ConfigFile.new()
	if prefs.load(_path) == OK: volume = clampf(float(prefs.get_value("audio","volume",0.35)),0,1)
	_player = AudioStreamPlayer.new()
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var bytes := PackedByteArray()
	var samples: int = 1544
	bytes.resize(samples*2)
	for index: int in range(samples):
		var envelope: float = pow(1.0-index/float(samples),2)*minf(1,index/80.0)
		bytes.encode_s16(index*2,int(sin(TAU*660*index/22050.0)*envelope*7000))
	wave.data = bytes
	_player.stream = wave
	add_child(_player)
	_apply()
	_hook(_owner)
	get_tree().node_added.connect(_hook)

## 静音为零振幅；只保存本地偏好，失败时保留内存设置并返回写入错误。
func set_volume(value: float) -> Error:
	volume = clampf(value,0,1)
	_apply()
	var prefs := ConfigFile.new()
	prefs.set_value("audio","volume",volume)
	return prefs.save(_path) if not _path.is_empty() else OK

func play() -> void:
	if volume > 0 and _player != null: _player.play()

func _apply() -> void:
	if _player != null: _player.volume_db = linear_to_db(maxf(0.00001,volume))

func _hook(node: Node) -> void:
	if node != _owner and not _owner.is_ancestor_of(node): return
	if node is Button and not node.pressed.is_connected(play): node.pressed.connect(play)
	for child: Node in node.get_children(): _hook(child)
