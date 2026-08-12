import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

const ORIGINS = new Set([
  "https://medygoo.github.io",
  "https://medt121.github.io",
  "https://cslesage.com",
  "https://www.cslesage.com",
  "http://localhost:3000",
  "http://localhost:5173",
  "http://127.0.0.1:3000",
  "http://127.0.0.1:5173",
]);

type Json = Record<string, unknown>;

function env(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function parseKeySet(raw: string | undefined): string[] {
  const value = raw?.trim();
  if (!value) return [];
  try {
    const parsed = JSON.parse(value) as Record<string, string>;
    return Object.values(parsed).filter(Boolean);
  } catch (_) {
    return [value];
  }
}

function publishableKeys(): string[] {
  return Array.from(new Set([
    ...parseKeySet(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")),
    ...parseKeySet(Deno.env.get("SUPABASE_ANON_KEY")),
  ])).filter(Boolean);
}

function publishableKey(): string {
  const keys = publishableKeys();
  if (!keys.length) throw new Error("Missing publishable key");
  return keys[0];
}

function secretKey(): string {
  const keys = [
    ...parseKeySet(Deno.env.get("SUPABASE_SECRET_KEYS")),
    ...parseKeySet(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")),
  ].filter(Boolean);
  if (!keys.length) throw new Error("Missing secret key");
  return keys[0];
}

function cors(origin: string | null): Record<string, string> {
  const h: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
  if (origin && ORIGINS.has(origin)) h["Access-Control-Allow-Origin"] = origin;
  return h;
}

function reply(origin: string | null, status: number, body: Json, requestId: string): Response {
  return new Response(JSON.stringify({ ...body, request_id: requestId }), {
    status,
    headers: {
      ...cors(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store, max-age=0",
      "Pragma": "no-cache",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Request-Id": requestId,
    },
  });
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

function clientIp(req: Request): string {
  return (
    req.headers.get("cf-connecting-ip") ||
    req.headers.get("x-real-ip") ||
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    "unknown"
  );
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const origin = req.headers.get("Origin");

  if (req.method === "OPTIONS") {
    if (origin && !ORIGINS.has(origin)) return reply(origin, 403, { ok: false, code: "ORIGIN_NOT_ALLOWED" }, requestId);
    return new Response(null, { status: 204, headers: cors(origin) });
  }
  if (req.method !== "POST") return reply(origin, 405, { ok: false, code: "METHOD_NOT_ALLOWED" }, requestId);
  if (origin && !ORIGINS.has(origin)) return reply(origin, 403, { ok: false, code: "ORIGIN_NOT_ALLOWED" }, requestId);

  const allowedKeys = publishableKeys();
  const apiKey = req.headers.get("apikey")?.trim() || "";
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim() || "";
  if (!allowedKeys.includes(apiKey) && !allowedKeys.includes(bearer)) {
    return reply(origin, 401, { ok: false, code: "CLIENT_KEY_REQUIRED" }, requestId);
  }

  let body: Json;
  try {
    body = await req.json() as Json;
  } catch (_) {
    return reply(origin, 400, { ok: false, code: "INVALID_JSON" }, requestId);
  }

  const identifier = String(body.identifier || "").trim();
  const password = String(body.password || "");
  const requestedChannel = String(body.channel || "").trim().toLowerCase();
  // ── LE CANAL `identifier` PASSE ENFIN — audit ChatGPT du 12 août ────────
  //
  // `resolve_school_login_identity` SAIT DÉJÀ résoudre `identifier`, `login` et
  // `alias` vers le même `auth_user_id` : ChatGPT l'a vérifié sur le Supabase
  // réel. Mais ce relais-ci retombait sur la chaîne vide pour tout ce qui
  // n'était ni `email` ni `phone`, et la ligne suivante refusait alors la
  // connexion avec `INVALID_CREDENTIALS` — **avant même d'appeler le RPC qui
  // avait la réponse**.
  //
  // Le navigateur envoyait déjà `channel:'identifier'` : une personne tapait
  // son abréviation ou son nom de connexion, parfaitement justes, et s'entendait
  // répondre que ses identifiants étaient incorrects. Un refus mal nommé envoie
  // ressaisir vingt fois un mot de passe qui n'a jamais été en cause.
  //
  // On ne devine PAS ici s'il s'agit des initiales ou du nom de connexion : le
  // relais ne lit pas `users`, et c'est tout son objet. Il transmet, le RPC
  // tranche.
  const channel = requestedChannel === "email"
    ? "email"
    : (["phone", "phone_whatsapp"].includes(requestedChannel) ? "phone"
      : (["identifier", "login", "alias"].includes(requestedChannel) ? "identifier" : ""));

  if (!identifier || identifier.length > 320 || !password || password.length > 256 || !channel) {
    return reply(origin, 401, { ok: false, code: "INVALID_CREDENTIALS" }, requestId);
  }

  const url = env("SUPABASE_URL");
  const admin = createClient(url, secretKey(), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

  const { data: resolvedData, error: resolveError } = await admin.rpc("resolve_school_login_identity", {
    p_identifier: identifier,
    p_channel: channel,
  });
  const resolved = (resolvedData || {}) as Json;
  const rawIdentifierKey = await sha256(`${channel}:${identifier.toLowerCase()}`);
  const identifierKey = typeof resolved.identifier_key === "string" ? resolved.identifier_key : rawIdentifierKey;
  const ipHash = await sha256(clientIp(req));
  const rateKey = await sha256(`${identifierKey}:${ipHash}`);

  const { data: rateData, error: rateError } = await admin.rpc("consume_school_login_attempt", {
    p_key_hash: rateKey,
  });
  const rate = (rateData || {}) as Json;
  if (rateError) {
    console.error("school-login rate failure", requestId, rateError.code || "RPC_ERROR");
    return reply(origin, 503, { ok: false, code: "LOGIN_TEMPORARILY_UNAVAILABLE" }, requestId);
  }
  if (rate.allowed !== true) {
    return reply(origin, 429, {
      ok: false,
      code: "TOO_MANY_ATTEMPTS",
      retry_after_seconds: rate.retry_after_seconds || 900,
    }, requestId);
  }

  if (resolveError || resolved.ok !== true || typeof resolved.auth_email !== "string") {
    await new Promise((resolve) => setTimeout(resolve, 220));
    return reply(origin, 401, { ok: false, code: "INVALID_CREDENTIALS" }, requestId);
  }

  const client = createClient(url, publishableKey(), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email: resolved.auth_email,
    password,
  });

  if (error || !data.session) {
    return reply(origin, 401, { ok: false, code: "INVALID_CREDENTIALS" }, requestId);
  }

  await admin.rpc("clear_school_login_attempts", { p_key_hash: rateKey });

  return reply(origin, 200, {
    ok: true,
    code: "LOGIN_OK",
    session: {
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
      expires_in: data.session.expires_in,
      expires_at: data.session.expires_at,
      token_type: data.session.token_type,
      user_id: data.user?.id || null,
    },
  }, requestId);
});
