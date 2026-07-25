# iOS export — what's scaffolded vs. what you still need to do

`export_presets.cfg` now has a `[preset.2]` "iOS" entry alongside Android and
Web, with the same bundle identifier style as Android
(`com.emmanuel.keyslearning`), the app icon wired to your existing 1024x1024
asset, and sane defaults (min iOS 13, Wi-Fi capability on, Game
Center/push notifications off since nothing in the game uses them yet).

## What I could NOT fill in (needs your Apple Developer account)

These fields are blank on purpose — they're account-specific and I have no
way to know them:

- `application/app_store_team_id` — your 10-character Apple Developer Team ID
- `application/provisioning_profile_uuid_debug` / `_release` — from a
  provisioning profile you create in the Apple Developer portal (or let
  Xcode automanage after you set the Team ID)
- `application/code_sign_identity_debug` / `_release` — matches whatever
  certificate name Xcode shows once you've added your account there

## Steps to actually get a build out

1. Join the Apple Developer Program (paid, $99/yr) if you haven't.
2. In Godot's editor: **Editor > Manage Export Templates**, install the iOS
   export templates matching your Godot version (needed on top of the
   Android/Web ones you likely already have).
3. **Export > iOS preset > Options**, fill in the Team ID field — Godot will
   then let Xcode auto-manage signing for you in most cases, so you may not
   need to hand-enter the provisioning profile UUID / signing identity at
   all.
4. Godot's iOS export produces an Xcode project, not a submittable .ipa
   directly — you export from Godot, then open the generated Xcode project
   on a Mac to do the actual archive/upload to App Store Connect.
5. You'll need a Mac (or a cloud Mac service) for that last step — there's
   no way around this, it's an Apple requirement, not a Godot limitation.

## Also worth doing before you submit

- `privacy/*_usage_description` fields are blank — only required if you end
  up using camera/mic/photo library. Nothing in the game touches those
  right now, so leave them blank unless that changes.
- Double check `application/min_ios_version="13.0"` still matches whatever
  Godot 4.6's actual minimum supported iOS version is by the time you
  export — this can drift between Godot releases.
