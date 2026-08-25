extends ProceduralWorldDatasource
class_name WorldWakePainterDatasource

const WORLD_SIZE := Vector2i(1024, 1024)
const NO_EDIT := -2

const TERRAIN_NAMES := ["Water", "Sand", "Grass", "Forest", "Mountain"]
const TERRAIN_COLORS := [
	[27, 69, 98],
	[188, 167, 112],
	[76, 122, 78],
	[38, 82, 57],
	[103, 105, 104]
]
const OUTSIDE_COLOR := [7, 11, 13]

var _continent_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _edits: Dictionary = {}
var _edit_mutex := Mutex.new()

func _init() -> void:
	_continent_noise.frequency = 0.0027
	_continent_noise.fractal_octaves = 5
	_continent_noise.fractal_gain = 0.52
	_detail_noise.frequency = 0.011
	_detail_noise.fractal_octaves = 3
	_detail_noise.fractal_gain = 0.48
	set_seed(24681357)

func set_seed(value: int) -> void:
	seed = value
	_continent_noise.seed = value
	_detail_noise.seed = value + 7919

func clear_edits() -> void:
	_edit_mutex.lock()
	_edits.clear()
	_edit_mutex.unlock()

func get_edit_count() -> int:
	_edit_mutex.lock()
	var count := _edits.size()
	_edit_mutex.unlock()
	return count

func terrain_name(terrain_id: int) -> String:
	if terrain_id < 0:
		return "Erase"
	if terrain_id >= TERRAIN_NAMES.size():
		return "Unknown"
	return TERRAIN_NAMES[terrain_id]

func paint_line(from_cell: Vector2i, to_cell: Vector2i, terrain_id: int, brush_radius: int) -> void:
	var dx := to_cell.x - from_cell.x
	var dy := to_cell.y - from_cell.y
	var steps: int = max(abs(dx), abs(dy))
	var radius := max(0, brush_radius)

	_edit_mutex.lock()
	if steps <= 0:
		_stamp_unlocked(from_cell.x, from_cell.y, terrain_id, radius)
	else:
		for i in range(steps + 1):
			var t := float(i) / float(steps)
			var x := roundi(lerpf(float(from_cell.x), float(to_cell.x), t))
			var y := roundi(lerpf(float(from_cell.y), float(to_cell.y), t))
			_stamp_unlocked(x, y, terrain_id, radius)
	_edit_mutex.unlock()

func _stamp_unlocked(cx: int, cy: int, terrain_id: int, radius: int) -> void:
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			if ox * ox + oy * oy > radius * radius:
				continue
			var x := cx + ox
			var y := cy + oy
			if x < 0 or y < 0 or x >= WORLD_SIZE.x or y >= WORLD_SIZE.y:
				continue
			var cell_key := y * WORLD_SIZE.x + x
			if terrain_id < 0:
				_edits.erase(cell_key)
			else:
				_edits[cell_key] = terrain_id

func _base_terrain(world_x: float, world_y: float) -> int:
	if world_x < 0.0 or world_y < 0.0 or world_x >= WORLD_SIZE.x or world_y >= WORLD_SIZE.y:
		return -1

	var nx := (world_x - WORLD_SIZE.x * 0.5) / (WORLD_SIZE.x * 0.5)
	var ny := (world_y - WORLD_SIZE.y * 0.5) / (WORLD_SIZE.y * 0.5)
	var edge := max(abs(nx), abs(ny))
	var edge_penalty := 0.0
	if edge > 0.67:
		edge_penalty = pow((edge - 0.67) / 0.33, 2.0) * 1.35

	var continent := _continent_noise.get_noise_2d(world_x, world_y)
	var detail := _detail_noise.get_noise_2d(world_x, world_y)
	var land := continent * 0.82 + detail * 0.22 - edge_penalty

	if land < -0.13:
		return 0
	if land < -0.035:
		return 1
	if land > 0.43:
		return 4
	if land > 0.16:
		return 3
	return 2

func get_biome_image(camera_zoomed_size: Vector2i):
	var width := max(1, camera_zoomed_size.x)
	var height := max(1, camera_zoomed_size.y)
	var buffer := PackedByteArray()
	buffer.resize(width * height * 3)

	_edit_mutex.lock()
	var edit_snapshot := _edits.duplicate()
	_edit_mutex.unlock()

	var local_zoom := max(zoom, 0.00001)
	var write_index := 0
	for py in range(height):
		var world_y := (offset.y + float(py)) / local_zoom
		var cell_y := floori(world_y)
		for px in range(width):
			var world_x := (offset.x + float(px)) / local_zoom
			var cell_x := floori(world_x)
			var terrain_id := -1

			if cell_x >= 0 and cell_y >= 0 and cell_x < WORLD_SIZE.x and cell_y < WORLD_SIZE.y:
				var cell_key := cell_y * WORLD_SIZE.x + cell_x
				terrain_id = int(edit_snapshot.get(cell_key, NO_EDIT))
				if terrain_id == NO_EDIT:
					terrain_id = _base_terrain(world_x, world_y)

			var color_bytes = OUTSIDE_COLOR if terrain_id < 0 else TERRAIN_COLORS[terrain_id]
			buffer[write_index] = color_bytes[0]
			buffer[write_index + 1] = color_bytes[1]
			buffer[write_index + 2] = color_bytes[2]
			write_index += 3

	return create_texture_from_buffer(buffer, Vector2i(width, height))
