# Son Sığınak — İzometrik Zombi Hayatta Kalma (Godot 4)

Kıyamet sonrası, kırsal Amerika havasında, izometrik kameralı bir hayatta kalma oyunu.
Karakterler, zombiler, binalar, araçlar ve silahlar Tripo 3D ile üretildi; sesler kodla sentezlendi.

> Not: Oyun dizinin *atmosferinden* ilham alıyor ama dizinin karakterlerini, isimlerini, logosunu
> veya mekânlarını birebir kullanmıyoruz. Yayınlamayı düşünüyorsan Tripo'da da ünlü karakterlerin
> birebir kopyalarını üretme; kendi karakterlerini tasarla.

## Başka bir bilgisayarda çalıştırmak

1. **Godot 4.7** (Standard, C# gerekmez) indir: https://godotengine.org/download — kurulum yok, zip'i aç yeter.
2. Bu depoyu indir: GitHub'da **Code → Download ZIP** (ya da `git clone`).
3. Godot'yu aç → **Import** → indirdiğin klasördeki `project.godot` → **Import & Edit**.
   İlk açılışta modeller ve sesler içe aktarılır (1–2 dakika sürebilir).
4. **F5** (ya da sağ üstteki ▶) ile oyunu başlat.

Kayıtlar her bilgisayarda ayrıdır (`%APPDATA%\Godot\app_userdata\Son Sığınak\savegame.json`).

## Kontroller

| Tuş | İşlev |
|---|---|
| WASD | Yürü |
| Shift | Koş (dayanıklılık harcar, gürültü yapar) |
| Sol tık | Kuşanılı silahla vur |
| Sağ tık basılı + Sol tık | Nişan al + ateş et (çok gürültülü!) |
| Q | Silah değiştir |
| E | Eşya al · **basılı tut**: ev/araba/sandık ara, barikat onar |
| Tab | Envanter |
| B | İnşa modu (1/2/3 seç, sol tık kur, R döndür) |
| F | Fener |
| 1 / 2 / 3 | Konserve ye / Su iç / İlk yardım |
| Fare tekerleği | Yakınlaş / uzaklaş |
| Esc | Duraklat (Kaydet, Ayarlar, Ana menü) |

## Kayıt

- Her şafakta (06:00) otomatik kayıt; duraklatma menüsünden elle de kaydedilir.
- Ana menüde **Devam Et** son kayıttan sürdürür.
- **Ölünce kayıt silinir** (kalıcı ölüm).

## Şu an oyunda olanlar

- **İzometrik kamera** (ortografik, 45°), yumuşak takip, zoom
- **Hayatta kalma**: sağlık, dayanıklılık, açlık, susuzluk — açlık/susuzluk sıfırsa can azalır
- **Zombi yapay zekası**: dolaşma → ses araştırma → kovalama; görüş açısı + duvar kontrolü,
  NavigationAgent ile binaların etrafından yol bulma, saldırı öncesi kısa hazırlık (geri kaçılabilir)
- **Gürültü sistemi**: koşmak, dövüşmek ve özellikle silah sesi yakındaki zombileri çeker
- **Gün/gece döngüsü** (1 gün = 12 dk): gece karanlık, daha çok zombi; her gece 22:00'de **sürü** gelir
- **Erzak**: konserve, su, ilk yardım, mermi; zombilerden de düşebilir
- Kan efekti, yerde kalan kan lekeleri, namlu ışığı, mermi izi
- Yer tutucu kasaba: merkezde çitli kamp + kamp ateşi, yollar, binalar, terk edilmiş arabalar, ağaçlar

## Klasör yapısı

```
project.godot
scenes/   main.tscn, player.tscn, zombie.tscn, pickup.tscn
scripts/  game.gd (autoload), player.gd, zombie.gd, level.gd, zombie_spawner.gd,
          camera_rig.gd, hud.gd, pickup.gd, model_animator.gd, main.gd
assets/models/characters   ← Tripo karakter .glb'leri
assets/models/zombies      ← Tripo zombi .glb'leri
assets/models/props        ← araba, varil, çit, sandık...
assets/models/buildings    ← evler, benzinlik, ahır...
```

---

# Tripo 3D → Godot iş akışı

## 1. Tripo'da üretim

**Karakterler ve zombiler (animasyonlu):**
1. Text-to-3D veya Image-to-3D ile modeli üret. Prompt'u **İngilizce** yaz ve **T-pose / A-pose** iste
   (otomatik rig için şart).
2. Modeli beğendikten sonra **Rig** (otomatik iskelet) adımını uygula.
3. **Animate** kısmından şu animasyonları ekle: `idle`, `walk`, `run`, `attack`, `hit/hurt`, `death`
   (zombi için yavaş/topallayan yürüme varyasyonları varsa onları seç).
4. Export: **GLB** formatı, animasyonlar dahil. Mümkünse düşük poligon / "low poly" seçeneğini kullan.

> Tripo'nun arayüzü sık güncelleniyor, buton isimleri biraz farklı olabilir; mantık aynı:
> *üret → rig → animasyon ekle → GLB indir*.

**Polygon bütçesi (izometrik kamerada küçük görünecekleri için):**

| Tür | Hedef üçgen | Doku |
|---|---|---|
| Oyuncu | 10–20k | 2048 |
| Zombi (ekranda 30+ tane olacak) | 5–10k | 1024 |
| Prop (varil, sandık, araba) | 1–5k | 512–1024 |
| Bina | 5–15k | 2048 |

**Örnek prompt'lar (atmosfere uygun, özgün):**
- `post-apocalyptic survivor man, worn brown leather jacket, jeans, backpack, short beard, realistic, T-pose`
- `rotting zombie, torn farmer clothes, pale grey-green skin, exposed ribs, realistic, T-pose`
- `abandoned rusty pickup truck, flat tires, broken windows, game asset`
- `old wooden farmhouse with porch, boarded windows, weathered paint, game asset`
- `makeshift wooden barricade with metal sheets and spikes, game asset`

## 2. Godot'ya alma

1. `.glb` dosyasını ilgili `assets/models/...` klasörüne kopyala — Godot otomatik import eder.
2. FileSystem panelinde dosyaya çift tıklarsan **Advanced Import Settings** açılır:
   - Animasyonların `loop` ayarını burada da yapabilirsin (kod `idle/walk/run`'ı zaten otomatik döngüye alıyor).
   - Ölçek yanlışsa `Root Scale` ile düzelt.

## 3. Oyuncuya model takmak

1. `scenes/player.tscn`'yi aç, kök `Player` düğümünü seç.
2. Inspector → **Model (Tripo 3D)** → `Model Scene` alanına `.glb` dosyasını sürükle.
3. Oyunu çalıştır. Output panelinde şuna benzer bir satır görürsün:
   `[Player] Animasyonlar: eşleşen: { "idle": "Idle", "walk": "Walk", ... }`
4. Ayarlar:
   - Karakter **ters bakıyorsa** → `Model Yaw Offset Deg = 180`
   - **Çok büyük/küçükse** → `Model Scale` (hedef boy ≈ 1.8 birim)
   - **Yere gömülü / havadaysa** → `Model Y Offset`

Animasyon isimleri anahtar kelimeyle eşleşir (`scripts/model_animator.gd`): adında *walk* geçen
yürüme, *attack/punch/bite* geçen saldırı, *death/die* geçen ölüm olur. Tripo farklı isim verirse
o dosyadaki `KEYWORDS` listesine kelime eklemen yeterli.

## 4. Zombilere model takmak

`scenes/zombie.tscn` → `Model Variants` dizisine **birden fazla** zombi `.glb`'si ekle.
Her zombi doğarken rastgele birini seçer, boyu ve animasyon hızı hafifçe değişir → kalabalık doğal görünür.

## 5. Harita / prop'lar

1. `.glb`'yi sahnede `Level/Props` altına sürükle.
2. **Çarpışma ekle** (yoksa içinden geçersin ve zombiler yol bulamaz):
   - Kolay yol: Advanced Import Settings → mesh'i seç → **Physics** → `Generate` açık,
     `Body Type: Static`, `Shape Type: Simple Convex` (bina gibi büyükler için `Trimesh`).
   - Ya da: prop'u bir `StaticBody3D` altına koyup `CollisionShape3D` (Box) ekle.
3. Kendi haritanı kurmaya başladığında `Level` düğümünde `Generate Placeholder Town = false` yap.
4. Navigasyon ağı her açılışta `Level` altındaki statik çarpıştırıcılardan otomatik pişirilir
   (`Bake At Runtime`). Editörde görmek istersen `Level`'i seç → üstteki **Bake NavigationMesh**.

---

## Sesler

Bütün sesler `tools/generate_audio.gd` ile kodla sentezlendi ve `assets/audio/` altında duruyor:

- `sfx/` — `isim_0.wav, isim_1.wav…` aynı sesin çeşitleri; oyun her seferinde rastgele birini seçer.
- `music/theme.wav` — menü ve gece müziği (48 sn döngü), `music/death.wav` — ölüm sesi.

Bir sesi gerçek bir kayıtla değiştirmek için aynı isimde `.wav` (veya `.ogg`) dosyasını üzerine koy.
Çeşit eklemek için `groan_6.wav` gibi yeni numara vermen yeterli. Sesleri baştan üretmek için:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tools/generate_audio.gd
```

## Sonraki adımlar (önerilen sıra)

1. Tripo ile oyuncu + 2-3 zombi modeli → yukarıdaki adımlarla tak
2. Ses: zombi inlemeleri, ayak sesi, silah, ortam (rüzgâr, cırcır böceği) — gürültü sistemine bağlı
3. Binaya girince çatı/üst katı gizleme ve kamerayla oyuncu arasındaki duvarları saydamlaştırma
4. Silah çeşitleri (bıçak, beyzbol sopası, tüfek, yay) + dayanıklılık
5. Crafting + üs inşası (barikat, kapı, yağmur suyu toplayıcı)
6. NPC hayatta kalanlar, görevler, kayıt sistemi
