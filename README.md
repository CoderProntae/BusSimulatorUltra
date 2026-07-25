# Bus Simulator Ultra

A 3D mobile bus simulator built from scratch in **Godot 4.4** (Forward+, PBR),
inspired by *Euro Truck Simulator 2* and *Ultimate Bus Simulator*.
Drive a heavy city bus around a PBR city, pick up and drop off passengers,
manage fuel and earn coins. Exported as an Android APK by GitHub Actions.

---

## Quick start

```bash
# open the project (the Godot project root is the res/ folder)
godot --path res

# verify everything before pushing
python3 tools/verify_project.py
```

### Enabling the APK build

The CI workflow lives in **`WORKFLOW_CONTENT.txt`** at the repo root rather
than `.github/workflows/`, because this repo's GitHub App connection lacks the
`workflows` permission (pushes to `.github/workflows/**` are rejected).

To activate it:

```bash
mkdir -p .github/workflows
cp WORKFLOW_CONTENT.txt .github/workflows/build-apk.yml
# delete the instruction comment header at the top of the copied file
git add .github/workflows/build-apk.yml
git commit -m "ci: add APK build workflow"
git push
```

It then builds on every push to `dev` / `main` / `arena/**`, and the APK is
downloadable from the run's **Artifacts** section (`BusSimulator-APK`).

---

## Project layout

```
res/                        <- Godot project root (project.godot lives here)
  project.godot
  export_presets.cfg
  scenes/     Main, Bus, World, BusStop, TrafficCar, HUD
  scripts/    bus_controller, camera_system, traffic_ai, passenger_system,
              fuel_system, ui_manager, day_night_cycle, city_builder,
              game_state, street_lamp, main
  materials/  asphalt.tres, concrete.tres, wall.tres, sky.tres
  shaders/    window_grid.gdshader
  assets/     models/, textures/, environment/   (CI overwrites with 1K PBR)
tools/                      helper + verification scripts
WORKFLOW_CONTENT.txt        the CI workflow (see "Enabling the APK build")
```

> **Why is the Godot root `res/`?**
> The materials reference `res://assets/textures/...` and the workflow
> downloads into `res/assets/textures/...`. Making `res/` the project root is
> what makes those two paths line up exactly, as required.

---

## Gameplay

| System | Behaviour |
| --- | --- |
| Passengers | **Deliver first, then board.** Stop at a bus stop, open the doors; riders for that stop get off (10-50 coins each), then waiting riders board up to the 24-seat capacity. |
| Economy | Start with **500 coins**. Fares earn 10-50 coins per passenger. |
| Fuel | 300 L tank, drains while driving. Refuel at the station (1.4 coins/L) by stopping under the canopy. Empty tank = no throttle. |
| Day/night | **5-minute** cycle. The rotating sun drives street-lamp bulbs, building window emission and the HUD clock. |
| Traffic | 5 AI cars loop the outer ring, braking for the bus and each other. |
| Cameras | Chase (anti-clip raycast), interior at the steering wheel, top-down orthographic. |

### Controls

**Touch (Android, landscape)** — real multi-touch: steer and accelerate at once.

- Left thumb pad — steering
- Right pedals — GAS / BRAKE (brake reverses when nearly stopped)
- Right column — HORN, DOOR, CAMERA, LIGHTS

**Keyboard (desktop testing)** — `A`/`D` or arrows steer, `W` gas, `S` brake,
`H` horn, `E` doors, `C` camera, `L` headlights.

---

## Visual quality

No flat single-colour surfaces anywhere:

- **Bus** — loads `assets/models/bus.glb` when present, otherwise builds a
  detailed CSG bus: rounded hull, slanted windshield, 6 framed transparent
  side windows, bumpers, emissive headlights (+ spot beams) and tail lights,
  side mirrors, glowing destination sign, roof AC unit, 4 wheels with tyre +
  metallic rim parented to each `VehicleWheel3D`, an animated sliding door,
  windshield wipers, and interior seats/poles/dashboard visible through glass.
- **Buildings** — `window_grid.gdshader` procedurally draws a window grid with
  per-cell hashed emissive lit windows, so towers glow at night. Heights vary
  8-40 m with rooftop boxes and parapets.
- **Environment** — HDRI `PanoramaSkyMaterial`, ACES tonemapping, SSAO, SSR,
  glow/bloom, volumetric fog (~0.02) for visible sun rays, plus a
  `ReflectionProbe` tracking the bus.
- **City** — asphalt PBR road (`uv1_scale` 20) with dashed lane lines, raised
  concrete curbs, zebra crossings, street lamps every 20 m, trees, traffic
  lights, bus shelters with bench + route sign, and a fuel station with
  canopy, pumps and an emissive price sign.

## Physics

`VehicleBody3D` at **10 000 kg**, 4 `VehicleWheel3D` (front 2 steer, rear 2
drive), suspension stiffness 25 / damping 3, smoothed steering that loses
authority with speed, 80 km/h cap, low centre of mass for heavy body roll.

---

## Asset strategy

Real 1K PBR maps are downloaded **in CI** (ambientCG + PolyHaven) into the
exact paths the materials reference. Procedurally generated fallbacks for
those same paths are **committed**, so the build and the game still look
correct if a download fails:

```
tools/gen_placeholder_textures.py   asphalt/concrete/brick albedo+normal+roughness
tools/gen_placeholder_sky.py        a real Radiance .hdr panorama (sun + clouds)
tools/verify_hdr.py                 independently decodes the .hdr to prove validity
tools/verify_project.py             parses every .gd + checks paths, workflow, preset
```

`assets/models/bus.glb` is the only genuinely optional asset — it is absent
from the repo and every load is guarded, so the CSG bus is used instead.
