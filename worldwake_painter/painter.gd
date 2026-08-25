extends Control

const WorldMapScript = preload("res://addons/procedural_world_map/worldmap.gd")
const PainterDatasource = preload("res://worldwake_painter/painter_datasource.gd")

const WORLD_SIZE := Vector2i(1024, 1024)

var worldmap
var datasource
var brush_terrain := 2
var brush_radius := 3
var painting := false
var panning := false
var last_paint_cell := Vector2i.ZERO
var pending_pan_pixels := Vector2.ZERO
var refresh_queued := false
var fps_label: Label
var cursor_label: Label
var brush_label: Label
var active_label: Label
var stats_accumulator := 0.0

func _ready() -> void:
	_build_ui()
	await get_tree().process_frame
	_sync_camera_size()
	_fit_world()

func _process(delta: float) -> void:
	if pending_pan_pixels != Vector2.ZERO:
		worldmap.coordinates -= pending_pan_pixels / max(worldmap.zoom, 0.0001)
		pending_pan_pixels = Vector2.ZERO
		refresh_queued = false
	elif refresh_queued:
		worldmap.refresh()
		refresh_queued = false

	stats_accumulator += delta
	if stats_accumulator >= 0.25:
		stats_accumulator = 0.0
		fps_label.text = "%d FPS   |   zoom %.2fx   |   %d painted cells" % [
			int(Engine.get_frames_per_second()),
			worldmap.zoom,
			datasource.get_edit_count()
		]

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("070b0d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var root_layout := VBoxContainer.new()
	root_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layout.add_theme_constant_override("separation", 0)
	add_child(root_layout)

	var topbar := PanelContainer.new()
	topbar.custom_minimum_size = Vector2(0, 54)
	topbar.add_theme_stylebox_override("panel", _panel_style(Color("11181c"), Color("27343a")))
	root_layout.add_child(topbar)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 14)
	top_margin.add_theme_constant_override("margin_right", 14)
	top_margin.add_theme_constant_override("margin_top", 8)
	top_margin.add_theme_constant_override("margin_bottom", 8)
	topbar.add_child(top_margin)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 14)
	top_margin.add_child(top_row)

	var title := Label.new()
	title.text = "WORLDWAKE PAINTER  ·  GODOT PROTOTYPE"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("d8e0e3"))
	top_row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)

	fps_label = Label.new()
	fps_label.text = "— FPS"
	fps_label.add_theme_color_override("font_color", Color("8fa3aa"))
	top_row.add_child(fps_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root_layout.add_child(body)

	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(235, 0)
	sidebar.add_theme_stylebox_override("panel", _panel_style(Color("0d1316"), Color("27343a")))
	body.add_child(sidebar)

	var side_margin := MarginContainer.new()
	side_margin.add_theme_constant_override("margin_left", 14)
	side_margin.add_theme_constant_override("margin_right", 14)
	side_margin.add_theme_constant_override("margin_top", 14)
	side_margin.add_theme_constant_override("margin_bottom", 14)
	sidebar.add_child(side_margin)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 9)
	side_margin.add_child(side)

	var tools_header := Label.new()
	tools_header.text = "PAINT TERRAIN"
	tools_header.add_theme_font_size_override("font_size", 15)
	tools_header.add_theme_color_override("font_color", Color("c9d2d5"))
	side.add_child(tools_header)

	active_label = Label.new()
	active_label.text = "Active: Grass"
	active_label.add_theme_color_override("font_color", Color("8fa3aa"))
	side.add_child(active_label)

	var palette_group := ButtonGroup.new()
	for terrain_id in range(5):
		var button := Button.new()
		button.text = datasource_name_for_id(terrain_id)
		button.toggle_mode = true
		button.button_group = palette_group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_terrain.bind(terrain_id))
		if terrain_id == brush_terrain:
			button.button_pressed = true
		side.add_child(button)

	var erase_button := Button.new()
	erase_button.text = "Erase override"
	erase_button.toggle_mode = true
	erase_button.button_group = palette_group
	erase_button.pressed.connect(_select_terrain.bind(-1))
	side.add_child(erase_button)

	var divider1 := HSeparator.new()
	side.add_child(divider1)

	brush_label = Label.new()
	brush_label.text = "Brush radius: %d" % brush_radius
	side.add_child(brush_label)

	var brush_slider := HSlider.new()
	brush_slider.min_value = 0
	brush_slider.max_value = 16
	brush_slider.step = 1
	brush_slider.value = brush_radius
	brush_slider.value_changed.connect(_on_brush_changed)
	side.add_child(brush_slider)

	var fit_button := Button.new()
	fit_button.text = "Fit whole world"
	fit_button.pressed.connect(_fit_world)
	side.add_child(fit_button)

	var clear_button := Button.new()
	clear_button.text = "Clear painted edits"
	clear_button.pressed.connect(_clear_edits)
	side.add_child(clear_button)

	var divider2 := HSeparator.new()
	side.add_child(divider2)

	var controls_header := Label.new()
	controls_header.text = "CONTROLS"
	controls_header.add_theme_font_size_override("font_size", 14)
	side.add_child(controls_header)

	var help := Label.new()
	help.text = "Left drag  ·  paint\nRight / middle drag  ·  pan\nMouse wheel  ·  zoom\n\nThe map intentionally drops to a fast low-res render while moving, then sharpens after you stop."
	help.add_theme_color_override("font_color", Color("899aa1"))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(help)

	var side_spacer := Control.new()
	side_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(side_spacer)

	cursor_label = Label.new()
	cursor_label.text = "world: —"
	cursor_label.add_theme_color_override("font_color", Color("71858d"))
	side.add_child(cursor_label)

	var map_panel := PanelContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_theme_stylebox_override("panel", _panel_style(Color("070b0d"), Color("27343a")))
	body.add_child(map_panel)

	datasource = PainterDatasource.new()
	worldmap = WorldMapScript.new()
	worldmap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	worldmap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	worldmap.mouse_filter = Control.MOUSE_FILTER_STOP
	worldmap.focus_mode = Control.FOCUS_ALL
	worldmap.incremental_quality = true
	worldmap.resolutions = [1, 2, 4, 8, 16]
	worldmap.fast_resolution_index = 4
	worldmap.refresh_timeout = 0.28
	worldmap.coordinates = Vector2(WORLD_SIZE) * 0.5
	worldmap.zoom = 0.75
	worldmap.datasource = datasource
	worldmap.gui_input.connect(_on_map_gui_input)
	worldmap.resized.connect(_on_map_resized)
	worldmap.mouse_exited.connect(_on_map_mouse_exited)
	map_panel.add_child(worldmap)

func _panel_style(background_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	return style

func datasource_name_for_id(terrain_id: int) -> String:
	match terrain_id:
		0: return "Water"
		1: return "Sand"
		2: return "Grass"
		3: return "Forest"
		4: return "Mountain"
		_: return "Erase"

func _select_terrain(terrain_id: int) -> void:
	brush_terrain = terrain_id
	active_label.text = "Active: %s" % datasource_name_for_id(terrain_id)

func _on_brush_changed(value: float) -> void:
	brush_radius = int(value)
	brush_label.text = "Brush radius: %d" % brush_radius

func _clear_edits() -> void:
	datasource.clear_edits()
	refresh_queued = true

func _on_map_resized() -> void:
	call_deferred("_sync_camera_size")

func _sync_camera_size() -> void:
	if not worldmap or worldmap.size.x < 32 or worldmap.size.y < 32:
		return
	var target := Vector2i(max(64, roundi(worldmap.size.x)), max(64, roundi(worldmap.size.y)))
	if worldmap.camera_size != target:
		worldmap.camera_size = target

func _fit_world() -> void:
	if not worldmap or worldmap.size.x < 32 or worldmap.size.y < 32:
		return
	var fit_zoom := min(worldmap.size.x / float(WORLD_SIZE.x), worldmap.size.y / float(WORLD_SIZE.y)) * 0.92
	worldmap.zoom = clamp(fit_zoom, 0.05, 32.0)
	worldmap.coordinates = Vector2(WORLD_SIZE) * 0.5

func _screen_to_world(local_position: Vector2) -> Vector2:
	return worldmap.coordinates + (local_position - worldmap.size * 0.5) / max(worldmap.zoom, 0.0001)

func _screen_to_cell(local_position: Vector2) -> Vector2i:
	var p := _screen_to_world(local_position)
	return Vector2i(floori(p.x), floori(p.y))

func _paint_cell(cell: Vector2i) -> void:
	datasource.paint_line(cell, cell, brush_terrain, brush_radius)
	last_paint_cell = cell
	refresh_queued = true

func _paint_to(cell: Vector2i) -> void:
	if cell == last_paint_cell:
		return
	datasource.paint_line(last_paint_cell, cell, brush_terrain, brush_radius)
	last_paint_cell = cell
	refresh_queued = true

func _zoom_at(local_position: Vector2, multiplier: float) -> void:
	var before := _screen_to_world(local_position)
	var new_zoom := clamp(worldmap.zoom * multiplier, 0.05, 32.0)
	worldmap.zoom = new_zoom
	var after := _screen_to_world(local_position)
	worldmap.coordinates += before - after

func _update_cursor(local_position: Vector2) -> void:
	var p := _screen_to_world(local_position)
	cursor_label.text = "world: %.1f, %.1f   cell: %d, %d" % [p.x, p.y, floori(p.x), floori(p.y)]

func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		_update_cursor(mouse_event.position)
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom_at(mouse_event.position, 1.18)
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom_at(mouse_event.position, 1.0 / 1.18)
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			painting = mouse_event.pressed
			if painting:
				_paint_cell(_screen_to_cell(mouse_event.position))
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT or mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = mouse_event.pressed
			return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_update_cursor(motion.position)
		if panning:
			pending_pan_pixels += motion.relative
			return
		if painting:
			_paint_to(_screen_to_cell(motion.position))

func _on_map_mouse_exited() -> void:
	painting = false
	panning = false
	pending_pan_pixels = Vector2.ZERO
