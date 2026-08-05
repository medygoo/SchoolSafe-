import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import { GetObjectCommand, ListObjectsV2Command, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const DEFAULT_ORIGINS = [
  "https://medygoo.github.io",
  "https://medt121.github.io",
  "https://cslesage.com",
  "https://www.cslesage.com",
];
const OWNER_TYPES = new Set([
  "student", "user", "authorized_person", "class", "school", "devoir",
  "cahier_prep", "administrative_document",
]);
const CATEGORIES = new Set([
  "document", "photo", "identity", "card", "receipt", "homework",
  "report", "archive", "teacher_preparation", "administrative_document",
]);

type Json = Record<string, unknown>;

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

function defaultSupabaseKey(name: string): string {
  const raw = requiredEnv(name);
  try {
    const parsed = JSON.parse(raw) as Record<string, string>;
    return parsed.default || Object.values(parsed)[0] || raw;
  } catch (_) {
    return raw;
  }
}

function origins(): Set<string> {
  const configured = Deno.env.get("APP_ALLOWED_ORIGINS");
  return new Set(configured
    ? configured.split(",").map((v) => v.trim()).filter(Boolean)
    : DEFAULT_ORIGINS);
}

function cors(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
  if (origin && origins().has(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}

function respond(data: Json, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...cors(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function safeFilename(value: string): string {
  return value.replace(/[\r\n"\\]/g, "_").slice(0, 160) || "document";
}

function normalizeRole(role: string | null | undefined): string {
  if (role === "direction_pedagogique") return "direction2";
  if (role === "caisse") return "direction3";
  return role || "";
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("Origin");
  if (request.method === "OPTIONS") {
    if (origin && !origins().has(origin)) return respond({ error: "Origin not allowed" }, 403, origin);
    return new Response(null, { status: 204, headers: cors(origin) });
  }
  if (request.method !== "POST") return respond({ error: "Method not allowed" }, 405, origin);
  if (origin && !origins().has(origin)) return respond({ error: "Origin not allowed" }, 403, origin);

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return respond({ error: "Authentication required" }, 401, origin);

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")
      ? defaultSupabaseKey("SUPABASE_PUBLISHABLE_KEYS")
      : requiredEnv("SUPABASE_ANON_KEY");
    const secretKey = defaultSupabaseKey("SUPABASE_SECRET_KEYS");
    const userClient = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const admin = createClient(supabaseUrl, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return respond({ error: "Invalid session" }, 401, origin);
    const authId = authData.user.id;

    const { data: appUser, error: userError } = await admin
      .from("users")
      .select("id,role,status")
      .eq("auth_user_id", authId)
      .maybeSingle();
    if (userError) throw new Error(`Identity lookup failed: ${userError.message}`);

    let isDirection = Boolean(appUser?.status === "active" && normalizeRole(appUser.role) === "direction");
    if (!isDirection) {
      const { data: profile, error: profileError } = await admin
        .from("profiles")
        .select("role,status")
        .eq("id", authId)
        .maybeSingle();
      if (profileError) throw new Error(`Profile lookup failed: ${profileError.message}`);
      isDirection = Boolean(profile?.status === "active" && normalizeRole(profile.role) === "direction");
    }
    if (!isDirection) return respond({ error: "Direction 1 access required" }, 403, origin);

    const endpoint = requiredEnv("R2_ENDPOINT").replace(/\/$/, "");
    const bucket = requiredEnv("R2_BUCKET_NAME");
    const s3 = new S3Client({
      endpoint,
      region: Deno.env.get("R2_REGION")?.trim() || "auto",
      forcePathStyle: true,
      credentials: {
        accessKeyId: requiredEnv("R2_ACCESS_KEY_ID"),
        secretAccessKey: requiredEnv("R2_SECRET_ACCESS_KEY"),
      },
    });

    const payload = (await request.json()) as Json;
    const action = String(payload.action || "");

    if (action === "health") {
      await s3.send(new ListObjectsV2Command({ Bucket: bucket, MaxKeys: 1 }));
      return respond({ ok: true, connected: true, bucket, archive_schema_version: 1 }, 200, origin);
    }

    if (action === "summary") {
      const { data, error } = await userClient.rpc("get_archive_summary");
      if (error) throw new Error(`Archive summary failed: ${error.message}`);
      return respond({ ok: true, years: data || [] }, 200, origin);
    }

    if (action === "list") {
      const academicYear = String(payload.academic_year || "").trim();
      const ownerType = String(payload.owner_type || "").trim();
      const ownerId = String(payload.owner_id || "").trim();
      const category = String(payload.category || "").trim();
      const requestedPage = Number(payload.page || 1);
      const requestedLimit = Number(payload.limit || 50);
      const page = Number.isFinite(requestedPage) ? Math.max(1, Math.trunc(requestedPage)) : 1;
      const limit = Number.isFinite(requestedLimit) ? Math.min(100, Math.max(1, Math.trunc(requestedLimit))) : 50;
      if (academicYear && !/^\d{4}-\d{4}$/.test(academicYear)) return respond({ error: "Invalid academic year" }, 400, origin);
      if (ownerType && !OWNER_TYPES.has(ownerType)) return respond({ error: "Invalid owner type" }, 400, origin);
      if (category && !CATEGORIES.has(category)) return respond({ error: "Invalid category" }, 400, origin);
      if (ownerId && !ownerType) return respond({ error: "owner_type is required with owner_id" }, 400, origin);

      const from = (page - 1) * limit;
      const to = from + limit - 1;
      let query = admin
        .from("school_files")
        .select("id,owner_type,owner_id,category,original_name,display_name,mime_type,size_bytes,academic_year,created_at,archived_at,archived_by,restored_at,restored_by,payment_transaction_id,cahier_prep_id,administrative_document_id", { count: "exact" })
        .not("archived_at", "is", null)
        .is("deleted_at", null)
        .order("archived_at", { ascending: false })
        .order("id", { ascending: false })
        .range(from, to);
      if (academicYear) query = query.eq("academic_year", academicYear);
      if (ownerType) query = query.eq("owner_type", ownerType);
      if (ownerId) query = query.eq("owner_id", ownerId);
      if (category) query = query.eq("category", category);
      const { data, error, count } = await query;
      if (error) throw new Error(`Archive list failed: ${error.message}`);
      const total = count || 0;
      return respond({ ok: true, files: data || [], page, limit, total, has_more: from + (data?.length || 0) < total }, 200, origin);
    }

    const fileId = String(payload.file_id || "").trim();
    if (!["download", "archive", "restore"].includes(action)) return respond({ error: "Unknown action" }, 400, origin);
    if (!/^[0-9a-f-]{36}$/i.test(fileId)) return respond({ error: "Invalid file id" }, 400, origin);

    const { data: record, error: lookupError } = await admin
      .from("school_files")
      .select("id,owner_type,owner_id,category,storage_path,original_name,display_name,mime_type,metadata,archived_at,deleted_at,administrative_document_id")
      .eq("id", fileId)
      .maybeSingle();
    if (lookupError) throw new Error(`Archive lookup failed: ${lookupError.message}`);
    if (!record || record.deleted_at) return respond({ error: "File not found" }, 404, origin);

    if (action === "download") {
      if (!record.archived_at) return respond({ error: "File is not archived" }, 409, origin);
      const url = await getSignedUrl(
        s3,
        new GetObjectCommand({
          Bucket: bucket,
          Key: record.storage_path,
          ResponseContentType: record.mime_type,
          ResponseContentDisposition: `inline; filename="${safeFilename(record.original_name)}"`,
        }),
        { expiresIn: 300 },
      );
      return respond({
        ok: true,
        url,
        expires_in: 300,
        archived: true,
        file_name: record.original_name,
        display_name: record.display_name || record.original_name,
        mime_type: record.mime_type,
      }, 200, origin);
    }

    const metadata = record.metadata && typeof record.metadata === "object"
      ? record.metadata as Json
      : {};

    if (action === "archive") {
      if (record.archived_at) return respond({ error: "File is already archived" }, 409, origin);
      const archivedAt = new Date().toISOString();
      const { data, error } = await admin
        .from("school_files")
        .update({
          archived_at: archivedAt,
          archived_by: authId,
          restored_at: null,
          restored_by: null,
          metadata: { ...metadata, status: "archived", archive_scope: "single_file" },
        })
        .eq("id", fileId)
        .is("archived_at", null)
        .is("deleted_at", null)
        .select("id,archived_at,archived_by")
        .maybeSingle();
      if (error) throw new Error(`Archive failed: ${error.message}`);
      if (!data) return respond({ error: "File unavailable for archive" }, 409, origin);
      return respond({ ok: true, file: data }, 200, origin);
    }

    if (!record.archived_at) return respond({ error: "File is not archived" }, 409, origin);
    if (record.owner_type === "administrative_document" && record.administrative_document_id) {
      const { data: document, error: documentError } = await admin
        .from("administrative_documents")
        .select("status")
        .eq("id", record.administrative_document_id)
        .maybeSingle();
      if (documentError) throw new Error(`Administrative document lookup failed: ${documentError.message}`);
      if (document?.status === "archived") {
        return respond({
          error: "Restore the administrative document with restore_administrative_document so all pages remain synchronized",
          document_id: record.administrative_document_id,
        }, 409, origin);
      }
    }

    const restoredAt = new Date().toISOString();
    const cleanMetadata = { ...metadata };
    delete cleanMetadata.archive_scope;
    const { data, error } = await admin
      .from("school_files")
      .update({
        archived_at: null,
        archived_by: null,
        restored_at: restoredAt,
        restored_by: authId,
        metadata: { ...cleanMetadata, status: "ready" },
      })
      .eq("id", fileId)
      .not("archived_at", "is", null)
      .is("deleted_at", null)
      .select("id,restored_at,restored_by")
      .maybeSingle();
    if (error) throw new Error(`Restore failed: ${error.message}`);
    if (!data) return respond({ error: "File unavailable for restore" }, 409, origin);
    return respond({ ok: true, file: data }, 200, origin);
  } catch (error) {
    console.error("r2-archives error", error instanceof Error ? error.message : "unknown error");
    return respond({ error: "Archive service unavailable" }, 500, origin);
  }
});
