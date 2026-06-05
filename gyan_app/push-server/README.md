# GYAN push server (free, no Blaze)

A tiny endpoint that sends FCM push notifications for group invites and study
reminders. FCM is free; this replaces the Cloud Function that would have needed
the Blaze plan.

## 1. Get a service account key
Firebase Console → ⚙ Project settings → **Service accounts** →
**Generate new private key**. This downloads a JSON file.

## 2. Deploy free on Render (easiest)
1. Push this repo to GitHub.
2. On https://render.com → **New → Web Service** → pick your repo.
3. Settings:
   - **Root Directory:** `gyan_app/push-server`
   - **Build Command:** `npm install`
   - **Start Command:** `npm start`
   - **Instance type:** Free
4. **Environment → Add Environment Variable:**
   - Key: `SERVICE_ACCOUNT`
   - Value: paste the **entire contents** of the JSON file from step 1
     (one line is fine).
5. Deploy. You'll get a URL like `https://gyan-push.onrender.com`.
   Open it in a browser — it should say "GYAN push server is running."

(The same code also runs on Railway, Fly.io, a VPS, or Vercel — Render is just
the simplest free option. Note: Render's free tier sleeps when idle, so the
first notification after a quiet period may take a few seconds.)

## 3. Point the app at it
In the app's `.env` file, add:

```
PUSH_ENDPOINT=https://YOUR-RENDER-URL.onrender.com/send
```

Rebuild the app. Done — invites and study reminders now push to phones, free.

## Notes
- Leave `PUSH_ENDPOINT` empty/unset and the app simply skips the push (in-app
  notifications still work). So nothing breaks before you deploy this.
- Security: the endpoint verifies the caller's Firebase ID token, so only
  signed-in, verified users of your app can trigger a send.
