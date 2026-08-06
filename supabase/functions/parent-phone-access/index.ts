import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

const ORIGINS = new Set([
  "https://medygoo.github.io",
  "https://medt121.github.io",
  "https://cslesage.com",
  "https://www.cslesage.com",
]);

type Json = Record<string, unknown>;
type Action = "provision" | "reset" | "change_phone";

function env(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function secretKey(): string {
  const raw = env("SUPABASE_SECRET_KEYS");
  try {
    const parsed = JSON.parse(raw) as Record<string, string>;
    return parsed.default || Object.values(parsed)[0] || raw;
  } catch (_) {
    return raw;
  }
}

function publishableKey(): string {
  const raw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")?.trim();
  if (!raw) return env("SUPABASE_ANON_KEY");
  try {
    const parsed = JSON.parse(raw) as Record<string, string>;
    return parsed.default || Object.values(parsed)[0] || raw;
  } catch (_) {
    return raw;
  }
}

function cors(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  if (origin && ORIGINS.has(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}

function reply(origin: string | null, status: number, data: Json): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...cors(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store, max-age=0",
      Pragma: "no-cache",
      "Referrer-Policy": "no-referrer",
    },
  });
}

function digits(length: number): string {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => String(byte % 10)).join("");
}

function temporaryCode(): string {
  return `Sa-${digits(4)}-${digits(4)}`;
}

function statusFor(code: string): number {
  if (["AUTH_REQUIRED", "INVALID_SESSION"].includes(code)) return 401;
  if (["FORBIDDEN", "ACTOR_NOT_FOUND"].includes(code)) return 403;
  if (["TARGET_NOT_FOUND", "REQUEST_NOT_FOUND"].includes(code)) return 404;
  if (["TOO_SOON", "PHONE_ACCESS_CONFLICT"].includes(code)) return 429;
  if (["PHONE_IN_USE", "ALREADY_LINKED", "ACCOUNT_NOT_LINKED", "TARGET_DISABLED"].includes(code)) return 409;
  return 400;
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("Origin");

  if (request.method === "OPTIONS") {
    if (origin && !ORIGINS.has(origin)) {
      return reply(origin, 403, { ok: false, code: "ORIGIN_NOT_ALLOWED" });
    }
    return new Response(null, { status: 204, headers: cors(origin) });
  }
  if (request.method !== "POST") {
    return reply(origin, 405, { ok: false, code: "METHOD_NOT_ALLOWED" });
  }
  if (origin && !ORIGINS.has(origin)) {
    return reply(origin, 403, { ok: false, code: "ORIGIN_NOT_ALLOWED" });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return reply(origin, 401, { ok: false, code: "AUTH_REQUIRED" });
  }

  const supabaseUrl = env("SUPABASE_URL");
  const userClient = createClient(supabaseUrl, publishableKey(), {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, secretKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) {
    return reply(origin, 401, { ok: false, code: "INVALID_SESSION" });
  }

  let body: Json;
  try {
    body = await request.json() as Json;
  } catch (_) {
    return reply(origin, 400, { ok: false, code: "INVALID_JSON" });
  }

  const appUserId = String(body.app_user_id || "").trim();
  const action = String(body.action || "").trim().toLowerCase() as Action;
  const requestedPhone = body.phone == null ? null : String(body.phone).trim();

  if (!appUserId || appUserId.length > 160) {
    return reply(origin, 400, { ok: false, code: "VALIDATION_ERROR", field: "app_user_id" });
  }
  if (!["provision", "reset", "change_phone"].includes(action)) {
    return reply(origin, 400, { ok: false, code: "VALIDATION_ERROR", field: "action" });
  }
  if (action === "change_phone" && !requestedPhone) {
    return reply(origin, 400, { ok: false, code: "VALIDATION_ERROR", field: "phone" });
  }

  const { data: prepared, error: prepareError } = await admin.rpc("prepare_parent_phone_access", {
    p_actor_auth_user_id: authData.user.id,
    p_app_user_id: appUserId,
    p_action: action,
    p_phone: requestedPhone,
  });

  if (prepareError) {
    console.error("parent-phone-access prepare", prepareError.code || "RPC_ERROR");
    return reply(origin, 500, { ok: false, code: "PREPARE_FAILED" });
  }

  const preparedData = prepared as Json;
  if (preparedData.ok !== true) {
    const code = String(preparedData.code || "PREPARE_REJECTED");
    return reply(origin, statusFor(code), {
      ok: false,
      code,
      field: preparedData.field,
      next_allowed_at: preparedData.next_allowed_at,
    });
  }

  const requestId = String(preparedData.request_id || "");
  const requestSecret = String(preparedData.request_secret || "");
  const phone = String(preparedData.phone || "");
  let authUserId = preparedData.auth_user_id ? String(preparedData.auth_user_id) : "";

  if (!requestId || !requestSecret || !phone) {
    return reply(origin, 500, { ok: false, code: "INVALID_PREPARE_RESPONSE" });
  }

  const code = temporaryCode();
  let accountUpdated = false;

  if (action === "provision") {
    const { data, error } = await admin.auth.admin.createUser({
      phone,
      password: code,
      phone_confirm: true,
      user_metadata: {
        school_phone_request_id: requestId,
        school_phone_request_secret: requestSecret,
        school_app_user_id: appUserId,
        access_channel: "phone_whatsapp",
      },
    });

    if (error || !data.user) {
      await admin.rpc("fail_parent_phone_access_request", {
        p_request_id: requestId,
        p_failure_code: error?.code || "AUTH_CREATE_FAILED",
      });
      const conflict = error?.status === 422 || error?.code === "phone_exists";
      return reply(origin, conflict ? 409 : 502, {
        ok: false,
        code: conflict ? "PHONE_IN_USE" : "AUTH_CREATE_FAILED",
      });
    }

    authUserId = data.user.id;
    accountUpdated = true;

    await admin.auth.admin.updateUserById(authUserId, {
      user_metadata: {
        school_app_user_id: appUserId,
        access_channel: "phone_whatsapp",
      },
    });
  } else {
    if (!authUserId) {
      return reply(origin, 409, { ok: false, code: "AUTH_LINK_MISSING" });
    }

    const attributes = action === "change_phone"
      ? { phone, phone_confirm: true, password: code }
      : { password: code };

    const { error } = await admin.auth.admin.updateUserById(authUserId, attributes);
    if (error) {
      await admin.rpc("fail_parent_phone_access_request", {
        p_request_id: requestId,
        p_failure_code: error.code || "AUTH_UPDATE_FAILED",
      });
      const conflict = error.status === 422 || error.code === "phone_exists";
      return reply(origin, conflict ? 409 : 502, {
        ok: false,
        code: conflict ? "PHONE_IN_USE" : "AUTH_UPDATE_FAILED",
      });
    }
    accountUpdated = true;
  }

  let finalized: Json | null = null;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const result = await admin.rpc("finalize_parent_phone_access", {
      p_request_id: requestId,
    });
    finalized = result.data as Json | null;
    if (!result.error && finalized?.ok === true) break;
    if (attempt === 0) await new Promise((resolve) => setTimeout(resolve, 150));
  }

  if (finalized?.ok !== true) {
    console.error("parent-phone-access finalize", String(finalized?.code || "RPC_ERROR"));
    return reply(origin, 500, {
      ok: false,
      code: "ACCOUNT_UPDATED_FINALIZE_FAILED",
      account_updated: accountUpdated,
      retry_after_seconds: 60,
    });
  }

  return reply(origin, 200, {
    ok: true,
    code: "PHONE_ACCESS_READY",
    action,
    phone,
    temporary_code: code,
    expires_at: finalized.expires_at || preparedData.expires_at,
    next_allowed_at: finalized.next_allowed_at,
    must_change_password: true,
    delivery_channel: "whatsapp_manual",
  });
});
