# Darb route analytics functions

`aggregateCompletedMetroTrip` validates a completed metro trip, derives its
station pair, filters extreme outliers after four samples, and adds anonymous
statistics to a private analytics branch. `publishMetroRouteAnalytics` copies
only summary fields to `App/RouteAnalytics/metro/<from>__<to>` for the app.

Deploy from the repository root after selecting the correct Firebase project:

```powershell
cd functions
npm install
cd ..
firebase deploy --only functions
```

Before deployment, merge these rules into the existing Realtime Database
rules: users must only access their own `App/TravelHistory/<uid>` records;
clients may read `App/RouteAnalytics`; clients must never read or write
`App/RouteAnalyticsInternal`. Do not replace existing project rules wholesale.

The trigger begins aggregating new completed trips after deployment. Existing
trips need a separate, admin-only backfill if they should be included.
