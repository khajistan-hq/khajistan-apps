# Subscribing from the apps

Owner, 2026-10-05, asked how people should subscribe from the apps: **both** — the website's
own checkout, and Apple's in-app purchase.

## 1. The website's checkout (works now)

The Reading Room sells All Access through `scripts/kj-join.js`: a signed-in reader is bound to
their account server-side by `stripe-checkout` and pays in an embedded Stripe sheet. A link to
`/reading-room.html?join=monthly` (or `annual`) resumes that checkout after sign-in.

- **iPhone:** the app draws no membership card of its own (owner, 2026-10-07: the Home card was
  too aggressive). The offer is the Reading Room page's own, in the in-app browser, on the US
  storefront only; elsewhere the page is opened with `app=1` and the site hides it.
- **Apple TV: sells nothing, in the app or through it.** Owner, 2026-10-06, to the Apple TV
  session: *"dont allow people to get reading room subscription on the apple tv app, make them go
  to our site for that"*. The TV's members' gate shows no plans and no prices, only that
  membership is on khajistan.com. The Apple TV app has no QR codes (removed 2026-10-06: they
  pointed at the password-gated host and carried the same review risk).
  - **Ruled 2026-10-06: plain text, no QR code.** Under App Review Guidelines 3.1.1 and 3.1.3,
    sending readers to buy outside the app, a QR code included, can be rejected. So the members'
    gate says membership is on khajistan.com, with no code and no call to action (owner, taking
    the Apple TV session's recommendation).

Prices are not written into either app. The site states them (All Access $49/month ·
$480/year, `reading-room.html`, measured 2026-10-05) and `kj_invariants.py` already guards that
the advertised price is the one Stripe charges; a third copy in an app would be one more place
to drift.

App Store note: pointing to an outside purchase is allowed on the US storefront (since May 2025);
elsewhere Apple requires its own purchase or the External Purchase Link entitlement. For an App
Store release outside the US: the Apple TV app has nothing to hide (no link, no QR code). The
iPhone/iPad app's "Become a member" buttons would need to be hidden on those storefronts, which
is not built, or §2 would be the route.

## 2. Apple in-app purchase (designed, NOT built)

**It does not apply to the Apple TV app**, which sells nothing in-app (owner, 2026-10-06, §1).
Whether the iPhone/iPad app should sell through Apple is not yet ruled.

**Corrected 2026-10-06.** This heading said "built in the app" until then. No branch of either
app imports StoreKit — checked on `app/tvos-reading`, `app/tvos-pigeon`, `app/tvos-native` and
the iOS branch `codex/ios-app-20260914`. What follows is the design, not a description of code.

Auto-renewable subscriptions in one group, **All Access**:

| product id | period |
|---|---|
| `com.khajistan.allaccess.monthly` | 1 month |
| `com.khajistan.allaccess.annual` | 1 year |

Client (StoreKit 2, to build): the purchase will carry `appAccountToken` = the signed-in Supabase user id, so
a renewal can always be tied back to the account. After a verified transaction the app will post the
signed transaction to the server; access is granted by the server, never by the app.

Server (lane **Bazaar**, which owns `stripe-checkout` / `stripe-webhook`; not built here, not
deployed from here — TEAM.md, safety §3):

- `apple-iap-verify` — takes the signed transaction from a signed-in app, verifies Apple's JWS
  chain, and upserts `reading_room_subscribers` (tier `all_access`, `expires_at` from the
  transaction, `notes` = `apple:<originalTransactionId>`).
- `apple-iap-webhook` — App Store Server Notifications v2: renewals, expiries, refunds and
  revocations move `expires_at` / `active` the same way `stripe-webhook` does for Stripe.
- Money-in before grant-out (backend §5): both deploy before the products are published.

## 3. What the owner does (none of it can be done by an agent)

1. Join the Apple Developer Program (US$99/yr).
2. In App Store Connect: create the app (bundle `com.khajistan.tv`, and `com.khajistan.archive`
   for iPhone), the subscription group and the two products, prices, and the agreements, tax
   and banking forms.
3. Create an App Store Server API key; put it in Supabase secrets for the Bazaar functions;
   set the notification URL to `apple-iap-webhook`.
4. Approve publishing — App Review, then release.
