# Subscribing from the apps

Owner, 2026-10-05, asked how people should subscribe from the apps: **both** — the website's
own checkout, and Apple's in-app purchase.

## 1. The website's checkout (works now)

The Reading Room sells All Access through `scripts/kj-join.js`: a signed-in reader is bound to
their account server-side by `stripe-checkout` and pays in an embedded Stripe sheet. A link to
`/reading-room.html?join=monthly` (or `annual`) resumes that checkout after sign-in.

- **iPhone:** a Subscribe control opens that URL in the in-app browser.
- **Apple TV:** tvOS has no browser, so the TV shows a QR code for the same URL; the viewer
  pays on their phone, and the TV sees the membership on its next check.

Prices are not written into either app. The site states them (All Access $49/month ·
$480/year, `reading-room.html`, measured 2026-10-05) and `kj_invariants.py` already guards that
the advertised price is the one Stripe charges; a third copy in an app would be one more place
to drift.

App Store note: pointing to an outside purchase is allowed on the US storefront (since May 2025);
elsewhere Apple requires its own purchase or the External Purchase Link entitlement. For an App
Store release outside the US, the QR/link is hidden on those storefronts and §2 is the route.

## 2. Apple in-app purchase (built in the app; live only after the owner's steps)

Auto-renewable subscriptions in one group, **All Access**:

| product id | period |
|---|---|
| `com.khajistan.allaccess.monthly` | 1 month |
| `com.khajistan.allaccess.annual` | 1 year |

Client (StoreKit 2): the purchase carries `appAccountToken` = the signed-in Supabase user id, so
a renewal can always be tied back to the account. After a verified transaction the app posts the
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
