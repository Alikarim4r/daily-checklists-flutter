import { createClient } from 'npm:@supabase/supabase-js@2'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: {
    'content-type': 'application/json',
    'cache-control': 'no-store',
  },
})

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  const authorization = req.headers.get('authorization') ?? ''
  if (!authorization.startsWith('Bearer ')) return json({ error: 'unauthorized' }, 401)

  const url = Deno.env.get('SUPABASE_URL')
  const anon = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!url || !anon || !serviceRole) return json({ error: 'service_unavailable' }, 503)

  const body = await req.json().catch(() => ({}))
  if (body?.confirm !== true) return json({ error: 'confirmation_required' }, 400)

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: { user }, error: userError } = await userClient.auth.getUser()
  if (userError || !user) return json({ error: 'unauthorized' }, 401)

  // Supabase Auth deletion removes auth.users. The profiles ON DELETE CASCADE
  // then invokes the database privacy trigger in the same database transaction,
  // anonymizing retained operational history before the profile disappears.
  const admin = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: ownerRow, error: ownerError } = await admin
    .from('platform_owners')
    .select('user_id')
    .eq('user_id', user.id)
    .maybeSingle()
  if (ownerError) return json({ error: 'account_deletion_failed' }, 500)
  if (ownerRow) return json({ error: 'owner_account_requires_transfer' }, 409)

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id, false)
  if (deleteError) {
    console.error('account deletion failed', { code: deleteError.code, status: deleteError.status })
    return json({ error: 'account_deletion_failed' }, 500)
  }

  return json({ deleted: true })
})
