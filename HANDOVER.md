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
| 16 GDScript dosyası | Hepsi parse ediyor (gdparse ile doğrulandı) |
| CI / APK build | ✅ Çalışıyor |
| APK boyutu | ~58 MB |
| `python3 tools/verify_project.py` | **145/145 geçiyor** |
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

### 3.9 Ana menü sol üst köşeye çökmüştü

`main_menu.gd` / `loading_screen.gd` `Control.new()` ile (0×0) yaratılıyor,
`_ready()` içinde ise `set_anchors_preset(PRESET_FULL_RECT)` çağrılıyordu.
Bu metodun varsayılanı `keep_offsets=false`'tur ve Godot bunu **"offsetleri
yeniden hesapla ki kontrol şu anki dikdörtgenini korusun"** diye uygular
(`Control::set_anchors_preset` → `set_anchor` → `_compute_offsets`).
Node ağaç içinde ve 0×0 olduğu için 0×0 sadakatle korundu → başlık, düğmeler
ve shader arka planı sol üst köşeye yığıldı. (Ekranda görünen mavi
`default_clear_color`'dı, yani arka plan hiç çizilmemişti.)

**Düzeltme:** üç UI kökünde de `set_anchors_and_offsets_preset()`.
**Yeni bir tam ekran Control yaparsan hep bunu kullan.**

### 3.10 Düğmeler dokunmayı almıyordu

`BaseButton::gui_input()` yalnızca `InputEventMouseButton` (ve `ui_accept`)
işler; `InputEventScreenTouch` dalı **yoktur**. Proje 3.6 yüzünden
`emulate_mouse_from_touch=false` tutmak zorunda, dolayısıyla hiçbir Button
parmağı görmüyordu. Emülasyonu geri açmak da çözüm değil: Godot mouse'u
sadece **ilk** parmak için taklit eder, yani pedal basılıyken hiçbir düğme
çalışmazdı.

**Düzeltme:** `res/scripts/touch_button.gd` — dokunma akışını kendisi okuyan
Button. Herhangi bir parmak, her an çalışır; `DEVICE_ID_EMULATION`
olaylarını yok sayar (masaüstünde çift tetiklemeyi önler); `touch_modal`
grubuna saygı duyar (ayar paneli açıkken arkası tıklanmaz).

⚠️ **Oyuncunun basacağı her düğme `touch_button.gd` kullanmalı.**
Menüde `_make_button()`, HUD'da `_make_touch_button()` fabrikalarından geç.
`verify_project.py` içindeki `check_ui_contract()` bunu zorunlu kılar.

### 3.11 Otobüs "maksimum 1 km/h"de kilitleniyordu

Kapı kilidi şöyleydi: `if doors_open and speed_kmh > 1.0: brake = 25`.
Kapılar **varsayılan olarak açık**, dolayısıyla otobüs 1 km/h'yi geçer geçmez
fren devreye giriyor, 6800 N'luk itiş bunu yenemiyordu → hız **tam 1'de
(ya da 0'da) kilitleniyordu.**

**Düzeltme:** kilit artık `engine_force`'u sıfırlıyor (gerçek otobüs kapısı
açıkken hareket etmez) ve "Close the doors before driving off" uyarısı
basıyor. **Kapı kilidine fren ekleme — eşiğin kendisi tuzağa dönüşür.**

### 3.12 Korkunç yavaş hızlanma

Üç ayrı hata üst üste binmişti:
- Sadece arka aks `use_as_traction` → 3400 N × 2 tekerlek ÷ 10 t = **0,68 m/s²**
- `wheel_friction_slip` 4.0/3.6 (Godot varsayılanı 10.5) → lastik patinaj yapıyor
- Süspansiyon: `stiffness=25` (dokümana göre <50 arazi aracı),
  `damping 3.0/4.0` (doküman ~0.3/0.5), `max_force=90000` (mass/4'ün ~36 katı,
  tavsiye 3-4 kat)

**Düzeltme:** 4 tekerlek çekiş, 6000 N (**2,4 m/s²**), grip 9.0-10.5,
süspansiyon dokümana uygun. Ayrıca kuadratik hava direnci eklendi.

⚠️ `verify_project.py` motor gücünü **iki yönden** sınırlar: 2,0 m/s² altı
"sürünüyor", 3,5 m/s² üstü "10 tonluk otobüs için fazla atik" der.

### 3.13 Trafik arabası çarpınca yanmıyordu

Hasar `traffic_ai._detect_collisions()` içindeydi ve `get_slide_collision()`
okuyordu. **CharacterBody3D yalnızca KENDİ `move_and_slide()`'ının ürettiği
teması görür.** Otobüsün çarptığı araba genelde duruyordu → hiç temas
üretmiyor → hiç hasar almıyordu. Yani hasar, kurbanın otobüse çarpmasına
bağlıydı; tam tersi olması gerekirken.

**Düzeltme:** Momentumu olan taraf (otobüs) raporluyor:
`bus_controller._report_crashes()` → `traffic_ai.take_external_hit()`,
kütle farkı için 4,5 kat ağırlıklandırma.

### 3.14 Trafik "salaktı"

`_update_blocked()` tek boolean'dı ve ışın arabanın **merkezinden** (kendi
4,3 m gövdesinin içinden) 9 m atılıyordu. Ya tam gaz ya tam duruş.

**Düzeltme:** ışın tampondan başlıyor, 14 m, `add_exception(self)`,
ve `_gap_ratio` ile hız oransal ölçekleniyor. Fren (16) gazdan (5.5) sert.

### 3.15 Durak isimleri çakışıyordu

24 durak ama 8 isim vardı: `STOP_NAMES[i % 8]` → üç ayrı yer "Riverside".
Harita ve bilet sistemi durakları **isimle** aradığı için yanlış hedefi
gösterebilirdi. Artık `_unique_stop_name()` benzersiz isim üretiyor
("Riverside", "Riverside North", "Riverside East"). Doğrulandı: 24/24 benzersiz.

### 3.16 1. şahıs camı opaktı

Üç hata üst üste:
1. Alfa 0,62 (dışarıdan bakmak için uygun, içinden bakmak için değil)
2. `metallic=0.9` → karanlık kabini aynalıyordu
3. **`WindshieldFrame`**: tüm açıklığı kaplayan **opak** kutu, camdan 6 cm önde

**Düzeltme:** çerçeve dört ince ray + A-direği oldu (ortası gerçekten boş),
cam kendi `_windshield_mat()` materyalini kullanıyor (alfa 0,10, metallic 0).
⚠️ Tek parça `WindshieldFrame` kutusunu geri koyma — doğrulama reddeder.

### 3.17 Otobüs 0 km/h'de takılı kaldı (süspansiyon otobüsü taşıyamıyordu)

**Bu bir asistan regresyonuydu** — 3.12'yi düzeltirken oluştu. İki hata:

1. `suspension_max_force = 12000`. Godot dokümanının *"aracın kütlesinin
   dörtte birinden büyük olmalı"* ifadesini `10000 kg / 4 = 2500 N` diye
   okumuşum. Kastedilen **ağırlığın** dörtte biri:
   `10000 × 9.8 = 98000 N` → tekerlek başına **24500 N**.
   4 tekerlek × 12000 = 48000 N, yani otobüsün sadece **%49'u**.
2. `suspension_stiffness = 70` N/mm → statik çökme
   `24500 / 70000 = 35 cm`, ama `suspension_travel` sadece 28 cm.

Buna çarpışma kutusu da eklenince (2.9 m boy, y=0.35 merkez → altı -1.10,
lastik teması -1.14, yani **4 cm** boşluk; çökmeyle birlikte 5,4 cm yeraltı)
gövde asfalta oturdu. **Yolu otobüsü taşıyınca tekerleklerde yük kalmadı,
yük yoksa tutuş da yok** → `engine_force` hiçbir şey yapmadı, hız 0.

**Düzeltme:** `max_force=85000` (tekerlek yükünün 3,5 katı),
`stiffness=260` (28 cm yolun içinde 9,4 cm çökme),
çarpışma kutusu 2.5 m / y=0.55 (çökme sonrası 34,6 cm boşluk).
Gövde mesh'ine dokunulmadı, sadece fizik proxy'si.

⚠️ **DERS: statik kontrol bunu yakalayamadı.** Bu yüzden iki katman eklendi:
- `verify_project.py` → `check_suspension_physics()`: taşıma kapasitesi,
  çökme/yol oranı ve çökme sonrası yerden yükseklik **hesaplanır**.
  Üç eski bozuk değerin üçünü de reddettiği doğrulandı.
- **`tools/physics_smoke.gd`** → gerçek motorla headless test: otobüsü
  zemine bırakır, gaza basar, 5 km/h'yi geçmezse / hareket etmezse /
  4 tekerlek yüklü değilse / kapı açılınca yavaşlamazsa **build'i düşürür**.

```bash
bash RUN_PHYSICS_TEST.sh     # Godot'u indirir ve testi calistirir
```

⚠️ Bu testin CI adımı **`WORKFLOW_CONTENT.txt` içinde bekliyor**, çünkü bu
uygulama bağlantısının `workflows` izni yok (`.github/workflows/` dosyasını
push edemiyor). Etkinleştirmek için:
```bash
cp WORKFLOW_CONTENT.txt .github/workflows/build-apk.yml
# dosyanin basindaki yorum blogunu sil, sonra commit + push
```

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
  scripts/   16 dosya
  materials/ asphalt, concrete, wall, sky (.tres)
  shaders/   window_grid.gdshader
  assets/    textures/, environment/sky.hdr
tools/       verify_project.py, physics_smoke.gd, placeholder üreticiler
.github/workflows/build-apk.yml
PUSH.sh      tek komutla push (PR AÇMAZ)
HANDOVER.md  bu dosya
```

| Dosya | Satır | Görev |
|---|---|---|
| `bus_controller.gd` | 1438 | Otobüs fiziği + gövde + detaylı kokpit + motor sesi |
| `ui_manager.gd` | 1113 | Mobil HUD, direksiyon, harita, hedef paneli, ayarlar |
| `city_builder.gd` | 973 | Şehir üretimi (benzersiz durak isimleri) |
| `traffic_ai.gd` | 823 | Trafik AI + oransal takip + hasar/yangın/patlama |
| `passenger_system.gd` | 453 | Durak mantığı + hedef durak biletleme |
| `loading_screen.gd` | 380 | Gerçek yükleme ekranı |
| `fuel_system.gd` | 359 | Yakıt istasyonu |
| `main.gd` | 343 | Menü → yükleme → oyun akışı |
| `settings.gd` | 273 | Kalıcı grafik ayarları (autoload) |
| `main_menu.gd` | 258 | Ana menü |
| `game_state.gd` | 252 | Ekonomi/yakıt/yolcu + durak kaydı (autoload) |
| `camera_system.gd` | 240 | 3 kamera modu (iç kamera: sallantı + yalpalama) |
| `mini_map.gd` | 214 | Navigasyon haritası (hedef durakları gösterir) |
| `day_night_cycle.gd` | 204 | 5 dk gece/gündüz |
| `touch_button.gd` | 126 | Dokunma alan Button (bkz. 3.10) |
| `street_lamp.gd` | 19 | Sokak lambası |

---

## 6. OYUN İÇERİĞİ

- **Yolcular:** Önce inen sonra binen. 24 durak (benzersiz isimli).
  Her yolcu **gerçek bir hedef durak** satın alır (`GameState.destinations`),
  10-50 coin/yolcu, kapasite 24.
- **Navigasyon:** Sol üstte kuzey-yukarı mini harita — sokak ızgarası, tüm
  duraklar (beyaz), **hedef duraklar (nabız atan camgöbeği)**, ekran dışı
  hedefler kenara sabitlenir, en yakın hedefe yön çizgisi. Altında metin
  paneli: "DROP OFF: Riverside — 3 aboard — 84 m".
- **Ekonomi:** 500 coin başlangıç.
- **Yakıt:** 300 L, istasyonda 1.4 coin/L. Tam gazda ~2,6 dk, şehir içi ~3,7 dk.
- **Sürüş:** 10 t, 4 tekerlek çekiş, 2,4 m/s². **Kapı açıkken hareket etmez**
  (gaz kesilir + uyarı). Kuadratik hava direnci üst hızı oturtur.
- **Gece/gündüz:** 5 dk döngü; lambalar, pencereler, farlar tepki verir.
- **Trafik:** Oransal takip mesafesi (14 m ışın, kademeli yavaşlama).
  Çarpışma → hasar → yangın → patlama → 6 sn sonra respawn.
  Çarpışmayı **otobüs raporlar** (bkz. 3.13).
- **Kameralar:** Takip (anti-clip raycast), **detaylı kokpit**, tepeden ortografik.
  İç kamera: gerçek göz noktası, 78 FOV, virajda yalpalama, motor sallantısı.
- **Kokpit:** Sarmal torpido, kapaklı gösterge paneli, **canlı ibreli
  hız/devir saati**, MFD, direksiyonla dönen üç kollu simit, kolonlar,
  pedallar, vites, el freni, havalı koltuk, güneşlik, ayna, bilet tepsisi.
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

# Fizigi DEGISTIRDIYSEN bunu da calistir (Godot indirir):
bash RUN_PHYSICS_TEST.sh
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
