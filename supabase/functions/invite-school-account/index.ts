import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const ALLOWED_ORIGINS = new Set([
  "https://medygoo.github.io",
  "https://cslesage.com",
  "https://www.cslesage.com",
  "http://localhost:3000",
  "http://localhost:5173",
  "http://127.0.0.1:3000",
  "http://127.0.0.1:5173",
]);

const DEFAULT_REDIRECT = "https://medygoo.github.io/SchoolSafe-/auth.html";
const ALLOWED_REDIRECTS = new Set([
  DEFAULT_REDIRECT,
  "https://cslesage.com/auth.html",
  "https://www.cslesage.com/auth.html",
]);

function corsHeaders(origin: string | null): Record<string, string> {
  const allowed = origin && ALLOWED_ORIGINS.has(origin)
    ? origin
    : "https://medygoo.github.io";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function jsonResponse(
  status: number,
  body: Record<string, unknown>,
  origin: string | null,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function statusForCode(code: string): number {
  switch (code) {
    case "AUTH_REQUIRED":
    case "ACTOR_NOT_FOUND":
      return 401;
    case "FORBIDDEN":
      return 403;
    case "TARGET_NOT_FOUND":
      return 404;
    case "ALREADY_LINKED":
    case "EMAIL_IN_USE":
      return 409;
    case "TARGET_DISABLED":
    case "UNSUPPORTED_ROLE":
    case "VALIDATION_ERROR":
      return 422;
    default:
      return 400;
  }
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const origin = req.headers.get("origin");

  if (origin && !ALLOWED_ORIGINS.has(origin)) {
    return jsonResponse(403, {
      ok: false,
      code: "ORIGIN_FORBIDDEN",
      request_id: requestId,
    }, origin);
  }

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, {
      ok: false,
      code: "METHOD_NOT_ALLOWED",
      request_id: requestId,
    }, origin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (!supabaseUrl || !publishableKey || !serviceRoleKey) {
    console.error("invite-school-account missing server configuration", { requestId });
    return jsonResponse(500, {
      ok: false,
      code: "SERVER_CONFIGURATION_ERROR",
      request_id: requestId,
    }, origin);
  }

  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.startsWith("Bearer ")
    ? authHeader.slice(7).trim()
    : "";
  if (!token) {
    return jsonResponse(401, {
      ok: false,
      code: "AUTH_REQUIRED",
      request_id: requestId,
    }, origin);
  }

  const userClient = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });

  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) {
    return jsonResponse(401, {
      ok: false,
      code: "AUTH_INVALID",
      request_id: requestId,
    }, origin);
  }

  let input: Record<string, unknown>;
  try {
    input = await req.json();
  } catch {
    return jsonResponse(400, {
      ok: false,
      code: "INVALID_JSON",
      request_id: requestId,
    }, origin);
  }

  const appUserId = typeof input.app_user_id === "string"
    ? input.app_user_id.trim()
    : "";
  const email = typeof input.email === "string"
    ? input.email.trim().toLowerCase()
    : "";
  const requestedRedirect = typeof input.redirect_to === "string"
    ? input.redirect_to.trim()
    : "";
  const redirectTo = ALLOWED_REDIRECTS.has(requestedRedirect)
    ? requestedRedirect
    : DEFAULT_REDIRECT;

  if (!appUserId || !email || appUserId.length > 160 || email.length > 320) {
    return jsonResponse(422, {
      ok: false,
      code: "VALIDATION_ERROR",
      request_id: requestId,
    }, origin);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });

  const { data: prepared, error: prepareError } = await admin.rpc(
    "prepare_account_invitation",
    {
      p_actor_auth_user_id: authData.user.id,
      p_app_user_id: appUserId,
      p_email: email,
    },
  );

  if (prepareError) {
    console.error("prepare_account_invitation failed", {
      requestId,
      code: prepareError.code,
      message: prepareError.message,
    });
    return jsonResponse(500, {
      ok: false,
      code: "DB_PREPARE_FAILED",
      request_id: requestId,
    }, origin);
  }

  const contract = (prepared ?? {}) as Record<string, unknown>;
  if (contract.ok !== true) {
    const code = typeof contract.code === "string"
      ? contract.code
      : "INVITATION_REJECTED";
    return jsonResponse(statusForCode(code), {
      ok: false,
      code,
      field: contract.field ?? undefined,
      app_user_id: contract.app_user_id ?? undefined,
      request_id: requestId,
    }, origin);
  }

  const invitationId = typeof contract.invitation_id === "string"
    ? contract.invitation_id
    : "";
  const normalizedEmail = typeof contract.email === "string"
    ? contract.email
    : email;
  const fullName = typeof contract.full_name === "string"
    ? contract.full_name
    : "";
  const role = typeof contract.role === "string" ? contract.role : "";

  const { data: inviteData, error: inviteError } = await admin.auth.admin
    .inviteUserByEmail(normalizedEmail, {
      redirectTo,
      data: {
        app_user_id: appUserId,
        full_name: fullName,
        role,
        invitation_id: invitationId,
      },
    });

  if (inviteError || !inviteData.user) {
    console.error("Supabase Auth invitation failed", {
      requestId,
      status: inviteError?.status,
      code: inviteError?.code,
      message: inviteError?.message,
    });

    if (invitationId) {
      const { error: cleanupError } = await admin.rpc(
        "cancel_account_invitation",
        {
          p_actor_auth_user_id: authData.user.id,
          p_invitation_id: invitationId,
        },
      );
      if (cleanupError) {
        console.error("Invitation cleanup failed", {
          requestId,
          code: cleanupError.code,
          message: cleanupError.message,
        });
      }
    }

    return jsonResponse(502, {
      ok: false,
      code: "INVITE_FAILED",
      request_id: requestId,
    }, origin);
  }

  const { data: linkedUser, error: linkError } = await admin
    .from("users")
    .select("id, auth_user_id, email, role, status")
    .eq("id", appUserId)
    .maybeSingle();

  if (linkError || !linkedUser?.auth_user_id) {
    console.error("Auth user created but SchoolSafe linkage was not confirmed", {
      requestId,
      linkErrorCode: linkError?.code,
    });
    return jsonResponse(500, {
      ok: false,
      code: "LINK_NOT_CONFIRMED",
      request_id: requestId,
    }, origin);
  }

  return jsonResponse(201, {
    ok: true,
    code: "ACCOUNT_INVITED",
    app_user_id: linkedUser.id,
    auth_user_id: linkedUser.auth_user_id,
    email: linkedUser.email,
    role: linkedUser.role,
    status: linkedUser.status,
    request_id: requestId,
  }, origin);
});
