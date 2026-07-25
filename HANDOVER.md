# DEVİR BELGESİ — BusSimulatorUltra

> Yeni asistan: bunu baştan sona oku. Kullanıcıya soru sorup zamanını harcama.

---

## 0. EN KRİTİK KURAL

Kullanıcı **11 kez** oturumunu kaybetti çünkü PR'lar merge edildi.
Arena oturumu PR durumuna göre takip eder: **PR merge edilir veya kapanırsa
oturum ölür.**

1. **ASLA merge etme.** Kullanıcı "merge et" dese bile ÖNCE dur ve sor.
2. **ASLA PR açma.** PR gereksiz; push yeterli, CI zaten çalışıyor.
3. **Sadece push et.** Push oturumu kapatmaz.
4. Şüphedeyken **hiçbir şey yapma, sor.**

**Bu oturumun branch'i: `arena/019f9afc-bussimulatorultra`** (önceki oturum
`arena/019f9a44-...` idi, oradaki `8c80330` commit'inden dallandı).
Sadece bu branch'e push et.

---

## 1. PROJE

Godot 4.4 + GDScript ile sıfırdan yazılmış **3D mobil otobüs simülatörü** (Android APK).
İlham: ETS2 + Ultimate Bus Simulator.

- Hedef: Android, landscape, 1280x720, 60 fizik FPS
- Build: GitHub Actions APK üretiyor (CI'ın tam internet erişimi var)
- Depo: `CoderProntae/BusSimulatorUltra`

### Godot proje kökü `res/` klasörüdür

Materyaller `res://assets/...` kullanır, CI `res/assets/...` içine indirir.
Godot'u hep şöyle çalıştır:

```bash
godot --path res
```

---

## 2. MEVCUT DURUM

| Sistem | Durum |
|---|---|
| 14 GDScript dosyası | Hepsi parse ediyor (gdparse ile doğrulandı) |
| CI / APK build | ✅ Çalışıyor |
| APK boyutu | ~58 MB |
| `python3 tools/verify_project.py` | **111/111 geçiyor** |
| Ana menü | ✅ |
| Gerçek yükleme ekranı | ✅ (sahte değil, ölçülü ilerleme) |
| Grafik ayarları | ✅ `user://settings.cfg` |
| Sıfır inline-if | ✅ |

---

## 3. ÇÖZÜLMÜŞ HATALAR — GERİ GETİRME!

### 3.1 `--check-only --script` yanlış "GameState bulunamadı" hatası
Her scripti tek başına yükler, autoload kayıtlı olmaz, **sahte** compile error verir.
Doğru yöntem (workflow'da zaten var):
1. `gdparse res/scripts/*.gd`
2. `%` içinde ternary arayan grep koruması
3. `godot --headless --path res --quit-after 180` → logda `SCRIPT ERROR` ara

**ASLA `--check-only --script` geri getirme.**

### 3.2 Mobilde ekran karıncalanması
`rendering_method.mobile="mobile"` olmalı (forward_plus DEĞİL).
Volumetric Fog / SSR / SSIL Mobile'da desteklenmez → parazit.
`main.gd::_apply_renderer_safe_graphics()` çalışma anında da kapatıyor.
**Bu efektleri mobilde açma.**

### 3.3 Bembeyaz sis
Suçlu yükseklik sisiydi. Düzeltme: `fog_height=0`, `fog_height_density=0`,
`fog_sky_affect=0`, `fog_density=0.0012`, `tonemap_white=2.0`, `glow_bloom=0`.

⚠️ **TUZAK:** `day_night_cycle.gd` her karede `fog_density`'yi yeniden yazar.
Sisi değiştirirsen orayı da güncelle.

### 3.4 Gaz/fren ters
`VehicleBody3D`'nin ileri yönü `Vector3.MODEL_FRONT` = **+Z**.
Gövde +Z'ye bakacak şekilde yeniden inşa edildi (ön aks +3.95, arka aks -3.25),
kamera `-basis.z`, farlar 180° çevrildi.

### 3.5 Direksiyon ters
Otobüs +Z'ye baktığı için sağı -X → `steering = -_steer_current * MAX_STEER_ANGLE`

### 3.6 Direksiyon kararsızlığı
`emulate_mouse_from_touch=false`, `emulate_touch_from_mouse=true`;
direksiyonu tek işaretçi sahiplenir (`_steer_pointer`);
girdi sadece hedef açı verir, 7.5 rad/s sınırıyla yaklaşılır.

### 3.7 Duraklar yolun ortasındaydı
Kaldırım kenarına taşındı (yol merkezinden 9.2 m yana, blok ortasında).
24 durak, en yakın kavşaktan 30 m.

### 3.8 CI süt kamyonu indiriyordu
`CesiumMilkTruck.glb` indirmesi kaldırıldı. Gerçek otobüs modeli istersen
`res/assets/models/bus.glb` (önü **+Z**) koy, kod otomatik kullanır.

---

## 4. GDSCRIPT KURALLARI (ZORUNLU)

- **ASLA inline-if (ternary)**, özellikle `%` format demeti içinde:
  - ❌ `name = "Wheel_%s" % ("L" if side < 0 else "R")`
  - ✅ `var label = "L"` / `if side >= 0: label = "R"` / `name = "Wheel_" + label`
- `%` yerine string birleştirme veya `str()`
- **TAB** ile girinti
- Her `.gd` dosyasını yazdıktan sonra yeniden oku ve doğrula
- Opsiyonel `load()` çağrılarını `ResourceLoader.exists()` /
  `FileAccess.file_exists()` ile koru
- Workflow dosyasında HTML entity olmasın — düz `&&`

---

## 5. DOSYA YAPISI

```
res/                       <- GODOT PROJE KÖKÜ
  project.godot            autoload: GameState, Settings
  export_presets.cfg       Android preset
  scenes/    Main, Bus, World, BusStop, TrafficCar, HUD
  scripts/   14 dosya
  materials/ asphalt, concrete, wall, sky (.tres)
  shaders/   window_grid.gdshader
  assets/    textures/, environment/sky.hdr
tools/       verify_project.py + placeholder üreticiler
.github/workflows/build-apk.yml
PUSH.sh      tek komutla push (PR AÇMAZ)
HANDOVER.md  bu dosya
```

| Dosya | Satır | Görev |
|---|---|---|
| `bus_controller.gd` | 1005 | Otobüs fiziği + gövde modeli + motor sesi |
| `ui_manager.gd` | 959 | Mobil HUD, dönen direksiyon, ayarlar, FPS |
| `city_builder.gd` | 952 | Şehir üretimi |
| `traffic_ai.gd` | 762 | Trafik AI + hasar/yangın/patlama |
| `passenger_system.gd` | 427 | Durak mantığı |
| `loading_screen.gd` | 376 | Gerçek yükleme ekranı |
| `fuel_system.gd` | 359 | Yakıt istasyonu |
| `main.gd` | 343 | Menü → yükleme → oyun akışı |
| `settings.gd` | 273 | Kalıcı grafik ayarları (autoload) |
| `main_menu.gd` | 240 | Ana menü |
| `day_night_cycle.gd` | 204 | 5 dk gece/gündüz |
| `camera_system.gd` | 197 | 3 kamera modu |
| `game_state.gd` | 157 | Ekonomi/yakıt/yolcu (autoload) |
| `street_lamp.gd` | 19 | Sokak lambası |

---

## 6. OYUN İÇERİĞİ

- **Yolcular:** Önce inen sonra binen. 24 durak. 10-50 coin/yolcu. Kapasite 24.
- **Ekonomi:** 500 coin başlangıç.
- **Yakıt:** 300 L, istasyonda 1.4 coin/L.
- **Gece/gündüz:** 5 dk döngü; lambalar, pencereler, farlar tepki verir.
- **Trafik:** Döngüsel AI arabalar, çarpışma → hasar → yangın → patlama → 6 sn sonra respawn.
- **Kameralar:** Takip (anti-clip raycast), iç mekân, tepeden ortografik.
- **Kontroller:** Sol dönen direksiyon, sağ gaz/fren, HORN/DOOR/CAMERA/LIGHTS.
  Çoklu dokunma çalışır. Klavye: A/D, W, S, H, E, C, L.

---

## 7. DOĞRULAMA — HER DEĞİŞİKLİKTEN SONRA

```bash
cd /home/user/BusSimulatorUltra
pip install --break-system-packages "gdtoolkit==4.*"
gdparse res/scripts/*.gd && echo "TUM SCRIPTLER GECERLI"
python3 tools/verify_project.py
grep -n ' if .* else ' res/scripts/*.gd || echo "TEMIZ"
```

`gdparse`, Godot'un parser'ından daha müsamahakârdır (`%` içindeki ternary'yi
kabul eder ama Godot etmez) — bu yüzden `verify_project.py` ayrı regex kontrolü yapar.

**Not:** Bu sandbox'ta Godot binary'si indirilemiyor (GitHub release assets
bloklu), gerçek boot testi CI'da yapılır.

---

## 8. NASIL GÖNDERİLİR

```bash
bash PUSH.sh
```

Bilerek PR açmaz. Push sonrası CI otomatik APK üretir:
- Actions: https://github.com/CoderProntae/BusSimulatorUltra/actions
- APK: en üstteki çalışma → Artifacts → `BusSimulator-APK`

---

## 9. SIRADAKİ OLASI İŞLER

- Ana menüdeki SETTINGS butonu şu an sadece kaliteyi değiştiriyor; tam panel oyun içinde.
- Otobüs modeli detaylandırma (körüklü otobüs, livery).
- Gerçek `bus.glb` (önü +Z).
- APK 58 MB; `export_presets.cfg` içinde `architectures/x86_64=false` → ~15 MB küçülür
  (ama emülatörde çalışmaz).

---

## 10. KULLANICIYLA İLETİŞİM

- Kullanıcı **Türkçe** yazıyor, Türkçe cevap ver.
- 11 oturum kaybı yaşadı; sabırlı ve net ol.
- Uzun açıklama değil, **çalışan sonuç** istiyor.
- Tahmin ediyorsan "tahmin" de; uydurma.
- **Merge/PR konusunda kesinlikle kendi başına hareket etme.**
