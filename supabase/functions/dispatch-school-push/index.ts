import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const ALLOWED_ORIGINS = new Set([
  "https://medygoo.github.io",
  "https://cslesage.com",
  "https://www.cslesage.com",
]);

function corsHeaders(origin: string | null): Record<string, string> {
  const allowed = origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://medygoo.github.io";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function jsonResponse(body: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function base64Url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const normalized = pem.replace(/\\n/g, "\n");
  const base64 = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function getGoogleAccessToken(clientEmail: string, privateKeyPem: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64Url(JSON.stringify({
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  ));
  const assertion = `${unsigned}.${base64Url(signature)}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok || typeof result.access_token !== "string") {
    throw new Error(`GOOGLE_OAUTH_FAILED:${response.status}`);
  }
  return result.access_token;
}

type ClaimedDelivery = {
  outbox_id: string;
  notification_id: string;
  device_id: string;
  provider: string;
  token: string;
  payload: {
    title?: string;
    body?: string;
    action_url?: string;
    data?: Record<string, unknown>;
  };
  attempt_no: number;
};

function stringData(data: Record<string, unknown> | undefined): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, value] of Object.entries(data ?? {})) {
    result[key] = value == null ? "" : typeof value === "string" ? value : JSON.stringify(value);
  }
  return result;
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (req.method !== "POST") return jsonResponse({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405, origin);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authorization = req.headers.get("Authorization") ?? "";
  const bearer = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !bearer) {
    return jsonResponse({ ok: false, code: "AUTH_REQUIRED" }, 401, origin);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let authorized = bearer === serviceRoleKey;
  if (!authorized) {
    const userClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authorization } },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser(bearer);
    if (authError || !authData.user) return jsonResponse({ ok: false, code: "AUTH_REQUIRED" }, 401, origin);
    const { data: appUser } = await admin
      .from("users")
      .select("id, role, status")
      .eq("auth_user_id", authData.user.id)
      .eq("status", "active")
      .maybeSingle();
    authorized = appUser?.role === "direction";
  }
  if (!authorized) return jsonResponse({ ok: false, code: "DIRECTION1_REQUIRED" }, 403, origin);

  const firebaseProjectId = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
  const firebaseClientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL") ?? "";
  const firebasePrivateKey = Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "";
  if (!firebaseProjectId || !firebaseClientEmail || !firebasePrivateKey) {
    return jsonResponse({
      ok: false,
      code: "PUSH_NOT_CONFIGURED",
      missing: [
        !firebaseProjectId ? "FIREBASE_PROJECT_ID" : null,
        !firebaseClientEmail ? "FIREBASE_CLIENT_EMAIL" : null,
        !firebasePrivateKey ? "FIREBASE_PRIVATE_KEY" : null,
      ].filter(Boolean),
    }, 503, origin);
  }

  let requestedLimit = 100;
  try {
    const body = await req.json();
    if (Number.isFinite(body?.limit)) requestedLimit = Math.max(1, Math.min(500, Number(body.limit)));
  } catch {
    // Empty body is valid.
  }

  let accessToken: string;
  try {
    accessToken = await getGoogleAccessToken(firebaseClientEmail, firebasePrivateKey);
  } catch {
    return jsonResponse({ ok: false, code: "FIREBASE_AUTH_FAILED" }, 502, origin);
  }

  const { data: claimed, error: claimError } = await admin.rpc("claim_notification_push_batch", { p_limit: requestedLimit });
  if (claimError) return jsonResponse({ ok: false, code: "CLAIM_FAILED" }, 500, origin);
  const deliveries = (claimed ?? []) as ClaimedDelivery[];

  let sent = 0;
  let failed = 0;
  let disabled = 0;
  const endpoint = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(firebaseProjectId)}/messages:send`;

  for (let offset = 0; offset < deliveries.length; offset += 10) {
    const chunk = deliveries.slice(offset, offset + 10);
    await Promise.all(chunk.map(async (delivery) => {
      const payload = delivery.payload ?? {};
      const actionUrl = typeof payload.action_url === "string" ? payload.action_url : "/?page=notifications";
      try {
        const response = await fetch(endpoint, {
          method: "POST",
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            message: {
              token: delivery.token,
              notification: {
                title: payload.title ?? "SchoolSafe",
                body: payload.body ?? "Une nouvelle information est disponible dans SchoolSafe.",
              },
              data: stringData(payload.data),
              webpush: { fcm_options: { link: actionUrl } },
              android: { priority: "high" },
              apns: { headers: { "apns-priority": "10" } },
            },
          }),
        });
        const responseText = await response.text();
        let providerMessageId = "";
        try { providerMessageId = JSON.parse(responseText)?.name ?? ""; } catch { /* no-op */ }
        if (response.ok) {
          sent++;
          await admin.rpc("complete_notification_push_delivery", {
            p_outbox_id: delivery.outbox_id,
            p_success: true,
            p_provider_message_id: providerMessageId,
            p_error: null,
            p_disable_device: false,
          });
          return;
        }
        const invalidToken = response.status === 404 || /UNREGISTERED|registration-token-not-registered/i.test(responseText);
        if (invalidToken) disabled++;
        failed++;
        await admin.rpc("complete_notification_push_delivery", {
          p_outbox_id: delivery.outbox_id,
          p_success: false,
          p_provider_message_id: null,
          p_error: `FCM_${response.status}:${responseText.slice(0, 600)}`,
          p_disable_device: invalidToken,
        });
      } catch (error) {
        failed++;
        await admin.rpc("complete_notification_push_delivery", {
          p_outbox_id: delivery.outbox_id,
          p_success: false,
          p_provider_message_id: null,
          p_error: `NETWORK_ERROR:${error instanceof Error ? error.message.slice(0, 400) : "unknown"}`,
          p_disable_device: false,
        });
      }
    }));
  }

  return jsonResponse({ ok: true, code: "PUSH_BATCH_DISPATCHED", claimed: deliveries.length, sent, failed, disabled }, 200, origin);
});
