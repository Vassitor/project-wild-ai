class_name WildWorldTiles
extends RefCounted
## CC0 地形图集适配；起始坐标沿用 P2，水帧向下扩展；不参与种子、通行或资源规则。

static func create_set() -> TileSet:
	var atlas := TileSetAtlasSource.new()
	atlas.texture = WildArtLibrary.TERRAIN
	atlas.texture_region_size = Vector2i(32, 32)
	for terrain: int in range(3):
		for variant: int in range(4):
			var cell := Vector2i(variant, terrain)
			atlas.create_tile(cell)
			if terrain == WildWorldData.Terrain.WATER:
				# 水的四帧纵向排列，同步播放只改变纹理，不推进世界模拟时间。
				atlas.set_tile_animation_columns(cell, 1)
				atlas.set_tile_animation_frames_count(cell, 4)
				atlas.set_tile_animation_speed(cell, 5.0)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(32, 32)
	tiles.add_source(atlas, 0)
	return tiles
