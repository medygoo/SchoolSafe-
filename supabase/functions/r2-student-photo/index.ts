import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

// DRAFT #89 — signer minimal pour la photo d'un élève.
// L'autorisation métier n'est PAS dupliquée ici : elle vient de
// public.get_student_photo_file_ref() exécutée avec le JWT de l'appelant.

const DEFAULT_ORIGINS = [
  "https://medygoo.github.io",
  "https://cslesage.com",
  "https://www.cslesage.com",
  "https://app.cslesage.com",
  "http://localhost:3000",
  "http://localhost:5173",
  "http://127.0.0.1:3000",
  "http://127.0.0.1:5173",
];

type Json = Record<string, unknown>;

type PhotoRefResult = {
  ok?: boolean;
  code?: string;
  student_id?: string;
  file_id?: string;
  legacy_photo_present?: boolean;
};

type FileRecord = {
  id: string;
  owner_type: string;
  owner_id: string;
  category: string;
  storage_path: string;
  original_name: string;
  display_name: string | null;
  mime_type: string;
  archived_at: string | null;
  deleted_at: string | null;
};

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

function firstKey(raw: string): string {
  try {
    const parsed = JSON.parse(raw) as Record<string, string>;
    return parsed.default || Object.values(parsed)[0] || raw;
  } catch (_) {
    return raw;
  }
}

function publishableKey(): string {
  const direct = Deno.env.get("SUPABASE_ANON_KEY")?.trim() ||
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY")?.trim();
  if (direct) return direct;
  const grouped = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")?.trim();
  if (grouped) return firstKey(grouped);
  throw new Error("Missing Supabase publishable/anon key");
}

function serviceRoleKey(): string {
  const direct = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (direct) return direct;
  const grouped = Deno.env.get("SUPABASE_SECRET_KEYS")?.trim();
  if (grouped) return firstKey(grouped);
  throw new Error("Missing Supabase service role/secret key");
}

function allowedOrigins(): Set<string> {
  const configured = Deno.env.get("APP_ALLOWED_ORIGINS");
  return new Set(
    configured
      ? configured.split(",").map((value) => value.trim()).filter(Boolean)
      : DEFAULT_ORIGINS,
  );
}

function cors(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  if (origin && allowedOrigins().has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
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
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function safeFilename(value: string): string {
  return value.replace(/[\r\n"\\]/g, "_").slice(0, 160) || "photo";
}

function statusForContractCode(code: string): number {
  if (code === "FORBIDDEN" || code === "STUDENT_PHOTO_FORBIDDEN") return 403;
  if (code === "STUDENT_NOT_FOUND" || code === "STUDENT_PHOTO_NOT_SET") return 404;
  if (code === "STUDENT_ARCHIVED") return 409;
  return 400;
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("Origin");
  const requestId = crypto.randomUUID();

  if (request.method === "OPTIONS") {
    if (origin && !allowedOrigins().has(origin)) {
      return reply(origin, 403, { ok: false, code: "ORIGIN_NOT_ALLOWED", request_id: requestId });
    }
    return new Response(null, { status: 204, headers: cors(origin) });
  }

  if (request.method !== "POST") {
    return reply(origin, 405, { ok: false, code: "METHOD_NOT_ALLOWED", request_id: requestId });
  }
  if (origin && !allowedOrigins().has(origin)) {
    return reply(origin, 403, { ok: false, code: "ORIGIN_NOT_ALLOWED", request_id: requestId });
  }

  const authorization = request.headers.get("Authorization") || "";
  if (!authorization.startsWith("Bearer ")) {
    return reply(origin, 401, { ok: false, code: "AUTH_REQUIRED", request_id: requestId });
  }

  let body: Json;
  try {
    body = await request.json() as Json;
  } catch (_) {
    return reply(origin, 400, { ok: false, code: "INVALID_JSON", request_id: requestId });
  }

  const studentId = String(body.student_id || "").trim();
  if (!studentId || studentId.length > 160) {
    return reply(origin, 422, {
      ok: false,
      code: "VALIDATION_ERROR",
      field: "student_id",
      request_id: requestId,
    });
  }

  try {
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const userClient = createClient(supabaseUrl, publishableKey(), {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const admin = createClient(supabaseUrl, serviceRoleKey(), {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });

    // Authentifie réellement le JWT avant la RPC métier.
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) {
      return reply(origin, 401, { ok: false, code: "AUTH_INVALID", request_id: requestId });
    }

    // Source unique d'autorisation : PostgreSQL + current_app_role/current user.
    const { data: refData, error: refError } = await userClient.rpc(
      "get_student_photo_file_ref",
      { p_sid: studentId },
    );
    if (refError) {
      console.error("student photo ref RPC failed", { requestId, error: refError.message });
      return reply(origin, 500, {
        ok: false,
        code: "STUDENT_PHOTO_CONTRACT_ERROR",
        request_id: requestId,
      });
    }

    const ref = (refData || {}) as PhotoRefResult;
    if (!ref.ok) {
      const code = String(ref.code || "STUDENT_PHOTO_FORBIDDEN");
      return reply(origin, statusForContractCode(code), {
        ok: false,
        code,
        student_id: studentId,
        legacy_photo_present: Boolean(ref.legacy_photo_present),
        request_id: requestId,
      });
    }

    const fileId = String(ref.file_id || "").trim();
    if (!fileId || ref.student_id !== studentId) {
      return reply(origin, 500, {
        ok: false,
        code: "STUDENT_PHOTO_CONTRACT_INVALID",
        request_id: requestId,
      });
    }

    // Service role n'intervient qu'APRÈS l'autorisation métier, pour obtenir
    // le chemin R2. On revérifie la relation fichier/élève en défense en profondeur.
    const { data: fileData, error: fileError } = await admin
      .from("school_files")
      .select("id,owner_type,owner_id,category,storage_path,original_name,display_name,mime_type,archived_at,deleted_at")
      .eq("id", fileId)
      .maybeSingle();
    if (fileError) throw new Error(`File lookup failed: ${fileError.message}`);
    if (!fileData) {
      return reply(origin, 404, { ok: false, code: "PHOTO_FILE_NOT_FOUND", request_id: requestId });
    }

    const file = fileData as FileRecord;
    if (file.archived_at || file.deleted_at) {
      return reply(origin, 409, { ok: false, code: "PHOTO_FILE_UNAVAILABLE", request_id: requestId });
    }
    if (
      file.owner_type !== "student" ||
      file.owner_id !== studentId ||
      file.category !== "photo" ||
      !["image/jpeg", "image/png", "image/webp"].includes(file.mime_type)
    ) {
      return reply(origin, 403, {
        ok: false,
        code: "PHOTO_FILE_RELATION_MISMATCH",
        request_id: requestId,
      });
    }

    const s3 = new S3Client({
      endpoint: requiredEnv("R2_ENDPOINT").replace(/\/$/, ""),
      region: Deno.env.get("R2_REGION")?.trim() || "auto",
      forcePathStyle: true,
      credentials: {
        accessKeyId: requiredEnv("R2_ACCESS_KEY_ID"),
        secretAccessKey: requiredEnv("R2_SECRET_ACCESS_KEY"),
      },
    });

    const url = await getSignedUrl(
      s3,
      new GetObjectCommand({
        Bucket: requiredEnv("R2_BUCKET_NAME"),
        Key: file.storage_path,
        ResponseContentType: file.mime_type,
        ResponseContentDisposition: `inline; filename="${safeFilename(file.original_name)}"`,
      }),
      { expiresIn: 300 },
    );

    return reply(origin, 200, {
      ok: true,
      code: "STUDENT_PHOTO_READY",
      student_id: studentId,
      file_id: file.id,
      url,
      expires_in: 300,
      mime_type: file.mime_type,
      display_name: file.display_name || file.original_name,
      request_id: requestId,
    });
  } catch (error) {
    console.error("r2-student-photo failed", { requestId, error: String(error) });
    return reply(origin, 500, {
      ok: false,
      code: "STUDENT_PHOTO_SERVICE_ERROR",
      request_id: requestId,
    });
  }
});
