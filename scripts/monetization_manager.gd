class_name MonetizationManager
extends Node

## Ads + donations. Instantiated once at startup by main.gd
## (init_ads() called there), used by MoreScreen's Settings panel for
## Support the Game.
##
## ADS are wired to the Poing Studios AdMob plugin already sitting in
## addons/admob, using real ad unit IDs (INTERSTITIAL_AD_ID /
## REWARDED_AD_ID below) and real App ID (addons/admob/android/config.gd)
## from the Type Blast AdMob app. Ads are fully configured — nothing
## left to wire in code-side.
## NOTE: AdMob showed a "payment setup incomplete" warning on your
## account — until you add a payment profile in AdMob, your app won't
## be approved for real (non-test) ad serving, so finish that in the
## AdMob console before shipping.
##
## There is no "Remove Ads" purchase — ads always show, gated only by
## should_show_ads() below (which is now a permanent `true`, kept as a
## single call site in case you want to reintroduce a paid tier later).
##
## DONATION ("Support the Game") needs no SDK at all — it just opens
## your Ko-fi / PayPal.me / Patreon link in the device browser. Set
## DONATION_URL below to your real page.

signal ads_initialized()
signal interstitial_ready()
signal interstitial_dismissed()
signal rewarded_ad_completed(reward_type: String)
signal rewarded_ad_failed(reason: String)
signal donation_page_opened()

## True once MobileAds.initialize()'s callback has actually fired.
## Every ad-display method no-ops (and logs a warning) while this is
## false, so calling into ad display before init finishes fails safely
## instead of crashing.
var _sdk_ready := false

## Real AdMob ad unit IDs for the Type Blast Android app
## (admob.google.com > Apps > Type Blast > Ad units).
const INTERSTITIAL_AD_ID := "ca-app-pub-5705446042606347/2281033610"
const REWARDED_AD_ID := "ca-app-pub-5705446042606347/5257862385"

const DONATION_URL := "https://paystack.shop/pay/rmlsk0w8-k"

var _interstitial_ad: InterstitialAd
var _rewarded_ad: RewardedAd
var _interstitial_loading := false
var _rewarded_loading := false
var _pending_reward_type := ""

var _interstitial_load_callback := InterstitialAdLoadCallback.new()
var _interstitial_content_callback := FullScreenContentCallback.new()
var _rewarded_load_callback := RewardedAdLoadCallback.new()
var _rewarded_content_callback := FullScreenContentCallback.new()
var _reward_listener := OnUserEarnedRewardListener.new()


func _ready() -> void:
	_interstitial_load_callback.on_ad_loaded = _on_interstitial_loaded
	_interstitial_load_callback.on_ad_failed_to_load = _on_interstitial_failed_to_load

	_interstitial_content_callback.on_ad_dismissed_full_screen_content = func() -> void:
		_interstitial_ad = null
		interstitial_dismissed.emit()
		_load_interstitial()
	_interstitial_content_callback.on_ad_failed_to_show_full_screen_content = func(err: AdError) -> void:
		ErrorLogger.log_warning("Interstitial failed to show", err.message)
		_interstitial_ad = null
		interstitial_dismissed.emit()
		_load_interstitial()

	_rewarded_load_callback.on_ad_loaded = _on_rewarded_loaded
	_rewarded_load_callback.on_ad_failed_to_load = _on_rewarded_failed_to_load

	_rewarded_content_callback.on_ad_dismissed_full_screen_content = func() -> void:
		_rewarded_ad = null
		_load_rewarded()
	_rewarded_content_callback.on_ad_failed_to_show_full_screen_content = func(err: AdError) -> void:
		rewarded_ad_failed.emit("show_failed: " + err.message)
		_rewarded_ad = null
		_load_rewarded()

	_reward_listener.on_user_earned_reward = _on_user_earned_reward


## Call once at startup (from main.gd, after everything else is set up).
func init_ads() -> void:
	var on_init_listener := OnInitializationCompleteListener.new()
	on_init_listener.on_initialization_complete = _on_mobile_ads_initialized

	var request_config := RequestConfiguration.new()
	# General-audience app: leave content rating at G unless you've
	# specifically confirmed Type Blast targets children, in which case
	# also set tag_for_child_directed_treatment / tag_for_under_age_of_consent.
	request_config.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_G
	MobileAds.set_request_configuration(request_config)
	MobileAds.initialize(on_init_listener)


func _on_mobile_ads_initialized(_status: InitializationStatus) -> void:
	_sdk_ready = true
	ads_initialized.emit()
	_load_interstitial()
	_load_rewarded()


## --- Interstitial ---

func _load_interstitial() -> void:
	if _interstitial_loading or _interstitial_ad != null:
		return
	_interstitial_loading = true
	InterstitialAdLoader.new().load(INTERSTITIAL_AD_ID, AdRequest.new(), _interstitial_load_callback)


func _on_interstitial_loaded(ad: InterstitialAd) -> void:
	_interstitial_loading = false
	ad.full_screen_content_callback = _interstitial_content_callback
	_interstitial_ad = ad
	interstitial_ready.emit()


func _on_interstitial_failed_to_load(error: LoadAdError) -> void:
	_interstitial_loading = false
	ErrorLogger.log_warning("Interstitial failed to load", error.message)


## Show an interstitial ad. Called from main.gd after each run ends,
## gated by should_show_ads() so it's automatically skipped once the
## player has purchased remove-ads. If none is loaded yet (e.g. still
## loading, or the previous one hasn't finished loading a replacement),
## this safely no-ops and kicks off a fresh load for next time.
func show_interstitial() -> void:
	if not _sdk_ready:
		ErrorLogger.log_warning("show_interstitial() called", "SDK not initialized yet — no-op")
		return
	if _interstitial_ad:
		_interstitial_ad.show()
	else:
		ErrorLogger.log_warning("show_interstitial() called", "No interstitial loaded yet — no-op")
		_load_interstitial()


## --- Rewarded ---

func _load_rewarded() -> void:
	if _rewarded_loading or _rewarded_ad != null:
		return
	_rewarded_loading = true
	RewardedAdLoader.new().load(REWARDED_AD_ID, AdRequest.new(), _rewarded_load_callback)


func _on_rewarded_loaded(ad: RewardedAd) -> void:
	_rewarded_loading = false
	ad.full_screen_content_callback = _rewarded_content_callback
	_rewarded_ad = ad


func _on_rewarded_failed_to_load(error: LoadAdError) -> void:
	_rewarded_loading = false
	ErrorLogger.log_warning("Rewarded ad failed to load", error.message)


func _on_user_earned_reward(_item: RewardedItem) -> void:
	rewarded_ad_completed.emit(_pending_reward_type)


## Show a rewarded ad, e.g. "watch an ad for a free power-up".
## reward_type is a caller-defined string (e.g. "extra_life",
## "power_up") echoed back on rewarded_ad_completed so the caller knows
## what to grant.
func show_rewarded_ad(reward_type: String) -> void:
	if not _sdk_ready:
		rewarded_ad_failed.emit("SDK not initialized")
		return
	if not _rewarded_ad:
		rewarded_ad_failed.emit("no_fill")
		_load_rewarded()
		return
	_pending_reward_type = reward_type
	_rewarded_ad.show(_reward_listener)


## Whether ads should be shown at all. There's no paid "remove ads"
## tier anymore, so this is always true — kept as a function (rather
## than inlining `true` at each call site) so a future paid tier could
## be reintroduced here without touching callers.
func should_show_ads(_game_state: GameState) -> bool:
	return true


## --- Donations ---
## No SDK needed — just opens the player's browser to your donation
## page. Works today, on every platform.

func open_donation_page() -> void:
	OS.shell_open(DONATION_URL)
	AnalyticsManager.log_event("donation_page_opened", {})
	donation_page_opened.emit()
