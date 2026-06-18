# Deploy once → APK works for everyone (zero setup)

The app talks to a backend server. For a shared APK to "just work" anywhere,
the backend + database must be hosted publicly **once**. After that, every
release APK connects automatically — no "Server settings", no IP, nothing.

> Why this is required: a mobile app on someone else's phone cannot reach a
> server running on your PC (`192.168.x.x` is only your local Wi‑Fi). The only
> permanent fix is a public URL.

---

## A. Host the backend (Railway — Node + MySQL together, easiest)

1. **Push the repo to GitHub.**

2. **Railway** (https://railway.app) → *New Project* → *Provision MySQL*.

3. **Load the schema** into that MySQL (one time). Open the MySQL service →
   *Connect* → copy the connection details, then run from your PC:
   ```bash
   mysql -h <DB_HOST> -P <DB_PORT> -u <DB_USER> -p<DB_PASSWORD> <DB_NAME> < server/schema.sql
   ```
   (or paste `server/schema.sql` into any MySQL client connected to it.)

4. **Add the API service**: Railway → *New* → *GitHub Repo* → pick this repo.
   - **Root directory:** `server`
   - **Start command:** `npm start`

5. **Set env vars** on the API service (Variables tab) — take the DB values
   from the Railway MySQL service:
   ```
   DB_HOST      = <from Railway MySQL>
   DB_PORT      = <from Railway MySQL>
   DB_USER      = <from Railway MySQL>
   DB_PASSWORD  = <from Railway MySQL>
   DB_NAME      = <from Railway MySQL>
   DB_SSL       = true
   JWT_SECRET   = <any long random string>
   ALLOW_DEV_SEED = true        # temporary, for step 7
   ```
   (Railway sets `PORT` automatically; the server already reads it and binds 0.0.0.0.)

6. **Deploy.** Railway gives a public URL like `https://gym-api-production.up.railway.app`.
   Test it in a browser — it should respond.

7. **Create your gym + admin login** (one time). From your PC:
   ```bash
   curl -X POST https://YOUR-URL/dev/seed \
     -H "Content-Type: application/json" \
     -d '{"tenantSlug":"demo","tenantName":"Demo Gym","adminEmail":"admin@demo.com","adminPassword":"admin123","adminName":"Owner"}'
   ```

8. **Lock it down.** Add env var `NODE_ENV = production` (this disables
   `/dev/seed`) and optionally remove `ALLOW_DEV_SEED`. Redeploy.

---

## B. Point the app at it (one line)

In `lib/src/core/providers.dart` set:
```dart
const kProductionApiUrl = 'https://YOUR-URL';   // your Railway URL, no trailing slash
```

Then build the shareable APK:
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

Send that APK to anyone. It opens and connects automatically — **no setup on
their side.** They just log in with the credentials from step 7.

---

## Notes
- The in-app **"Server settings"** field still exists as an optional override,
  but recipients never need it once `kProductionApiUrl` is set.
- Other hosts work too (Render/Fly/VPS): same env vars, same `npm start`,
  binds `0.0.0.0`, reads `PORT`. Use any managed MySQL (Aiven/PlanetScale) and
  set `DB_SSL=true`.
- HTTPS is recommended; cleartext HTTP is already allowed in the Android
  manifest for flexibility.
