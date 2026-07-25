# Privacy Policy — DRAFT, NOT FOR PUBLICATION AS-IS

This is a starting point, not a finished legal document. Every `[BRACKETED]`
field needs your actual information before this goes anywhere near an app
store listing or a real URL. I'm not a lawyer — have someone who is review
this before you publish it, especially the data-sharing and children's
sections if you ever target an under-13 audience (COPPA) or EU users (GDPR).

---

## Privacy Policy for Type Blast

**Last updated:** [DATE]

### What this app currently does

Based on the app as it stands today, Type Blast:

- Stores all gameplay progress (scores, streaks, achievements, settings)
  **locally on your device only**, via a save file in the app's private
  storage. Nothing is transmitted anywhere.
- Does not collect analytics, crash reports, or any usage data.
- Does not show ads.
- Does not offer in-app purchases.
- Does not require an account, login, or any personal information.
- Includes a "Daily Challenge" share feature that generates a short text
  code you can copy and share manually (e.g. via Messages) — this is
  user-initiated and the app itself never transmits it anywhere.

**If all of the above stays true**, your privacy policy can honestly be
very short: no data leaves the device, full stop. That's a genuinely good
position — most competing typing apps collect far more, and "we don't
collect anything" is both true and a selling point.

### If you add any of the following later, this document needs updating
**before** you ship that change, not after:

- Analytics or crash reporting SDK → add what's collected, and whether
  it's identifiable (device ID, IP) or aggregated
- Ads → name the ad network, link to their policy, disclose any
  ad-ID/tracking use
- IAP → name the payment processor (Apple/Google handle this, but
  disclose it)
- Cloud save / leaderboards (Game Center, Google Play Games) → disclose
  what's synced and that it's covered by the platform's own policy
- Any account/login system → disclose what's collected and how it's
  stored

### Contact

[YOUR NAME / STUDIO NAME]
[CONTACT EMAIL]

### Children's privacy

[If this app is directed at children under 13, you need COPPA-compliant
language here, and Apple/Google both have separate declarations you must
fill out in their consoles regardless of what this document says. Flag
this to a lawyer specifically — it's the area with the most legal exposure
for a low-effort mistake.]

### Changes to this policy

We may update this policy as the app changes. [Add how you'll notify
users of material changes, e.g. "check this page" or "in-app notice."]

---

## Practical notes for you, not part of the policy itself

- Both Apple App Store Connect and Google Play Console make you fill out
  a data-safety questionnaire independent of this document — answer it
  honestly based on the "what this app currently does" section above.
- You need a real URL to host this at (GitHub Pages works fine for a
  static privacy policy and is free) before either store will accept it.
- If the current "nothing leaves the device" state changes, update this
  file in the same PR/commit as the code change that changes it, so they
  never drift apart.
