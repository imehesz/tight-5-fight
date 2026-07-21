extends Node
## Sponsor roster singleton (registered as "Sponsors" after Leaderboard).
## Loads website-for-all/sponsors/sponsors.json — HOSTED next to the games,
## not baked into the .pck, so signing a sponsor is: paste image, edit JSON,
## rsync the website. Every live edition picks it up on its next boot.
##
## Same best-effort contract as Leaderboard: sponsors are a garnish. If the
## fetch fails (offline, LAN playtest with no hosted copy) the street simply
## grows no billboards and the SPONSORS screen says so.

## Fired once loading settles (successfully or not) so late-opening screens
## (SPONSORS menu) can stop showing a spinner. Check `active` for the result.
signal sponsors_ready

## The hosted folder, same host rule as Leaderboard.base_url(): the deployed
## site and hub domains route to the real thing; anywhere else web-served has
## no hosted copy (and no CORS to fetch cross-origin), so ads just stay off.
const PROD_SPONSORS_URL := "https://games.imstandup.com/tight5fight/sponsors/"
## In the editor / a desktop dev run the project tree itself has the files
## (website-for-all is .gdignore'd, so raw FileAccess, never load()).
const LOCAL_SPONSORS_DIR := "website-for-all/sponsors/"
const TIMEOUT_SEC := 8.0

## Sponsors valid RIGHT NOW for THIS game, ad texture included:
## [{id, name, link, weight, texture: ImageTexture}]. Weight decides the
## share of billboard slots (30 vs 20 → 60%/40%); how often a billboard
## appears at all is street.gd's BILLBOARD_CHANCE.
var active: Array = []

enum { IDLE, LOADING, DONE, FAILED }
var _state := IDLE


func _ready() -> void:
	ensure_loaded()


## Kick off the one load per session — or retry it, if the last attempt
## couldn't reach the JSON at all. Called from _ready and again by every
## street/SPONSORS screen; a successful load (even of an empty roster) is
## never redone, so mid-session JSON edits need a page reload.
func ensure_loaded() -> void:
	if _state == LOADING or _state == DONE:
		return
	_state = LOADING
	_load_all()


func is_ready() -> bool:
	return _state == DONE or _state == FAILED


## Weighted pick for one billboard slot. Repeats across slots are fine (the
## street cycles anyway); an empty roster returns {}.
func pick_weighted() -> Dictionary:
	if active.is_empty():
		return {}
	var total := 0
	for s in active:
		total += int(s.weight)
	var roll := randi() % maxi(total, 1)
	for s in active:
		roll -= int(s.weight)
		if roll < 0:
			return s
	return active.back()


## Restore path for billboards saved in street_state: the id is persisted,
## the texture is not. {} when the sponsor vanished mid-session (can't
## happen within one page load, but the caller stays defensive).
func by_id(id: String) -> Dictionary:
	for s in active:
		if String(s.id) == id:
			return s
	return {}


# ---------------------------------------------------------------- loading
func _load_all() -> void:
	var parsed = await _fetch_json()
	if parsed == null:
		_state = FAILED
		sponsors_ready.emit()
		return
	var today := Time.get_date_string_from_system(true)  # UTC YYYY-MM-DD
	var loaded: Array = []
	for s in parsed.get("sponsors", []):
		if not s is Dictionary:
			continue
		if not _runs_today(s, today):
			continue
		var tex := await _fetch_ad_texture(String(s.get("imgLink", "")))
		if tex == null:
			continue
		loaded.append({
			"id": String(s.get("sponsorId", "")),
			"name": String(s.get("sponsorName", "")),
			"link": String(s.get("linkTo", "")),
			"weight": maxi(int(s.get("weight", 0)), 1),
			"texture": tex,
		})
	active = loaded
	_state = DONE
	sponsors_ready.emit()


## One sponsor's eligibility for this game, today. Dates are inclusive and
## compared lexicographically (safe for YYYY-MM-DD); a missing dateStart
## means "already running", a missing dateEnd means "until pulled".
func _runs_today(s: Dictionary, today: String) -> bool:
	if bool(s.get("isDisabled", false)):
		return false
	if String(s.get("sponsorId", "")) == "" or String(s.get("imgLink", "")) == "":
		return false
	var markets: Array = s.get("inMarkets", [])
	if not markets.has(GameState.active_game):
		return false
	var start := String(s.get("dateStart", ""))
	if start != "" and today < start:
		return false
	var end := String(s.get("dateEnd", ""))
	if end != "" and today > end:
		return false
	return true


## The sponsors.json body as a Dictionary, or null when it couldn't be
## reached/parsed (null → FAILED → a later ensure_loaded() retries; an empty
## roster is a Dictionary and sticks).
func _fetch_json() -> Variant:
	var local := _local_path("sponsors.json")
	if local != "":
		var f := FileAccess.open(local, FileAccess.READ)
		if f == null:
			return null
		var parsed = JSON.parse_string(f.get_as_text())
		return parsed if parsed is Dictionary else null
	if not _hosted_reachable():
		return null
	var body := await _http_get(PROD_SPONSORS_URL + "sponsors.json")
	if body.is_empty():
		return null
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	return parsed if parsed is Dictionary else null


## One ad image as a texture, null on any failure (bad path, bad bytes). A
## sponsor without a loadable image is skipped outright — an empty billboard
## sells nothing.
func _fetch_ad_texture(img_link: String) -> ImageTexture:
	if img_link == "" or img_link.contains(".."):
		return null
	var img := Image.new()
	var local := _local_path(img_link)
	if local != "":
		if img.load(local) != OK:
			return null
		return ImageTexture.create_from_image(img)
	var bytes := await _http_get(PROD_SPONSORS_URL + img_link)
	if bytes.is_empty():
		return null
	# Sniff the format from the bytes — a paste-renamed .png that is really
	# a JPEG must still load.
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.size() > 8 and bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes.size() > 2 and bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.size() > 12 and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)


## Absolute filesystem path to a sponsors file when this run can read the
## project tree directly (editor / dev desktop build run from the repo);
## "" otherwise. website-for-all/ is .gdignore'd so it never ships in a pck.
func _local_path(rel: String) -> String:
	if OS.has_feature("web"):
		return ""
	var p := ProjectSettings.globalize_path("res://") + LOCAL_SPONSORS_DIR + rel
	return p if FileAccess.file_exists(p) else ""


## Mirrors Leaderboard's host rule: only pages served from the real domains
## may fetch the hosted folder (anything else is cross-origin to a static
## file with no CORS headers, a guaranteed console error — don't try).
func _hosted_reachable() -> bool:
	if not OS.has_feature("web"):
		return true  # desktop export: plain HTTPS, no CORS in play
	var host := str(JavaScriptBridge.eval("window.location.hostname"))
	return host.ends_with("imstandup.com") or host.ends_with("mehesz.net")


## One GET, returning the raw body (empty on any failure). Same throwaway
## HTTPRequest pattern as Leaderboard._request.
func _http_get(url: String) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SEC
	add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return PackedByteArray()
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		return PackedByteArray()
	return result[3]
