#!/usr/bin/env node
// Owner moderation tool: the report queue and actions, from a terminal.
//   TRIFECTA_SERVICE=https://... TRIFECTA_ADMIN_TOKEN=... node tools/admin.mjs <command>
// Commands:
//   queue [open|actioned|dismissed]       list reports (oldest first)
//   show <profile_id>                     profile, recent names, reports
//   dismiss <receipt> [note]
//   rename <receipt> [note]               force a rename (old name becomes reserved)
//   suspend <receipt> <hours> [note]
//   unsuspend <profile_id>
//   reserve <name> [note]
//   audit [limit]
const base = process.env.TRIFECTA_SERVICE;
const token = process.env.TRIFECTA_ADMIN_TOKEN;
if (!base || !token) {
  console.error('Set TRIFECTA_SERVICE and TRIFECTA_ADMIN_TOKEN (from service/.secrets/admin_token).');
  process.exit(2);
}
async function api(method, path, body) {
  const r = await fetch(base.replace(/\/$/, '') + path, {
    method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`${r.status} ${j.error}: ${j.message}`);
  return j;
}
const [cmd, a, b, ...rest] = process.argv.slice(2);
const note = (xs) => xs.filter(Boolean).join(' ') || undefined;
try {
  switch (cmd) {
    case 'queue': {
      const j = await api('GET', `/v1/admin/reports?status=${a || 'open'}`);
      for (const r of j.reports) {
        console.log(`${r.id}  ${new Date(r.created_at).toISOString()}  ${(r.kind || 'player').padEnd(8)} ${r.reason.padEnd(13)} target=${r.target_id} "${r.target_name ?? ''}" open_for_target=${r.open_for_target}${r.details ? '  — ' + r.details : ''}`);
        if (r.evidence) console.log(`    message: "${r.evidence}"  (room ${r.context?.room_code ?? '?'})`);
      }
      console.log(`${j.reports.length} report(s)`);
      break;
    }
    case 'show': console.log(JSON.stringify(await api('GET', `/v1/admin/profiles/${a}`), null, 2)); break;
    case 'dismiss': console.log(await api('POST', `/v1/admin/reports/${a}/resolve`, { action: 'dismiss', note: note([b, ...rest]) })); break;
    case 'rename': console.log(await api('POST', `/v1/admin/reports/${a}/resolve`, { action: 'force_rename', note: note([b, ...rest]) })); break;
    case 'suspend': console.log(await api('POST', `/v1/admin/reports/${a}/resolve`, { action: 'suspend', hours: Number(b), note: note(rest) })); break;
    case 'unsuspend': console.log(await api('POST', `/v1/admin/profiles/${a}/unsuspend`, {})); break;
    case 'reserve': console.log(await api('POST', '/v1/admin/reserved', { name: a, note: note([b, ...rest]) })); break;
    case 'audit': {
      const j = await api('GET', `/v1/admin/audit?limit=${a || 100}`);
      for (const e of j.audit) console.log(`${new Date(e.at).toISOString()}  ${e.actor.padEnd(24)} ${e.action.padEnd(20)} ${e.target ?? ''} ${e.detail ? JSON.stringify(e.detail) : ''}`);
      break;
    }
    default:
      console.log('Commands: queue, show, dismiss, rename, suspend, unsuspend, reserve, audit (see the header of this file).');
  }
} catch (e) {
  console.error(String(e.message || e));
  process.exit(1);
}
