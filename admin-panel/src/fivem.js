// حالة سيرفر FiveM — تُجلب من قائمة سيرفرات FiveM العامة (cfx.re)، لا من
// السيرفر نفسه مباشرة، فما تحتاج أي رمز دخول أو فتح منفذ إضافي على
// الاستضافة. يشترط فقط أن يكون السيرفر مُدرَجًا علنيًا بالقائمة (sv_listed)
// وأن يرسل نبضة heartbeat حديثة لها — سيرفر مطفّى أو غير مُدرَج يظهر
// "غير متصل" لا خطأ.

const SERVER_ID = process.env.FIVEM_SERVER_ID;

async function fetchWithTimeout(url, ms = 8000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    return await fetch(url, { signal: controller.signal, headers: { Accept: 'application/json' } });
  } finally {
    clearTimeout(timer);
  }
}

/** حالة السيرفر الحية، أو null لو ما رُبط سيرفر FiveM أصلًا. */
async function getStatus() {
  if (!SERVER_ID) return null;

  const joinUrl = `https://cfx.re/join/${SERVER_ID}`;
  try {
    // نطاق واجهة FiveM العامة تغيّر مؤخرًا من servers-frontend.fivem.net
    // (صار يرد 404 لأي سيرفر) إلى frontend.cfx-services.net — نفس المصدر
    // الذي تعتمده صفحة cfx.re/join نفسها لعرض حالة السيرفر الحية.
    const res = await fetchWithTimeout(`https://frontend.cfx-services.net/api/servers/single/${SERVER_ID}`);
    if (!res.ok) return { online: false, serverId: SERVER_ID, joinUrl };

    const body = await res.json();
    const data = body?.Data;
    if (!data) return { online: false, serverId: SERVER_ID, joinUrl };

    const players = Array.isArray(data.players) ? data.players : [];
    return {
      online: true,
      serverId: SERVER_ID,
      joinUrl,
      hostname: data.hostname || null,
      mapname: data.mapname || null,
      gametype: data.gametype || null,
      clients: typeof data.clients === 'number' ? data.clients : players.length,
      maxClients: data.sv_maxclients ?? data.vars?.sv_maxclients ?? null,
      resourceCount: Array.isArray(data.resources) ? data.resources.length : null,
      players: players
        .map((p) => ({ name: p.name, ping: p.ping ?? null }))
        .sort((a, b) => (a.name || '').localeCompare(b.name || ''))
        .slice(0, 100),
    };
  } catch (err) {
    console.error('fivem status:', err.message);
    return { online: false, serverId: SERVER_ID, joinUrl, error: true };
  }
}

module.exports = { getStatus, isConfigured: () => Boolean(SERVER_ID) };
