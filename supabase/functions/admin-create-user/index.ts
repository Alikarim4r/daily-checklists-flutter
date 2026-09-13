import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function handleRequest(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Server configuration is incomplete" }, 500);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const jwt = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return json({ error: "Authentication required" }, 401);

  const callerClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: callerData, error: callerError } =
    await callerClient.auth.getUser(jwt);
  if (callerError || !callerData.user) {
    return json({ error: "Invalid or expired session" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const callerId = callerData.user.id;
  const [{ data: owner, error: ownerError }, { data: profile, error: profileError }] =
    await Promise.all([
      admin
        .from("platform_owners")
        .select("user_id")
        .eq("user_id", callerId)
        .maybeSingle(),
      admin
        .from("profiles")
        .select("role, is_active, approval_status, home_organization_id")
        .eq("id", callerId)
        .maybeSingle(),
    ]);

  if (ownerError || profileError) {
    return json({ error: "Administrator access could not be verified" }, 503);
  }
  if (!profile) {
    return json({ error: "Caller profile is unavailable" }, 403);
  }
  const isPlatformOwner = owner?.user_id === callerId;
  const isApprovedOrgAdmin =
    profile.role === "super_admin" &&
    profile.is_active === true &&
    profile.approval_status === "approved" &&
    typeof profile.home_organization_id === "string" &&
    profile.home_organization_id.length > 0;
  if (!isPlatformOwner && !isApprovedOrgAdmin) {
    return json({ error: "Only an approved administrator can create users" }, 403);
  }

  let payload: Record<string, unknown>;
  try {
    const value: unknown = await request.json();
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      return json({ error: "Expected a JSON object" }, 400);
    }
    payload = value as Record<string, unknown>;
  } catch (_) {
    return json({ error: "Invalid JSON request" }, 400);
  }
  const email = typeof payload.email === "string"
    ? payload.email.trim().toLowerCase()
    : "";
  const password = typeof payload.password === "string" ? payload.password : "";
  const requestedName = typeof payload.full_name === "string"
    ? payload.full_name.trim()
    : "";
  const fullName = requestedName || email.split("@")[0] || "User";

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 320) {
    return json({ error: "Invalid email address" }, 400);
  }
  if (password.length < 8 || password.length > 128) {
    return json({ error: "Password must be between 8 and 128 characters" }, 400);
  }
  if (fullName.length > 160) {
    return json({ error: "Full name is too long" }, 400);
  }

  const { data: created, error: createError } =
    await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    });
  if (createError || !created.user) {
    return json(
      { error: createError?.message ?? "Could not create user" },
      createError?.status ?? 400,
    );
  }

  const userId = created.user.id;
  const { error: profileWriteError } = await admin.from("profiles").upsert({
    id: userId,
    full_name: fullName,
    email,
    role: "viewer",
    is_active: false,
    approval_status: "pending",
    home_organization_id: isPlatformOwner
      ? null
      : profile.home_organization_id,
  }, { onConflict: "id" });

  if (profileWriteError) {
    // Avoid an orphaned login that cannot be administered in the application.
    await admin.auth.admin.deleteUser(userId);
    return json({ error: "Could not initialize the user profile" }, 500);
  }

  return json({ id: userId }, 201);
}

Deno.serve(async (request: Request) => {
  try {
    return await handleRequest(request);
  } catch (_) {
    // Keep CORS and a stable response even when Auth/Storage is unavailable.
    return json({ error: "User creation is temporarily unavailable" }, 503);
  }
});
