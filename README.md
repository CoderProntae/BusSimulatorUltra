# Bus Simulator Ultra

A 3D mobile bus simulator built in Godot 4 with realistic PBR graphics, inspired by "Ultimate Bus Simulator" and "Euro Truck Simulator 2".

## Features Implemented

### The Bus (Exterior)
- Detailed 3D bus model with rounded front face
- Large curved windshield with glass PBR material
- Side windows with thin metal frames
- Glowing headlights and red tail lights
- Orange turn signals
- Front/rear dark plastic bumpers
- Two side mirrors on extending arms
- Glowing orange destination sign above windshield
- Roof-mounted AC unit and vents
- Four turning and steering wheels with metallic rims
- Windshield wipers (animated)
- Rear license plate
- Sliding/folding passenger doors (open/close with button)
- Mud flaps behind rear wheels
- Subtle exhaust pipe
- Realistic glossy blue metallic PBR paint that reflects environment

### The Bus (Interior - Visible Through Windows / Interior Camera)
- Rows of passenger seats with dark fabric texture
- Driver seat with steering wheel
- Detailed dashboard with speedometer needle simulation
- Fuel gauge display
- Indicator lights on dashboard
- Gear selector (D/N/R) and hand brake representation
- Door open/close control buttons
- Interior rear-view mirror
- Handrails and hanging straps for standing passengers
- Steps at the doors
- Driver cabin partition
- Warm interior ceiling lights

### The City
- Buildings of varying heights (2-15 floors) with visible windows
- Night windows glow with warm light (simulated emissive materials)
- Asphalt roads with white lane markings, yellow center lines
- Zebra crosswalks at intersections
- Raised concrete sidewalks with curb stones
- Working traffic lights (red/yellow/green cycle)
- Bus stops with shelter, bench, route sign, and waiting passengers
- Fuel station with canopy, pumps, and glowing price sign
- Green trees scattered along sidewalks and in park areas
- Street lamps that illuminate at night
- Parked cars along streets
- Pedestrians walking on sidewalks
- Moving traffic: cars and vans of different colors stopping at red lights

### Visual Quality & Atmosphere
- Realistic skybox and sun position for day/night cycle
- Full day/night cycle with sunrise/sunset colors
- Soft directional sunlight with smooth shadows
- Night mode: glowing street lamps, headlights, lit windows, dark blue sky with stars
- Weather variety: sunny, cloudy, rainy
- Rain makes roads wet and reflective
- Realistic reflections on bus windows and body via PBR
- Atmospheric haze/fog for depth
- God rays through atmosphere
- Rich cinematic color grading via environment settings

### Driving Feel & Physics
- Slow, gradual acceleration (heavy bus feel)
- Long braking distance
- Wide turning radius
- Body roll/lean when turning sharply
- Subtle suspension bounce
- Top speed ~80 km/h
- Reverse gear for maneuvering

### Gameplay
- Drive to bus stops, open doors, board passengers
- Passenger delivery earns money ($15 per passenger)
- Coin economy: start with $500
- Fuel drains while driving; refuel at fuel station ($2.50/unit)
- Route system: next stop shown on HUD and minimap
- Traffic rules: stopping at red lights expected
- Running red lights or crashing causes fines
- Damage system: crashing dents bus and costs repair money
- Schedule feel with route progression
- Progression: earn enough to unlock new buses (structure in place)

### Sound (Placeholder System)
- Engine sound pitch changes with speed
- Horn sound trigger
- Brake squeal simulation
- Door open/close sound triggers
- Passenger murmur on boarding/alighting
- City ambience (distant traffic, birds)
- Rain sound when weather is rainy

### Cameras
- Exterior chase camera following smoothly behind bus
- Interior camera at driver's seat showing dashboard and windshield
- Door camera for safe passenger boarding view
- Top-down bird's-eye camera
- Camera avoids clipping through buildings (collision-aware positioning)

### HUD / Interface
- Digital/needle-style speedometer in km/h
- Fuel gauge/bar with color warning
- Current money display
- Passenger count
- Next bus stop name
- Minimap/GPS with route indicator
- In-game clock showing time of day
- Gear indicator (D / N / R)
- All buttons large, semi-transparent, thumb-friendly for landscape play

### Mobile Touch Controls
- Steering buttons on left (left/right)
- Gas and brake pedals on right (hold to accelerate/brake)
- Horn button
- Open/close doors button
- Switch camera button
- Toggle headlights button
- Large, semi-transparent, landscape-optimized layout

## How to Build the APK

### Prerequisites
1. **Godot 4.4+** with Android export templates installed
2. **Android SDK** (API 21+ recommended, target API 34)
3. **OpenJDK 17+**
4. **Android Build Tools / ADB** (optional but recommended)

### Quick Build
```bash
chmod +x build_apk.sh
./build_apk.sh
```

This script checks for all prerequisites and attempts to export the APK using Godot's headless export.

### Manual Export in Godot Editor
1. Open `project.godot` in Godot 4.4+
2. Import the Android export template (`Editor -> Manage Export Templates`)
3. Configure the Android preset (`Project -> Export -> Android`)
4. Click `Export Project` or use `Godot --headless --export-release "Android (Release)" build/BusSimulatorUltra.apk`

### Project Structure
```
BusSimulatorUltra/
├── scripts/
│   ├── game_manager.gd       # Main game logic, economy, time, weather
│   ├── bus_controller.gd     # Bus physics, doors, interior, passengers
│   ├── city_environment.gd   # City generation, buildings, roads
│   ├── traffic_system.gd     # Moving traffic vehicles, light cycles
│   ├── camera_controller.gd  # Multi-mode camera system
│   └── ui_controller.gd      # Mobile HUD and touch controls
├── scenes/
│   ├── main_scene.tscn       # Root scene (game manager + world)
│   ├── bus_scene.tscn        # Bus 3D model and interior
│   ├── city_scene.tscn       # City environment
│   └── ui_scene.tscn         # HUD layout
├── assets/
│   └── textures/             # Generated PBR textures
├── icon.png                  # App icon
├── project.godot             # Godot 4 project settings
├── export_presets.cfg        # Android APK export preset
└── build_apk.sh              # Build automation script
```

## Technical Notes

- **Engine**: Godot 4.4 (Forward Plus renderer, PBR)
- **Target**: Android (arm64-v8a, armeabi-v7a)
- **Graphics**: Vulkan renderer, screen-space reflections, ambient occlusion, glow, fog
- **Physics**: Custom heavy-vehicle physics in GDScript (not rigid body for stability)
- **3D Models**: Procedurally built using Godot MeshInstance3D, CSG-like geometry for bus and city
- **Textures**: AI-generated PBR texture maps (paint, asphalt, seats, dashboard, windows)

## Limitations / Next Steps

This is a fully functional foundation. For production release:
- Replace placeholder audio with recorded .wav/.ogg files
- Add more detailed 3D mesh models (imported .glb/.fbx bus and environment assets)
- Implement full passenger AI (walking to/from bus)
- Add more routes and unlockable bus variants with unique stats
- Optimize for low-end Android devices (reduce shadow resolution, disable SSAO)
- Add localization for multiple languages

## Credits

Built with Godot Engine 4.4. Inspired by Zuuks Games (Ultimate Bus Simulator) and SCS Software (Euro Truck Simulator 2).
