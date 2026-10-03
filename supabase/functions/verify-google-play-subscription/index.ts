import { createClient } from 'npm:@supabase/supabase-js@2'
import { SignJWT, importPKCS8 } from 'npm:jose@5'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
})
const PRODUCT_TIERS: Record<string, string> = {
  daily_checklists_starter: 'starter',
  daily_checklists_professional: 'professional',
  daily_checklists_business: 'business',
}
const ALLOWED_PACKAGES = new Set([
  'com.moehe.checklists.checklist_entry',
  'com.moehe.checklists.checklist_viewer',
  'com.moehe.checklists.checklist_admin',
])
const stateMap: Record<string, string> = {
  SUBSCRIPTION_STATE_ACTIVE: 'active',
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD: 'grace_period',
  SUBSCRIPTION_STATE_PAUSED: 'paused',
  SUBSCRIPTION_STATE_ON_HOLD: 'paused',
  SUBSCRIPTION_STATE_CANCELED: 'active',
  SUBSCRIPTION_STATE_EXPIRED: 'expired',
  SUBSCRIPTION_STATE_PENDING: 'expired',
}

async function googleAccessToken(sa: { client_email: string; private_key: string }) {
  const now = Math.floor(Date.now() / 1000)
  const key = await importPKCS8(sa.private_key, 'RS256')
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/androidpublisher' })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email).setSubject(sa.client_email)
    .setAudience('https://oauth2.googleapis.com/token').setIssuedAt(now).setExpirationTime(now + 3600)
    .sign(key)
  const form = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion,
  })
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: form,
  })
  if (!response.ok) throw new Error(`google_oauth_${response.status}`)
  return (await response.json()).access_token as string
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)
  const auth = req.headers.get('authorization') ?? ''
  const url = Deno.env.get('SUPABASE_URL')!
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const userClient = createClient(url, anon, { global: { headers: { Authorization: auth } } })
  const { data: { user } } = await userClient.auth.getUser()
  if (!user) return json({ error: 'unauthorized' }, 401)

  const body = await req.json().catch(() => ({}))
  const productId = String(body.product_id ?? '').trim()
  const purchaseToken = String(body.purchase_token ?? '').trim()
  const packageName = String(body.package_name ?? '').trim()
  const tier = PRODUCT_TIERS[productId]
  if (!tier || !purchaseToken || !ALLOWED_PACKAGES.has(packageName)) {
    return json({ error: 'invalid_purchase_data' }, 400)
  }

  const admin = createClient(url, service)
  const { data: profile } = await admin.from('profiles')
    .select('home_organization_id,is_active,approval_status').eq('id', user.id).single()
  if (!profile?.home_organization_id || !profile.is_active || profile.approval_status !== 'approved') {
    return json({ error: 'organization_access_required' }, 403)
  }
  const raw = Deno.env.get('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON') ?? ''
  if (!raw) return json({ error: 'play_verification_not_configured' }, 503)

  try {
    const token = await googleAccessToken(JSON.parse(raw))
    const endpoint = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`
    const playResponse = await fetch(endpoint, { headers: { authorization: `Bearer ${token}` } })
    if (!playResponse.ok) return json({ error: 'play_verification_failed' }, 422)
    const play = await playResponse.json()
    if (play.packageName && play.packageName !== packageName) {
      return json({ error: 'package_mismatch' }, 422)
    }
    const line = play.lineItems?.find((item: any) => item.productId === productId)
    if (!line) return json({ error: 'product_mismatch' }, 422)
    const state = stateMap[play.subscriptionState] ?? 'expired'
    const expiry = line.expiryTime ?? null
    const basePlanId = line.offerDetails?.basePlanId ?? null
    const offerId = line.offerDetails?.offerId ?? null
    const autoRenewing = Boolean(line.autoRenewingPlan?.autoRenewEnabled)
    const hashBytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(purchaseToken))
    const tokenHash = Array.from(new Uint8Array(hashBytes))
      .map(b => b.toString(16).padStart(2, '0')).join('')

    const { error } = await admin.from('organization_subscriptions').upsert({
      organization_id: profile.home_organization_id,
      plan_tier: tier, product_id: productId,
      base_plan_id: basePlanId, offer_id: offerId,
      subscription_state: state, expires_at: expiry,
      auto_renewing: autoRenewing, provider: 'google_play',
      purchase_token_hash: tokenHash, verified_at: new Date().toISOString(),
    }, { onConflict: 'organization_id' })
    if (error) throw error
    return json({
      verified: true, plan_tier: tier, base_plan_id: basePlanId, offer_id: offerId,
      subscription_state: state, expires_at: expiry, auto_renewing: autoRenewing,
    })
  } catch (error) {
    console.error('subscription verification failed', error)
    return json({ error: 'verification_internal_error' }, 500)
  }
})
