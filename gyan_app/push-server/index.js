// ─────────────────────────────────────────────────────────────────────────────
// GYAN push server — free FCM sender (no Firebase Blaze plan needed).
//
// One tiny endpoint the app calls when a user sends a group invite or a study
// reminder. It verifies the caller (Firebase ID token), looks up the
// recipient's device tokens in Firestore, and sends the push via FCM.
//
// FCM itself is free; this just replaces the Cloud Function trigger that would
// have required Blaze. Deploy free on Render / Railway / Fly / a VPS.
//
// Required env vars:
//   SERVICE_ACCOUNT  → the FULL JSON of a Firebase service account key
//                      (Project Settings → Service accounts → Generate key),
//                      pasted as a single-line string.
//   PORT             → provided automatically by most hosts (defaults to 3000).
// ─────────────────────────────────────────────────────────────────────────────

const express = require("express");
const admin = require("firebase-admin");

admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(process.env.SERVICE_ACCOUNT)),
});

// Admin emails allowed to run /purge (comma-separated env var, lowercase).
const ADMIN_EMAILS = (process.env.ADMIN_EMAILS || "")
  .split(",")
  .map((e) => e.trim().toLowerCase())
  .filter(Boolean);

const app = express();
app.use(express.json());

// Health check (open this URL to confirm the server is up).
app.get("/", (_req, res) => res.send("GYAN push server is running."));

// Removes a user's Firestore data (group membership + their doc & subcollections).
// Never touches Firebase Auth accounts.
async function cleanupUser(uid) {
  const db = admin.firestore();
  const groups = await db
    .collection("study_groups")
    .where("memberUids", "array-contains", uid)
    .get();
  for (const g of groups.docs) {
    await g.ref.update({
      memberUids: admin.firestore.FieldValue.arrayRemove(uid),
    });
    await g.ref.collection("members").doc(uid).delete().catch(() => {});
  }
  await db.recursiveDelete(db.doc(`study_app_users/${uid}`));
}

app.post("/send", async (req, res) => {
  try {
    // 1) Authenticate the caller via their Firebase ID token.
    const authHeader = req.headers.authorization || "";
    const idToken = authHeader.startsWith("Bearer ")
      ? authHeader.slice(7)
      : "";
    if (!idToken) return res.status(401).json({ error: "missing token" });

    const caller = await admin.auth().verifyIdToken(idToken);
    if (!caller || caller.email_verified !== true) {
      return res.status(403).json({ error: "unverified caller" });
    }

    // 2) Build the message from the request.
    const { toUid, type, groupName, fromName } = req.body || {};
    if (!toUid || !type) {
      return res.status(400).json({ error: "missing fields" });
    }
    const from = fromName || "Someone";

    let title;
    let body;
    if (type === "group_invite") {
      title = "Group invitation";
      body = `${from} invited you to join "${groupName || "a group"}"`;
    } else if (type === "study_reminder") {
      title = "Study reminder";
      body = `${from} is nudging you to study. Time to focus! 💪`;
    } else {
      return res.status(400).json({ error: "unknown type" });
    }

    // 3) Look up the recipient's device tokens.
    const db = admin.firestore();
    const userRef = db.doc(`study_app_users/${toUid}`);
    const snap = await userRef.get();
    const tokens = (snap.get("fcmTokens") || []).filter(Boolean);
    if (tokens.length === 0) return res.json({ sent: 0 });

    // 4) Send + prune any invalid tokens.
    const result = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { type },
      android: {
        priority: "high",
        notification: { channelId: "gyan_default_channel" },
      },
      apns: { payload: { aps: { sound: "default" } } },
    });

    const stale = [];
    result.responses.forEach((r, i) => {
      if (!r.success) {
        const code = r.error && r.error.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-argument"
        ) {
          stale.push(tokens[i]);
        }
      }
    });
    if (stale.length) {
      await userRef.update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...stale),
      });
    }

    res.json({ sent: result.successCount });
  } catch (e) {
    console.error("send failed:", e);
    res.status(500).json({ error: "server error" });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Admin: clean up "orphan" user docs left behind when an account is deleted from
// Firebase Authentication (keeps the admin "Registered" count accurate without
// the Blaze plan). Deletes ONLY docs whose uid no longer exists in Auth — real
// users are always kept. Returns { purged, registered }.
// ─────────────────────────────────────────────────────────────────────────────
app.post("/purge", async (req, res) => {
  try {
    const authHeader = req.headers.authorization || "";
    const idToken = authHeader.startsWith("Bearer ")
      ? authHeader.slice(7)
      : "";
    if (!idToken) return res.status(401).json({ error: "missing token" });

    const caller = await admin.auth().verifyIdToken(idToken);
    const email = (caller.email || "").toLowerCase();
    if (caller.email_verified !== true || !ADMIN_EMAILS.includes(email)) {
      return res.status(403).json({ error: "admins only" });
    }

    const db = admin.firestore();
    const snap = await db.collection("study_app_users").get();
    let purged = 0;
    for (const d of snap.docs) {
      try {
        await admin.auth().getUser(d.id); // still a real account → keep
      } catch (e) {
        if (e.code === "auth/user-not-found") {
          await cleanupUser(d.id);
          purged++;
        }
      }
    }
    const after = await db.collection("study_app_users").count().get();
    res.json({ purged, registered: after.data().count });
  } catch (e) {
    console.error("purge failed:", e);
    res.status(500).json({ error: "server error" });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`GYAN push server listening on ${port}`));
