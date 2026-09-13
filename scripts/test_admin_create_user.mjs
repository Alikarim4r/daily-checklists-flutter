import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

// Execute the real handler with only its network client and Deno host injected.
// No Auth accounts are created, and no production connection is made.
const source = stripTypeScriptTypes(
  readFileSync(new URL('../supabase/functions/admin-create-user/index.ts', import.meta.url), 'utf8')
    .replace(/^import \{ createClient \} from [^\n]+\n/, ''),
);

function fixture(options = {}) {
  const calls = { created: [], profiles: [], deleted: [] };
  let handler;
  const profile = {
    role: 'super_admin', is_active: true, approval_status: 'approved',
    home_organization_id: 'org-a', ...options.profile,
  };
  const client = {
    auth: {
      getUser: async () => options.invalidSession
        ? { data: {}, error: { message: 'expired' } }
        : { data: { user: { id: 'caller' } }, error: null },
      admin: {
        createUser: async (payload) => {
          calls.created.push(payload);
          if (options.throwAuth) throw new Error('transport unavailable');
          return options.createError
            ? { data: {}, error: { status: 422, message: 'duplicate email' } }
            : { data: { user: { id: 'new-user' } }, error: null };
        },
        deleteUser: async (id) => { calls.deleted.push(id); return { error: null }; },
      },
    },
    from(table) {
      return {
        select() { return this; }, eq() { return this; },
        async maybeSingle() {
          if (table === 'platform_owners') {
            return { data: options.owner ? { user_id: 'caller' } : null, error: options.ownerError ?? null };
          }
          return { data: profile, error: null };
        },
        async upsert(payload) {
          calls.profiles.push(payload);
          return { error: options.profileWriteError ? { message: 'failed' } : null };
        },
      };
    },
  };
  runInNewContext(source, {
    createClient: () => client, Response,
    Deno: { env: { get: () => 'test-configuration' }, serve: (value) => { handler = value; } },
  });
  return {
    calls,
    request: (body = { email: ' User@example.com ', password: 'password-123', full_name: 'Test User' }, auth = true) =>
      handler(new Request('https://example.test/admin-create-user', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(auth ? { Authorization: 'Bearer test-jwt' } : {}) },
        body: JSON.stringify(body),
      })),
  };
}

test('rejects absent and expired sessions without creating an account', async () => {
  const absent = fixture();
  assert.equal((await absent.request({}, false)).status, 401);
  assert.equal(absent.calls.created.length, 0);
  const expired = fixture({ invalidSession: true });
  assert.equal((await expired.request()).status, 401);
  assert.equal(expired.calls.created.length, 0);
});

test('rejects technicians, suspended admins and pending admins', async () => {
  for (const profile of [{ role: 'technician' }, { is_active: false }, { approval_status: 'pending' }]) {
    const state = fixture({ profile });
    assert.equal((await state.request()).status, 403);
    assert.equal(state.calls.created.length, 0);
  }
});

test('fails closed when owner lookup cannot be verified', async () => {
  const state = fixture({ ownerError: { message: 'unavailable' } });
  assert.equal((await state.request()).status, 503);
  assert.equal(state.calls.created.length, 0);
});

test('rejects malformed payload shapes and invalid passwords', async () => {
  for (const body of [null, [], 'text', { email: 'valid@example.com', password: 'short' }]) {
    const state = fixture();
    assert.equal((await state.request(body)).status, 400);
    assert.equal(state.calls.created.length, 0);
  }
});

test('org admin creates a pending viewer only within the server-derived org', async () => {
  const state = fixture();
  const response = await state.request({
    email: ' User@example.com ', password: 'password-123',
    role: 'super_admin', home_organization_id: 'attacker-org', is_active: true,
  });
  assert.equal(response.status, 201);
  assert.equal((await response.json()).id, 'new-user');
  assert.equal(state.calls.created[0].email, 'user@example.com');
  assert.equal(state.calls.profiles[0].role, 'viewer');
  assert.equal(state.calls.profiles[0].approval_status, 'pending');
  assert.equal(state.calls.profiles[0].is_active, false);
  assert.equal(state.calls.profiles[0].home_organization_id, 'org-a');
});

test('UUID platform owner creates pending users without binding them to an org', async () => {
  const state = fixture({ owner: true });
  assert.equal((await state.request()).status, 201);
  assert.equal(state.calls.profiles[0].home_organization_id, null);
});

test('cleans up a newly created Auth user when profile initialization fails', async () => {
  const state = fixture({ profileWriteError: true });
  assert.equal((await state.request()).status, 500);
  assert.deepEqual(state.calls.deleted, ['new-user']);
});

test('Auth failures return JSON and CORS without an orphan profile', async () => {
  for (const options of [{ throwAuth: true }, { createError: true }]) {
    const state = fixture(options);
    const response = await state.request();
    assert.equal(response.status, options.throwAuth ? 503 : 422);
    assert.equal(response.headers.get('Access-Control-Allow-Origin'), '*');
    assert.ok((await response.json()).error);
    assert.equal(state.calls.profiles.length, 0);
  }
});
