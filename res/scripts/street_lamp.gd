extends Node3D

## Street lamp: the day/night cycle calls set_night_energy() on every node in
## the "street_lamp" group, turning the bulb emission + OmniLight3D on at dusk.

func set_night_energy(energy: float, on: bool) -> void:
	var light: Node = get_node_or_null("Light")
	if light != null and light is OmniLight3D:
		var omni: OmniLight3D = light as OmniLight3D
		omni.visible = on
		omni.light_energy = energy * 4.5

	var bulb: Node = get_node_or_null("Bulb")
	if bulb != null and bulb is MeshInstance3D:
		var mesh_node: MeshInstance3D = bulb as MeshInstance3D
		var mat: Material = mesh_node.get_surface_override_material(0)
		if mat != null and mat is StandardMaterial3D:
			var std: StandardMaterial3D = mat as StandardMaterial3D
			std.emission_energy_multiplier = energy * 6.0
