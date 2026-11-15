class_name Updater
extends Node
## Oyun içi güncelleme: GitHub'daki son sürümü kontrol eder, yeni exe'yi indirir,
## eskisinin yerine koyar ve oyunu yeniden başlatır.
##
## Yayın kuralı: GitHub sürüm etiketi "v0.3" gibi olmalı ve sürüme "SonSiginak.exe"
## adlı dosya eklenmeli. Sürüm numarası project.godot > application/config/version.
##
## Test için: SonSiginak.exe -- --auto-update   (kontrol + kurulumu kendiliğinden yapar)
##            ... --update-no-restart          (kurduktan sonra yeniden başlatmadan çıkar)

signal state_changed(state: String, text: String)

const API_URL := "https://api.github.com/repos/fatihlabsai/son-siginak/releases/latest"
const RELEASES_PAGE := "https://github.com/fatihlabsai/son-siginak/releases/latest"
const ASSET_NAME := "SonSiginak.exe"
const HEADERS := ["User-Agent: SonSiginak-Updater", "Accept: application/vnd.github+json"]

## idle | checking | latest | available | downloading | installing | failed
var state := "idle"
var latest_version := ""
var notes := ""
var _download_url := ""
var _download_size := 0
var _http: HTTPRequest
var _new_path := ""


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## a, b'den yeni mi? ("0.10" > "0.9")
static func is_newer(a: String, b: String) -> bool:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


## Kendini güncelleyebilir mi? (dışa aktarılmış Windows exe'si; editörde değil)
static func can_self_update() -> bool:
	return OS.has_feature("template") and OS.get_name() == "Windows"


## Önceki güncellemeden kalan eski exe'yi sil.
static func cleanup_old() -> void:
	if not can_self_update():
		return
	var old := OS.get_executable_path() + ".old"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)


static func _user_arg(name: String) -> bool:
	return OS.get_cmdline_user_args().has(name)


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.use_threads = true
	add_child(_http)
	set_process(false)


func check() -> void:
	if state == "checking" or state == "downloading":
		return
	_set_state("checking", "Güncelleme kontrol ediliyor...")
	if _http.request_completed.is_connected(_on_download_done):
		_http.request_completed.disconnect(_on_download_done)
	_http.request_completed.connect(_on_check_done, CONNECT_ONE_SHOT)
	var err := _http.request(API_URL, HEADERS)
	if err != OK:
		_set_state("failed", "")


func _on_check_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[Updater] kontrol başarısız: result=%d code=%d" % [result, code])
		_set_state("failed", "")
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		_set_state("failed", "")
		return
	latest_version = String(data.get("tag_name", "")).trim_prefix("v")
	notes = String(data.get("body", ""))
	_download_url = ""
	for a in data.get("assets", []):
		if String(a.get("name", "")) == ASSET_NAME:
			_download_url = String(a.get("browser_download_url", ""))
			_download_size = int(a.get("size", 0))
	print("[Updater] mevcut=%s son=%s exe=%s" % [current_version(), latest_version, _download_url != ""])
	if latest_version != "" and is_newer(latest_version, current_version()):
		_set_state("available", "Yeni sürüm hazır: v%s" % latest_version)
		if _user_arg("--auto-update"):
			install()
	else:
		_set_state("latest", "Oyun güncel (v%s)" % current_version())


## Güncellemeyi indir ve kur. Exe'den çalışmıyorsa sürüm sayfasını açar.
func install() -> void:
	if state != "available":
		return
	if not can_self_update() or _download_url == "":
		OS.shell_open(RELEASES_PAGE)
		return
	_new_path = OS.get_executable_path() + ".new"
	if FileAccess.file_exists(_new_path):
		DirAccess.remove_absolute(_new_path)
	_http.download_file = _new_path
	_http.timeout = 0.0
	_http.request_completed.connect(_on_download_done, CONNECT_ONE_SHOT)
	var err := _http.request(_download_url, ["User-Agent: SonSiginak-Updater"])
	if err != OK:
		_fail("İndirme başlatılamadı.")
		return
	_set_state("downloading", "İndiriliyor... %0")
	set_process(true)


func _process(_delta: float) -> void:
	if state != "downloading":
		set_process(false)
		return
	var total := _http.get_body_size()
	if total <= 0:
		total = _download_size
	var got := _http.get_downloaded_bytes()
	var pct := int(100.0 * got / total) if total > 0 else 0
	_set_state("downloading", "İndiriliyor... %%%d  (%.0f / %.0f MB)" % [pct, got / 1048576.0, total / 1048576.0])


func _on_download_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	set_process(false)
	_http.download_file = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[Updater] indirme başarısız: result=%d code=%d" % [result, code])
		_fail("İndirme başarısız oldu.")
		return
	var f := FileAccess.open(_new_path, FileAccess.READ)
	var size := f.get_length() if f else 0
	if f:
		f.close()
	if size < 1048576 or (_download_size > 0 and size != _download_size):
		_fail("İndirilen dosya bozuk.")
		return
	_set_state("installing", "Kuruluyor...")
	var exe := OS.get_executable_path()
	var old := exe + ".old"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)
	# Windows çalışan exe'nin silinmesine izin vermez ama adının değiştirilmesine izin verir.
	var err := DirAccess.rename_absolute(exe, old)
	if err != OK:
		print("[Updater] eski exe taşınamadı: %d" % err)
		_fail("Oyun klasörüne yazılamıyor.")
		return
	err = DirAccess.rename_absolute(_new_path, exe)
	if err != OK:
		DirAccess.rename_absolute(old, exe)   # geri al
		_fail("Yeni sürüm yerine konamadı.")
		return
	print("[Updater] v%s kuruldu" % latest_version)
	_set_state("installing", "Yeniden başlatılıyor...")
	if not _user_arg("--update-no-restart"):
		OS.create_process(exe, [])
	get_tree().quit()


func _fail(text: String) -> void:
	if _new_path != "" and FileAccess.file_exists(_new_path):
		DirAccess.remove_absolute(_new_path)
	_set_state("failed", text)
	# Elle indirme için sürüm sayfası hâlâ açılabilsin
	if text != "":
		state = "available"
		state_changed.emit("error", text + " Sayfadan elle indirebilirsin.")
		_download_url = ""


func _set_state(s: String, text: String) -> void:
	state = s
	state_changed.emit(s, text)
