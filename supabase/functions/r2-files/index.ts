import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import {
  DeleteObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const MAX_FILE_SIZE = 5 * 1024 * 1024;
const ALLOWED_MIME_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/pdf",
]);
const OWNER_CATEGORIES: Record<string, ReadonlySet<string>> = {
  student: new Set(["document", "photo", "identity", "card", "receipt", "homework", "report"]),
  user: new Set(["document", "photo", "identity"]),
  authorized_person: new Set(["document", "photo", "identity"]),
  class: new Set(["document", "homework", "report"]),
  school: new Set(["document", "report", "archive"]),
  devoir: new Set(["document", "homework"]),
  cahier_prep: new Set(["teacher_preparation"]),
  administrative_document: new Set(["administrative_document"]),
};
const ALLOWED_OWNER_TYPES = new Set(Object.keys(OWNER_CATEGORIES));
const ALLOWED_CATEGORIES = new Set(Object.values(OWNER_CATEGORIES).flatMap((values) => [...values]));
const FINANCIAL_CATEGORIES = new Set(["receipt"]);
const PARENT_STUDENT_READ = new Set(["photo", "card", "receipt", "homework", "report"]);
const TEACHER_STUDENT_READ = new Set(["photo", "document", "homework", "report"]);
const TEACHER_STUDENT_UPLOAD = new Set(["document", "homework", "report"]);
const TEACHER_CLASS_ACCESS = new Set(["document", "homework", "report"]);
const TEACHER_DEVOIR_ACCESS = new Set(["document", "homework"]);
const DEFAULT_ORIGINS = [
  "https://medygoo.github.io",
  "https://medt121.github.io",
  "https://cslesage.com",
  "https://www.cslesage.com",
];

type JsonRecord = Record<string, unknown>;
type SupabaseClient = ReturnType<typeof createClient>;
type Identity = { authId: string; appUserId: string | null; role: string };
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
  payment_transaction_id: string | null;
  cahier_prep_id: string | null;
  administrative_document_id: string | null;
  metadata?: JsonRecord | null;
};
type AdminDocument = {
  id: string;
  is_financial: boolean;
  confidentiality: "administrative" | "financial" | "restricted";
  status: "draft" | "active" | "archived" | "voided";
  school_year: string;
};
type StudentRecord = {
  id: string;
  cid: string | null;
  pid: string | null;
  access_parent: boolean | null;
  archived: boolean | null;
};
type DevoirRecord = { id: string; cid: string | null; teacher_id: string | null };
type OwnerContext = {
  exists: boolean;
  active: boolean;
  expectedYear: string;
  student?: StudentRecord;
  adminDocument?: AdminDocument;
  devoir?: DevoirRecord;
};

function allowedOrigins(): Set<string> {
  const configured = Deno.env.get("APP_ALLOWED_ORIGINS");
  return new Set(
    configured
      ? configured.split(",").map((value) => value.trim()).filter(Boolean)
      : DEFAULT_ORIGINS,
  );
}

function corsHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-idempotency-key",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  if (origin && allowedOrigins().has(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}

function jsonResponse(data: JsonRecord, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

function defaultSupabaseKey(name: string): string {
  const raw = requiredEnv(name);
  try {
    const parsed = JSON.parse(raw) as Record<string, string>;
    const key = parsed.default || Object.values(parsed)[0];
    if (key) return key;
  } catch (_) {
    // Plain legacy values remain supported.
  }
  return raw;
}

function normalizeRole(role: string | null | undefined): string {
  if (role === "direction_pedagogique") return "direction2";
  if (role === "caisse") return "direction3";
  return role || "";
}

function sanitizeSegment(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80) || "unknown";
}

function extensionForMime(mimeType: string): string {
  if (mimeType === "image/jpeg") return "jpg";
  if (mimeType === "image/png") return "png";
  if (mimeType === "image/webp") return "webp";
  if (mimeType === "application/pdf") return "pdf";
  return "bin";
}

function safeFilename(value: string): string {
  return value.replace(/[\r\n"\\]/g, "_").slice(0, 160) || "document";
}

function safeDisplayName(value: string): string {
  return value.replace(/[\r\n]/g, " ").replace(/\s+/g, " ").trim().slice(0, 180) || "Document";
}

function isValidAcademicYear(value: string): boolean {
  return /^\d{4}-\d{4}$/.test(value);
}

function isValidUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function categoryAllowedForOwner(ownerType: string, category: string): boolean {
  return Boolean(OWNER_CATEGORIES[ownerType]?.has(category));
}

function detectMime(bytes: Uint8Array): string | null {
  if (bytes.length >= 4 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
    bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) return "image/png";
  if (
    bytes.length >= 12 &&
    String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
    String.fromCharCode(...bytes.slice(8, 12)) === "WEBP"
  ) return "image/webp";
  if (bytes.length >= 5 && String.fromCharCode(...bytes.slice(0, 5)) === "%PDF-") return "application/pdf";
  return null;
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function getIdentity(admin: SupabaseClient, authId: string): Promise<Identity | null> {
  const { data: appUser, error: appUserError } = await admin
    .from("users")
    .select("id,role,status")
    .eq("auth_user_id", authId)
    .maybeSingle();
  if (appUserError) throw new Error(`Identity lookup failed: ${appUserError.message}`);
  if (appUser?.status === "active") {
    return { authId, appUserId: appUser.id, role: normalizeRole(appUser.role) };
  }

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("role,status")
    .eq("id", authId)
    .maybeSingle();
  if (profileError) throw new Error(`Profile lookup failed: ${profileError.message}`);
  if (profile?.status === "active" && normalizeRole(profile.role) === "direction") {
    return { authId, appUserId: null, role: "direction" };
  }
  return null;
}

async function getCurrentAcademicYear(admin: SupabaseClient): Promise<string> {
  const { data, error } = await admin.from("settings").select("year").eq("id", "main").maybeSingle();
  if (error) throw new Error(`School year lookup failed: ${error.message}`);
  const year = String(data?.year || "").trim();
  if (!isValidAcademicYear(year)) throw new Error("Invalid current academic year");
  return year;
}

async function getStudent(admin: SupabaseClient, studentId: string): Promise<StudentRecord | null> {
  const { data, error } = await admin
    .from("students")
    .select("id,cid,pid,access_parent,archived")
    .eq("id", studentId)
    .maybeSingle();
  if (error) throw new Error(`Student lookup failed: ${error.message}`);
  return (data as StudentRecord | null) ?? null;
}

async function canAccessClass(admin: SupabaseClient, identity: Identity, classId: string | null): Promise<boolean> {
  if (!classId) return false;
  if (["direction", "direction2"].includes(identity.role)) return true;
  if (identity.role !== "enseignant" || !identity.appUserId) return false;
  const { data, error } = await admin
    .from("classes")
    .select("id")
    .eq("id", classId)
    .or(`teacher_id.eq.${identity.appUserId},teacher_id_en.eq.${identity.appUserId},titulaire_id.eq.${identity.appUserId}`)
    .maybeSingle();
  if (error) throw new Error(`Class access lookup failed: ${error.message}`);
  return Boolean(data);
}

async function parentHasChildInClass(admin: SupabaseClient, identity: Identity, classId: string | null): Promise<boolean> {
  if (identity.role !== "parent" || !identity.appUserId || !classId) return false;
  const { data, error } = await admin
    .from("students")
    .select("id")
    .eq("cid", classId)
    .eq("pid", identity.appUserId)
    .eq("archived", false)
    .neq("access_parent", false)
    .limit(1);
  if (error) throw new Error(`Parent class lookup failed: ${error.message}`);
  return Boolean(data?.length);
}

async function canAccessStudent(admin: SupabaseClient, identity: Identity, studentId: string): Promise<boolean> {
  const student = await getStudent(admin, studentId);
  if (!student || student.archived) return false;
  if (["direction", "direction2"].includes(identity.role)) return true;
  if (identity.role === "parent") {
    return Boolean(identity.appUserId && student.pid === identity.appUserId && student.access_parent !== false);
  }
  if (identity.role === "enseignant") return canAccessClass(admin, identity, student.cid);
  return false;
}

async function getDevoir(admin: SupabaseClient, devoirId: string): Promise<DevoirRecord | null> {
  const { data, error } = await admin
    .from("devoirs")
    .select("id,cid,teacher_id")
    .eq("id", devoirId)
    .maybeSingle();
  if (error) throw new Error(`Homework lookup failed: ${error.message}`);
  return (data as DevoirRecord | null) ?? null;
}

async function canAccessTeacherPreparation(
  admin: SupabaseClient,
  identity: Identity,
  preparationId: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from("cahier_prep")
    .select("id,teacher_id")
    .eq("id", preparationId)
    .maybeSingle();
  if (error) throw new Error(`Teacher preparation lookup failed: ${error.message}`);
  if (!data) return false;
  if (["direction", "direction2"].includes(identity.role)) return true;
  return Boolean(identity.role === "enseignant" && identity.appUserId && data.teacher_id === identity.appUserId);
}

async function getAdministrativeDocument(
  admin: SupabaseClient,
  documentId: string,
): Promise<AdminDocument | null> {
  const { data, error } = await admin
    .from("administrative_documents")
    .select("id,is_financial,confidentiality,status,school_year")
    .eq("id", documentId)
    .maybeSingle();
  if (error) throw new Error(`Administrative document lookup failed: ${error.message}`);
  return (data as AdminDocument | null) ?? null;
}

function canAccessAdministrativeDocument(identity: Identity, document: AdminDocument): boolean {
  if (["archived", "voided"].includes(document.status)) return false;
  if (identity.role === "direction") return true;
  if (identity.role === "direction2") {
    return !document.is_financial && document.confidentiality === "administrative";
  }
  if (identity.role === "direction3") return document.is_financial;
  return false;
}

async function validateReceiptTransaction(
  admin: SupabaseClient,
  studentId: string,
  transactionId: string | null,
): Promise<{ valid: boolean; schoolYear: string | null }> {
  if (!transactionId) return { valid: false, schoolYear: null };
  const { data, error } = await admin
    .from("payment_transactions")
    .select("id,school_year")
    .eq("id", transactionId)
    .eq("sid", studentId)
    .eq("status", "confirmed")
    .maybeSingle();
  if (error) throw new Error(`Payment transaction lookup failed: ${error.message}`);
  return { valid: Boolean(data), schoolYear: data?.school_year || null };
}

async function getOwnerContext(
  admin: SupabaseClient,
  ownerType: string,
  ownerId: string,
  category: string,
  paymentTransactionId: string | null,
): Promise<OwnerContext> {
  const currentYear = await getCurrentAcademicYear(admin);

  if (ownerType === "student") {
    const student = await getStudent(admin, ownerId);
    if (!student) return { exists: false, active: false, expectedYear: currentYear };
    if (category === "receipt") {
      const receipt = await validateReceiptTransaction(admin, ownerId, paymentTransactionId);
      return {
        exists: receipt.valid,
        active: !student.archived && receipt.valid,
        expectedYear: receipt.schoolYear || currentYear,
        student,
      };
    }
    return { exists: true, active: !student.archived, expectedYear: currentYear, student };
  }

  if (ownerType === "user") {
    const { data, error } = await admin.from("users").select("id,status").eq("id", ownerId).maybeSingle();
    if (error) throw new Error(`User owner lookup failed: ${error.message}`);
    return { exists: Boolean(data), active: data?.status === "active", expectedYear: currentYear };
  }

  if (ownerType === "authorized_person") {
    const { data, error } = await admin.from("aps").select("id,active").eq("id", ownerId).maybeSingle();
    if (error) throw new Error(`Authorized person owner lookup failed: ${error.message}`);
    return { exists: Boolean(data), active: Boolean(data), expectedYear: currentYear };
  }

  if (ownerType === "class") {
    const { data, error } = await admin.from("classes").select("id").eq("id", ownerId).maybeSingle();
    if (error) throw new Error(`Class owner lookup failed: ${error.message}`);
    return { exists: Boolean(data), active: Boolean(data), expectedYear: currentYear };
  }

  if (ownerType === "school") {
    const { data, error } = await admin.from("settings").select("id,year").eq("id", ownerId).maybeSingle();
    if (error) throw new Error(`School owner lookup failed: ${error.message}`);
    return {
      exists: Boolean(data),
      active: Boolean(data),
      expectedYear: isValidAcademicYear(String(data?.year || "")) ? data!.year : currentYear,
    };
  }

  if (ownerType === "devoir") {
    const devoir = await getDevoir(admin, ownerId);
    return { exists: Boolean(devoir), active: Boolean(devoir), expectedYear: currentYear, devoir: devoir || undefined };
  }

  if (ownerType === "cahier_prep") {
    const { data, error } = await admin.from("cahier_prep").select("id").eq("id", ownerId).maybeSingle();
    if (error) throw new Error(`Teacher preparation owner lookup failed: ${error.message}`);
    return { exists: Boolean(data), active: Boolean(data), expectedYear: currentYear };
  }

  if (ownerType === "administrative_document") {
    const document = await getAdministrativeDocument(admin, ownerId);
    return {
      exists: Boolean(document),
      active: Boolean(document && !["archived", "voided"].includes(document.status)),
      expectedYear: document?.school_year || currentYear,
      adminDocument: document || undefined,
    };
  }

  return { exists: false, active: false, expectedYear: currentYear };
}

async function canReadFile(
  admin: SupabaseClient,
  identity: Identity,
  record: FileRecord,
): Promise<boolean> {
  if (record.archived_at || record.deleted_at) return false;
  if (!categoryAllowedForOwner(record.owner_type, record.category)) return false;
  if (identity.role === "direction") return true;

  if (record.owner_type === "administrative_document") {
    const document = await getAdministrativeDocument(admin, record.owner_id);
    return Boolean(document && canAccessAdministrativeDocument(identity, document));
  }

  if (record.owner_type === "cahier_prep") {
    return record.category === "teacher_preparation" &&
      await canAccessTeacherPreparation(admin, identity, record.owner_id);
  }

  const financial = FINANCIAL_CATEGORIES.has(record.category);
  if (identity.role === "direction2") return !financial;
  if (identity.role === "direction3") {
    if (!financial || record.owner_type !== "student") return false;
    return (await validateReceiptTransaction(admin, record.owner_id, record.payment_transaction_id)).valid;
  }
  if (identity.role === "gardien") return false;

  if (record.owner_type === "user") {
    if (!identity.appUserId || record.owner_id !== identity.appUserId || financial) return false;
    if (identity.role === "parent") return record.category === "photo";
    if (identity.role === "enseignant") return ["photo", "document", "identity"].includes(record.category);
    return false;
  }

  if (record.owner_type === "student") {
    if (!(await canAccessStudent(admin, identity, record.owner_id))) return false;
    if (identity.role === "enseignant") return TEACHER_STUDENT_READ.has(record.category);
    if (identity.role === "parent") {
      if (!PARENT_STUDENT_READ.has(record.category)) return false;
      if (record.category === "receipt") {
        return (await validateReceiptTransaction(admin, record.owner_id, record.payment_transaction_id)).valid;
      }
      return true;
    }
    return false;
  }

  if (record.owner_type === "authorized_person") {
    if (identity.role !== "parent" || record.category !== "photo") return false;
    const { data, error } = await admin.from("aps").select("sid").eq("id", record.owner_id).maybeSingle();
    if (error) throw new Error(`Authorized person lookup failed: ${error.message}`);
    return Boolean(data?.sid && await canAccessStudent(admin, identity, data.sid));
  }

  if (record.owner_type === "class") {
    return identity.role === "enseignant" && TEACHER_CLASS_ACCESS.has(record.category) &&
      await canAccessClass(admin, identity, record.owner_id);
  }

  if (record.owner_type === "devoir") {
    const devoir = await getDevoir(admin, record.owner_id);
    if (!devoir) return false;
    if (identity.role === "enseignant") {
      return TEACHER_DEVOIR_ACCESS.has(record.category) && await canAccessClass(admin, identity, devoir.cid);
    }
    if (identity.role === "parent") {
      return record.category === "homework" && await parentHasChildInClass(admin, identity, devoir.cid);
    }
    return false;
  }

  return false;
}

async function canUploadFile(
  admin: SupabaseClient,
  identity: Identity,
  ownerType: string,
  ownerId: string,
  category: string,
  paymentTransactionId: string | null,
  owner: OwnerContext,
): Promise<boolean> {
  if (!owner.exists || !owner.active || !categoryAllowedForOwner(ownerType, category)) return false;

  if (ownerType === "administrative_document") {
    return category === "administrative_document" && Boolean(
      owner.adminDocument && canAccessAdministrativeDocument(identity, owner.adminDocument),
    );
  }

  if (ownerType === "cahier_prep") {
    return category === "teacher_preparation" && canAccessTeacherPreparation(admin, identity, ownerId);
  }

  const financial = FINANCIAL_CATEGORIES.has(category);
  if (identity.role === "direction") return financial ? Boolean(paymentTransactionId) : true;
  if (identity.role === "direction2") return !financial;
  if (identity.role === "direction3") {
    return financial && ownerType === "student" && Boolean(paymentTransactionId);
  }
  if (identity.role !== "enseignant" || financial) return false;

  if (ownerType === "user") {
    return Boolean(identity.appUserId && ownerId === identity.appUserId && ["photo", "document", "identity"].includes(category));
  }
  if (ownerType === "student") {
    return TEACHER_STUDENT_UPLOAD.has(category) && await canAccessStudent(admin, identity, ownerId);
  }
  if (ownerType === "class") {
    return TEACHER_CLASS_ACCESS.has(category) && await canAccessClass(admin, identity, ownerId);
  }
  if (ownerType === "devoir") {
    return TEACHER_DEVOIR_ACCESS.has(category) && Boolean(owner.devoir) &&
      await canAccessClass(admin, identity, owner.devoir!.cid);
  }
  return false;
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("Origin");

  if (request.method === "OPTIONS") {
    if (origin && !allowedOrigins().has(origin)) {
      return jsonResponse({ error: "Origin not allowed" }, 403, origin);
    }
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405, origin);
  if (origin && !allowedOrigins().has(origin)) return jsonResponse({ error: "Origin not allowed" }, 403, origin);

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return jsonResponse({ error: "Authentication required" }, 401, origin);
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")
      ? defaultSupabaseKey("SUPABASE_PUBLISHABLE_KEYS")
      : requiredEnv("SUPABASE_ANON_KEY");
    const secretKey = defaultSupabaseKey("SUPABASE_SECRET_KEYS");
    const supabase = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const admin = createClient(supabaseUrl, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) return jsonResponse({ error: "Invalid session" }, 401, origin);
    const user = authData.user;
    const identity = await getIdentity(admin, user.id);
    if (!identity) return jsonResponse({ error: "Active SchoolSafe account required" }, 403, origin);

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

    const contentType = request.headers.get("Content-Type") || "";
    let action = "";
    let payload: JsonRecord = {};
    let form: FormData | null = null;
    if (contentType.includes("multipart/form-data")) {
      form = await request.formData();
      action = String(form.get("action") || "upload");
    } else {
      payload = (await request.json()) as JsonRecord;
      action = String(payload.action || "");
    }

    if (action === "health") {
      if (identity.role !== "direction") return jsonResponse({ error: "Direction 1 access required" }, 403, origin);
      await s3.send(new ListObjectsV2Command({ Bucket: bucket, MaxKeys: 1 }));
      return jsonResponse({
        ok: true,
        connected: true,
        bucket,
        function_version: 5,
        schema_version: 4,
        current_academic_year: await getCurrentAcademicYear(admin),
      }, 200, origin);
    }

    if (action === "upload") {
      if (!form) return jsonResponse({ error: "Multipart form required" }, 400, origin);
      const file = form.get("file");
      const ownerType = String(form.get("owner_type") || "").trim();
      const ownerId = String(form.get("owner_id") || "").trim();
      const category = String(form.get("category") || "document").trim().toLowerCase();
      const requestedAcademicYear = String(form.get("academic_year") || "").trim();
      const paymentTransactionId = String(form.get("payment_transaction_id") || "").trim() || null;
      const displayName = safeDisplayName(String(form.get("display_name") || (file instanceof File ? file.name : "Document")));
      const idempotencyKey = String(
        request.headers.get("x-idempotency-key") || form.get("idempotency_key") || "",
      ).trim() || null;

      if (!(file instanceof File)) return jsonResponse({ error: "File is required" }, 400, origin);
      if (!ALLOWED_MIME_TYPES.has(file.type)) return jsonResponse({ error: "Unsupported file type" }, 415, origin);
      if (file.size <= 0 || file.size > MAX_FILE_SIZE) {
        return jsonResponse({ error: "File must be between 1 byte and 5 MB" }, 413, origin);
      }
      if (!ALLOWED_OWNER_TYPES.has(ownerType)) return jsonResponse({ error: "Invalid owner type" }, 400, origin);
      if (!ALLOWED_CATEGORIES.has(category) || !categoryAllowedForOwner(ownerType, category)) {
        return jsonResponse({ error: "Invalid owner/category combination" }, 400, origin);
      }
      if (!ownerId || ownerId.length > 128) return jsonResponse({ error: "Invalid owner id" }, 400, origin);
      if (requestedAcademicYear && !isValidAcademicYear(requestedAcademicYear)) {
        return jsonResponse({ error: "Invalid academic year" }, 400, origin);
      }
      if (idempotencyKey && !/^[A-Za-z0-9._:-]{8,128}$/.test(idempotencyKey)) {
        return jsonResponse({ error: "Invalid idempotency key" }, 400, origin);
      }

      const owner = await getOwnerContext(admin, ownerType, ownerId, category, paymentTransactionId);
      if (!owner.exists) return jsonResponse({ error: "File owner does not exist or receipt transaction is invalid" }, 404, origin);
      if (!owner.active) return jsonResponse({ error: "File owner is inactive or archived" }, 409, origin);
      if (!(await canUploadFile(admin, identity, ownerType, ownerId, category, paymentTransactionId, owner))) {
        return jsonResponse({ error: "File upload not allowed for this role" }, 403, origin);
      }

      const academicYear = owner.expectedYear;
      if (!isValidAcademicYear(academicYear)) throw new Error("Owner academic year is invalid");
      if (requestedAcademicYear && requestedAcademicYear !== academicYear) {
        return jsonResponse({
          error: "Academic year does not match the server source of truth",
          current_academic_year: academicYear,
        }, 409, origin);
      }

      if (idempotencyKey) {
        const { data: existing, error: existingError } = await admin
          .from("school_files")
          .select("id,owner_type,owner_id,category,original_name,display_name,mime_type,size_bytes,academic_year,created_at,payment_transaction_id,cahier_prep_id,administrative_document_id")
          .eq("uploaded_by", user.id)
          .eq("idempotency_key", idempotencyKey)
          .is("deleted_at", null)
          .maybeSingle();
        if (existingError) throw new Error(`Idempotency lookup failed: ${existingError.message}`);
        if (existing) {
          if (existing.owner_type !== ownerType || existing.owner_id !== ownerId || existing.category !== category) {
            return jsonResponse({ error: "Idempotency key already belongs to another upload" }, 409, origin);
          }
          return jsonResponse({ ok: true, reused: true, file: existing }, 200, origin);
        }
      }

      const bytes = new Uint8Array(await file.arrayBuffer());
      const detectedMime = detectMime(bytes);
      if (!detectedMime || detectedMime !== file.type) {
        return jsonResponse({ error: "File content does not match its declared type" }, 415, origin);
      }

      const fileId = crypto.randomUUID();
      const storagePath = [
        "schools",
        "le-sage",
        academicYear,
        ownerType,
        sanitizeSegment(ownerId),
        category,
        `${fileId}.${extensionForMime(detectedMime)}`,
      ].join("/");
      const checksum = await sha256Hex(bytes);
      const cahierPrepId = ownerType === "cahier_prep" ? ownerId : null;
      const administrativeDocumentId = ownerType === "administrative_document" ? ownerId : null;

      await s3.send(new PutObjectCommand({
        Bucket: bucket,
        Key: storagePath,
        Body: bytes,
        ContentType: detectedMime,
        ContentLength: bytes.length,
        Metadata: {
          "file-id": fileId,
          "uploaded-by": identity.authId,
          "owner-type": ownerType,
          category,
          "academic-year": academicYear,
        },
      }));

      const { data: record, error: insertError } = await admin
        .from("school_files")
        .insert({
          id: fileId,
          owner_type: ownerType,
          owner_id: ownerId,
          category,
          storage_path: storagePath,
          original_name: safeFilename(file.name),
          display_name: displayName,
          mime_type: detectedMime,
          size_bytes: bytes.length,
          academic_year: academicYear,
          uploaded_by: user.id,
          checksum_sha256: checksum,
          idempotency_key: idempotencyKey,
          payment_transaction_id: paymentTransactionId,
          cahier_prep_id: cahierPrepId,
          administrative_document_id: administrativeDocumentId,
          metadata: { status: "ready", storage: "r2", schema_version: 4, function_version: 5 },
        })
        .select("id,owner_type,owner_id,category,original_name,display_name,mime_type,size_bytes,academic_year,created_at,payment_transaction_id,cahier_prep_id,administrative_document_id")
        .single();

      if (insertError) {
        await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: storagePath })).catch(() => undefined);
        throw new Error(`Metadata insert failed: ${insertError.message}`);
      }
      return jsonResponse({ ok: true, reused: false, file: record }, 201, origin);
    }

    if (action === "download") {
      const fileId = String(payload.file_id || "");
      if (!isValidUuid(fileId)) return jsonResponse({ error: "Invalid file id" }, 400, origin);
      const { data: record, error } = await admin
        .from("school_files")
        .select("id,owner_type,owner_id,category,storage_path,original_name,display_name,mime_type,archived_at,deleted_at,payment_transaction_id,cahier_prep_id,administrative_document_id")
        .eq("id", fileId)
        .maybeSingle();
      if (error) throw new Error(`Metadata lookup failed: ${error.message}`);
      if (!record) return jsonResponse({ error: "File not found" }, 404, origin);
      if (!(await canReadFile(admin, identity, record as FileRecord))) {
        return jsonResponse({ error: "File access not allowed" }, 403, origin);
      }

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
      return jsonResponse({
        ok: true,
        url,
        expires_in: 300,
        file_name: record.original_name,
        display_name: record.display_name || record.original_name,
        mime_type: record.mime_type,
      }, 200, origin);
    }

    if (action === "list") {
      const ownerType = String(payload.owner_type || "");
      const ownerId = String(payload.owner_id || "");
      const category = String(payload.category || "");
      const requestedLimit = Number(payload.limit || 50);
      const limit = Number.isFinite(requestedLimit) ? Math.min(Math.max(Math.trunc(requestedLimit), 1), 100) : 50;
      if (!ALLOWED_OWNER_TYPES.has(ownerType) || !ownerId) return jsonResponse({ error: "Invalid owner" }, 400, origin);
      if (category && (!ALLOWED_CATEGORIES.has(category) || !categoryAllowedForOwner(ownerType, category))) {
        return jsonResponse({ error: "Invalid category" }, 400, origin);
      }

      let query = admin
        .from("school_files")
        .select("id,owner_type,owner_id,category,original_name,display_name,mime_type,size_bytes,academic_year,created_at,payment_transaction_id,cahier_prep_id,administrative_document_id,archived_at,deleted_at")
        .eq("owner_type", ownerType)
        .eq("owner_id", ownerId)
        .is("archived_at", null)
        .is("deleted_at", null)
        .order("created_at", { ascending: false })
        .limit(limit);
      if (category) query = query.eq("category", category);
      const { data, error } = await query;
      if (error) throw new Error(`File list failed: ${error.message}`);

      const visible: JsonRecord[] = [];
      for (const record of data || []) {
        if (await canReadFile(admin, identity, record as FileRecord)) visible.push(record as JsonRecord);
      }
      return jsonResponse({ ok: true, files: visible, limit }, 200, origin);
    }

    if (action === "archive") {
      if (identity.role !== "direction") return jsonResponse({ error: "Direction 1 access required" }, 403, origin);
      const fileId = String(payload.file_id || "");
      if (!isValidUuid(fileId)) return jsonResponse({ error: "Invalid file id" }, 400, origin);
      const { data, error } = await admin
        .from("school_files")
        .update({ archived_at: new Date().toISOString() })
        .eq("id", fileId)
        .is("archived_at", null)
        .is("deleted_at", null)
        .select("id,archived_at")
        .maybeSingle();
      if (error) throw new Error(`Archive failed: ${error.message}`);
      if (!data) return jsonResponse({ error: "File not found or unavailable" }, 404, origin);
      return jsonResponse({ ok: true, file: data }, 200, origin);
    }

    if (action === "delete") {
      if (identity.role !== "direction") return jsonResponse({ error: "Direction 1 access required" }, 403, origin);
      const fileId = String(payload.file_id || "");
      if (!isValidUuid(fileId)) return jsonResponse({ error: "Invalid file id" }, 400, origin);
      const { data: record, error: lookupError } = await admin
        .from("school_files")
        .select("id,storage_path,deleted_at,metadata")
        .eq("id", fileId)
        .maybeSingle();
      if (lookupError) throw new Error(`Delete lookup failed: ${lookupError.message}`);
      if (!record || record.deleted_at) return jsonResponse({ error: "File not found" }, 404, origin);

      await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: record.storage_path }));
      const metadata = (record.metadata && typeof record.metadata === "object") ? record.metadata as JsonRecord : {};
      const { error: updateError } = await admin
        .from("school_files")
        .update({
          deleted_at: new Date().toISOString(),
          deleted_by: user.id,
          metadata: { ...metadata, status: "deleted", storage: "r2", schema_version: 4, function_version: 5 },
        })
        .eq("id", fileId);
      if (updateError) throw new Error(`Delete metadata update failed: ${updateError.message}`);
      return jsonResponse({ ok: true, file_id: fileId, deleted: true }, 200, origin);
    }

    return jsonResponse({ error: "Unknown action" }, 400, origin);
  } catch (error) {
    console.error("r2-files error", error instanceof Error ? error.message : "unknown error");
    return jsonResponse({ error: "Storage service unavailable" }, 500, origin);
  }
});
