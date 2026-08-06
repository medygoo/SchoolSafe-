import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type Json = Record<string, unknown>;

const ORIGINS = new Set([
  "https://medygoo.github.io",
  "https://cslesage.com",
  "https://www.cslesage.com",
  "http://localhost:3000",
  "http://localhost:5173",
  "http://127.0.0.1:3000",
  "http://127.0.0.1:5173",
]);

function env(name: string): string {
  const value = Deno.env.get(name) ?? "";
  if (!value) throw new Error(`Missing ${name}`);
  return value;
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

function reply(origin: string | null, status: number, data: Json): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...cors(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store, max-age=0",
      "Pragma": "no-cache",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function statusFor(code: string): number {
  if (["AUTH_REQUIRED", "AUTH_INVALID", "ACTOR_NOT_FOUND"].includes(code)) return 401;
  if (code === "FORBIDDEN") return 403;
  if (code === "TARGET_NOT_FOUND") return 404;
  if (["CANNOT_REMOVE_CURRENT_ACCOUNT", "LAST_DIRECTION_ACCOUNT"].includes(code)) return 409;
  if (["VALIDATION_ERROR", "INVALID_REASON"].includes(code)) return 422;
  return 400;
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const origin = req.headers.get("Origin");

  if (req.method === "OPTIONS") {
    if (origin && !ORIGINS.has(origin)) {
      return reply(origin, 403, { ok: false, code: "ORIGIN_NOT_ALLOWED", request_id: requestId });
    }
    return new Response(null, { status: 204, headers: cors(origin) });
  }

  if (req.method !== "POST") {
    return reply(origin, 405, { ok: false, code: "METHOD_NOT_ALLOWED", request_id: requestId });
  }
  if (origin && !ORIGINS.has(origin)) {
    return reply(origin, 403, { ok: false, code: "ORIGIN_NOT_ALLOWED", request_id: requestId });
  }

  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return reply(origin, 401, { ok: false, code: "AUTH_REQUIRED", request_id: requestId });
  }

  let body: Json;
  try {
    body = await req.json() as Json;
  } catch {
    return reply(origin, 400, { ok: false, code: "INVALID_JSON", request_id: requestId });
  }

  const appUserId = String(body.app_user_id ?? "").trim();
  const reason = String(body.reason ?? "").trim();
  if (!appUserId || appUserId.length > 160) {
    return reply(origin, 422, { ok: false, code: "VALIDATION_ERROR", field: "app_user_id", request_id: requestId });
  }
  if (reason.length < 5 || reason.length > 500) {
    return reply(origin, 422, { ok: false, code: "INVALID_REASON", field: "reason", request_id: requestId });
  }

  let url: string;
  let publishableKey: string;
  let serviceRoleKey: string;
  try {
    url = env("SUPABASE_URL");
    publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ?? env("SUPABASE_PUBLISHABLE_KEY");
    serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY");
  } catch (error) {
    console.error("remove-school-account configuration error", { requestId, error: String(error) });
    return reply(origin, 500, { ok: false, code: "SERVER_CONFIGURATION_ERROR", request_id: requestId });
  }

  const userClient = createClient(url, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const admin = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) {
    return reply(origin, 401, { ok: false, code: "AUTH_INVALID", request_id: requestId });
  }

  const { data: preparedData, error: prepareError } = await admin.rpc("prepare_school_account_removal", {
    p_actor_auth_user_id: authData.user.id,
    p_app_user_id: appUserId,
    p_reason: reason,
  });

  if (prepareError) {
    console.error("prepare_school_account_removal failed", {
      requestId,
      code: prepareError.code,
      message: prepareError.message,
    });
    return reply(origin, 500, { ok: false, code: "REMOVAL_PREPARE_FAILED", request_id: requestId });
  }

  const prepared = (preparedData ?? {}) as Json;
  if (prepared.ok !== true) {
    const code = String(prepared.code ?? "REMOVAL_REJECTED");
    return reply(origin, statusFor(code), { ok: false, code, request_id: requestId });
  }

  const authUserId = prepared.auth_user_id == null ? "" : String(prepared.auth_user_id);
  const expectedAuthUserId = prepared.removed_auth_user_id == null
    ? (authUserId || null)
    : String(prepared.removed_auth_user_id);

  if (authUserId) {
    const { error: deleteError } = await admin.auth.admin.deleteUser(authUserId);
    if (deleteError) {
      const { data: lookupData, error: lookupError } = await admin.auth.admin.getUserById(authUserId);
      if (!lookupError && lookupData.user) {
        console.error("Auth deletion failed and identity still exists", {
          requestId,
          status: deleteError.status,
          code: deleteError.code,
          message: deleteError.message,
        });
        return reply(origin, 502, {
          ok: false,
          code: "AUTH_DELETE_FAILED",
          access_disabled: true,
          retryable: true,
          request_id: requestId,
        });
      }
    }
  }

  const { data: confirmedData, error: confirmError } = await admin.rpc("confirm_school_account_removal", {
    p_actor_auth_user_id: authData.user.id,
    p_app_user_id: appUserId,
    p_expected_auth_user_id: expectedAuthUserId,
  });

  if (confirmError) {
    console.error("confirm_school_account_removal failed", {
      requestId,
      code: confirmError.code,
      message: confirmError.message,
    });
    return reply(origin, 500, {
      ok: false,
      code: "REMOVAL_CONFIRM_FAILED",
      access_disabled: true,
      request_id: requestId,
    });
  }

  const confirmed = (confirmedData ?? {}) as Json;
  if (confirmed.ok !== true) {
    const code = String(confirmed.code ?? "REMOVAL_NOT_CONFIRMED");
    return reply(origin, 409, {
      ok: false,
      code,
      access_disabled: true,
      request_id: requestId,
    });
  }

  return reply(origin, 200, {
    ok: true,
    code: "ACCOUNT_ACCESS_REMOVED",
    app_user_id: appUserId,
    status: confirmed.status ?? "inactive",
    access_removed_at: confirmed.access_removed_at ?? prepared.access_removed_at,
    request_id: requestId,
  });
});
