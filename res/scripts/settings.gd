extends Node

## Persistent graphics / gameplay settings (autoload "Settings").
##
## Everything here is chosen to be cheap to apply at runtime and safe on the
## Mobile renderer, where several Forward+ effects simply do not exist.
## Values are saved to user://settings.cfg so they survive a restart.

signal settings_changed()

const SAVE_PATH: String = "user://settings.cfg"

enum Quality { LOW, MEDIUM, HIGH }

const QUALITY_NAMES: Array[String] = ["LOW", "MEDIUM", "HIGH"]

# --- graphics ---
var quality: int = Quality.MEDIUM
var render_scale: float = 0.85
var shadows_enabled: bool = true
var shadow_distance: float = 120.0
var glow_enabled: bool = true
var fog_enabled: bool = true
var reflections_enabled: bool = false
var traffic_count: int = 5
var street_lamps_enabled: bool = true
var show_fps: bool = false
var target_fps: int = 60

# --- gameplay ---
var invert_steering: bool = false
var steering_sensitivity: float = 1.0


func _ready() -> void:
	load_settings()
	apply_all()


func quality_name() -> String:
	var index: int = clampi(quality, 0, QUALITY_NAMES.size() - 1)
	return QUALITY_NAMES[index]


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	_apply_quality_preset()
	apply_all()
	save_settings()
	emit_signal("settings_changed")


func _apply_quality_preset() -> void:
	if quality == Quality.LOW:
		render_scale = 0.6
		shadows_enabled = false
		shadow_distance = 60.0
		glow_enabled = false
		fog_enabled = false
		reflections_enabled = false
		traffic_count = 3
		street_lamps_enabled = false
	elif quality == Quality.MEDIUM:
		render_scale = 0.85
		shadows_enabled = true
		shadow_distance = 110.0
		glow_enabled = true
		fog_enabled = true
		reflections_enabled = false
		traffic_count = 5
		street_lamps_enabled = true
	else:
		render_scale = 1.0
		shadows_enabled = true
		shadow_distance = 180.0
		glow_enabled = true
		fog_enabled = true
		reflections_enabled = true
		traffic_count = 8
		street_lamps_enabled = true


func apply_all() -> void:
	_apply_render_scale()
	_apply_frame_cap()
	_apply_environment()
	_apply_shadows()
	_apply_lamps()


func _apply_render_scale() -> void:
	## Rendering 3D below native resolution is by far the biggest performance
	## win on a phone; the HUD stays crisp because it is drawn separately.
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var vp: Viewport = tree.get_root()
	if vp == null:
		return
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)


func _apply_frame_cap() -> void:
	Engine.max_fps = target_fps


func _apply_environment() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var env_nodes: Array = tree.get_nodes_in_group("world_environment")
	if env_nodes.is_empty():
		return
	var holder: Node = env_nodes[0]
	if not (holder is WorldEnvironment):
		return
	var env: Environment = (holder as WorldEnvironment).environment
	if env == null:
		return

	env.glow_enabled = glow_enabled
	env.fog_enabled = fog_enabled

	# These are Forward+ only; never switch them on from here.
	env.ssr_enabled = false
	env.ssil_enabled = false
	env.volumetric_fog_enabled = false
	env.ssao_enabled = false


func _apply_shadows() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var suns: Array = tree.get_nodes_in_group("sun")
	var i: int = 0
	while i < suns.size():
		var node: Node = suns[i]
		if node is DirectionalLight3D:
			var sun: DirectionalLight3D = node as DirectionalLight3D
			sun.shadow_enabled = shadows_enabled
			sun.directional_shadow_max_distance = shadow_distance
		i += 1


func _apply_lamps() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var lamps: Array = tree.get_nodes_in_group("street_lamp")
	var i: int = 0
	while i < lamps.size():
		var lamp: Node = lamps[i]
		if lamp is Node3D:
			var light: Node = lamp.get_node_or_null("Light")
			if light != null and light is OmniLight3D:
				var omni: OmniLight3D = light as OmniLight3D
				if not street_lamps_enabled:
					omni.visible = false
		i += 1


func toggle_shadows() -> void:
	shadows_enabled = not shadows_enabled
	_apply_shadows()
	save_settings()
	emit_signal("settings_changed")


func toggle_glow() -> void:
	glow_enabled = not glow_enabled
	_apply_environment()
	save_settings()
	emit_signal("settings_changed")


func toggle_fog() -> void:
	fog_enabled = not fog_enabled
	_apply_environment()
	save_settings()
	emit_signal("settings_changed")


func toggle_fps_counter() -> void:
	show_fps = not show_fps
	save_settings()
	emit_signal("settings_changed")


func cycle_render_scale() -> void:
	var steps: Array[float] = [0.6, 0.7, 0.85, 1.0]
	var current: int = 0
	var i: int = 0
	while i < steps.size():
		if absf(steps[i] - render_scale) < 0.02:
			current = i
		i += 1
	var next: int = current + 1
	if next >= steps.size():
		next = 0
	render_scale = steps[next]
	_apply_render_scale()
	save_settings()
	emit_signal("settings_changed")


func cycle_target_fps() -> void:
	var steps: Array[int] = [30, 60, 0]
	var current: int = 0
	var i: int = 0
	while i < steps.size():
		if steps[i] == target_fps:
			current = i
		i += 1
	var next: int = current + 1
	if next >= steps.size():
		next = 0
	target_fps = steps[next]
	_apply_frame_cap()
	save_settings()
	emit_signal("settings_changed")


func fps_label() -> String:
	if target_fps <= 0:
		return "UNCAPPED"
	return str(target_fps)


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "shadows_enabled", shadows_enabled)
	cfg.set_value("graphics", "shadow_distance", shadow_distance)
	cfg.set_value("graphics", "glow_enabled", glow_enabled)
	cfg.set_value("graphics", "fog_enabled", fog_enabled)
	cfg.set_value("graphics", "reflections_enabled", reflections_enabled)
	cfg.set_value("graphics", "traffic_count", traffic_count)
	cfg.set_value("graphics", "street_lamps_enabled", street_lamps_enabled)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.set_value("graphics", "target_fps", target_fps)
	cfg.set_value("gameplay", "invert_steering", invert_steering)
	cfg.set_value("gameplay", "steering_sensitivity", steering_sensitivity)
	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Could not save settings")


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if not FileAccess.file_exists(SAVE_PATH):
		_apply_quality_preset()
		return
	var err: int = cfg.load(SAVE_PATH)
	if err != OK:
		_apply_quality_preset()
		return

	quality = int(cfg.get_value("graphics", "quality", quality))
	render_scale = float(cfg.get_value("graphics", "render_scale", render_scale))
	shadows_enabled = bool(cfg.get_value("graphics", "shadows_enabled", shadows_enabled))
	shadow_distance = float(cfg.get_value("graphics", "shadow_distance", shadow_distance))
	glow_enabled = bool(cfg.get_value("graphics", "glow_enabled", glow_enabled))
	fog_enabled = bool(cfg.get_value("graphics", "fog_enabled", fog_enabled))
	reflections_enabled = bool(cfg.get_value("graphics", "reflections_enabled", reflections_enabled))
	traffic_count = int(cfg.get_value("graphics", "traffic_count", traffic_count))
	street_lamps_enabled = bool(cfg.get_value("graphics", "street_lamps_enabled", street_lamps_enabled))
	show_fps = bool(cfg.get_value("graphics", "show_fps", show_fps))
	target_fps = int(cfg.get_value("graphics", "target_fps", target_fps))
	invert_steering = bool(cfg.get_value("gameplay", "invert_steering", invert_steering))
	steering_sensitivity = float(cfg.get_value("gameplay", "steering_sensitivity", steering_sensitivity))
