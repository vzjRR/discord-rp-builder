// آليات OAuth2 مع ديسكورد فقط (تبادل الرمز، وجلب هوية المستخدم) — منفصلة
// عن src/discord.js لأن تلك كلها طلبات بتوكن البوت (Bot token)، وهذه
// طلبات نيابة عن المستخدم نفسه (Bearer token) بعد موافقته.

const CLIENT_ID = process.env.DISCORD_CLIENT_ID;
const CLIENT_SECRET = process.env.DISCORD_CLIENT_SECRET;

function authorizeUrl({ redirectUri, state }) {
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    redirect_uri: redirectUri,
    response_type: 'code',
    scope: 'identify',
    state,
    prompt: 'consent',
  });
  return `https://discord.com/oauth2/authorize?${params}`;
}

async function exchangeCode(code, redirectUri) {
  const body = new URLSearchParams({
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    grant_type: 'authorization_code',
    code,
    redirect_uri: redirectUri,
  });
  const res = await fetch('https://discord.com/api/oauth2/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`تعذّر تبادل رمز ديسكورد (${res.status}): ${text.slice(0, 200)}`);
  }
  return res.json(); // { access_token, token_type, expires_in, refresh_token, scope }
}

async function fetchIdentity(accessToken) {
  const res = await fetch('https://discord.com/api/users/@me', {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error(`تعذّر جلب هوية ديسكورد (${res.status})`);
  return res.json(); // { id, username, global_name, avatar, discriminator }
}

module.exports = { authorizeUrl, exchangeCode, fetchIdentity };
