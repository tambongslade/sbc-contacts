import { Controller, Get, Query, Res, Version, VERSION_NEUTRAL } from '@nestjs/common';
import { Response } from 'express';
import { Public } from '../../common/decorators/public.decorator';

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * HTTPS redirect bridge for SSO. SBC redirects the browser to
 * `https://contacts.sniperbusinesscenterlive.com/auth/callback?code=...` after
 * consent; this page shows the one-shot code for copy/paste and offers the
 * `sbccontacts://` deep link. The code is rendered SERVER-SIDE so it's visible
 * even if JS is blocked. When no code arrives, it shows exactly what SBC sent.
 *
 * Mounted at the ROOT path (excluded from the /api/v1 prefix in main.ts) because
 * that exact URL is what's registered as the client's redirect_uri on SBC.
 */
@Controller()
export class SsoBridgeController {
  @Public()
  @Version(VERSION_NEUTRAL)
  @Get('auth/callback')
  callback(@Query() query: Record<string, string>, @Res() res: Response): void {
    const code = (query.code ?? '').trim();
    const state = query.state ?? '';
    const hasCode = code.length > 0;

    // Everything SBC sent (minus code/state) — surfaced when no code arrives.
    const otherParams = Object.entries(query)
      .filter(([k]) => k !== 'code' && k !== 'state')
      .map(([k, v]) => `${escapeHtml(k)} = ${escapeHtml(String(v))}`)
      .join('<br/>');

    const body = hasCode
      ? `<p>Connexion réussie ✓<br/>Copie ce code et colle-le dans l'application
           (bouton « J'ai un code »).</p>
         <code id="code">${escapeHtml(code)}</code>
         <button class="btn" id="copy">Copier le code</button>
         <p class="hint">Astuce : appuie longuement sur le code pour le copier.</p>
         <a class="btn sec" id="open" href="sbccontacts://auth/callback?code=${encodeURIComponent(
           code,
         )}${state ? `&state=${encodeURIComponent(state)}` : ''}">Ouvrir l'application (si installée)</a>`
      : `<p class="err">Aucun code d'autorisation reçu de SBC.</p>
         ${otherParams ? `<p class="hint">SBC a renvoyé :</p><code>${otherParams}</code>` : ''}
         <p class="hint">Réessaie la connexion depuis l'application.</p>`;

    const safeCode = JSON.stringify(code);
    const html = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>SBC Contacts — Connexion</title>
<style>
  :root{--p:#1862F0;--g:#92B127;--o:#F49101}
  *{box-sizing:border-box;font-family:-apple-system,Segoe UI,Roboto,sans-serif}
  body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#F4F7FD;color:#0f172a}
  .card{background:#fff;max-width:440px;width:92%;padding:28px;border-radius:20px;box-shadow:0 10px 32px rgba(24,98,240,.12);text-align:center}
  .arc{height:6px;border-radius:6px;background:linear-gradient(90deg,var(--p),var(--g) 55%,var(--o));margin:0 auto 18px;width:120px}
  h1{font-size:20px;margin:0 0 6px}
  p{color:#475569;font-size:14px;margin:6px 0 14px}
  .btn{display:block;width:100%;padding:14px;border:0;border-radius:12px;background:var(--p);color:#fff;font-size:15px;font-weight:700;text-decoration:none;margin:8px 0;cursor:pointer}
  .btn.sec{background:#EDF2FB;color:var(--p)}
  code{display:block;word-break:break-all;background:#F1F5F9;padding:14px;border-radius:10px;font-size:13px;margin:12px 0;user-select:all;-webkit-user-select:all;cursor:pointer;text-align:left}
  .hint{font-size:12px;color:#94a3b8;margin-top:4px}
  .err{color:#EF4444;font-weight:600}
</style>
</head>
<body>
<div class="card">
  <div class="arc"></div>
  <h1>Connexion SBC</h1>
  ${body}
</div>
<script>
  var code = ${safeCode};
  var codeEl = document.getElementById('code');
  var btn = document.getElementById('copy');
  if (code && codeEl) {
    codeEl.onclick = function(){
      var r = document.createRange(); r.selectNodeContents(codeEl);
      var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
    };
  }
  if (code && btn) {
    function copied(){ btn.textContent = 'Code copié ✓'; }
    function legacyCopy(){
      try {
        var ta = document.createElement('textarea');
        ta.value = code; ta.setAttribute('readonly','');
        ta.style.position='fixed'; ta.style.top='0'; ta.style.opacity='0';
        document.body.appendChild(ta); ta.focus(); ta.select();
        ta.setSelectionRange(0, code.length);
        var okc = document.execCommand('copy');
        document.body.removeChild(ta);
        okc ? copied() : (btn.textContent = 'Sélectionne le code puis copie-le');
      } catch(e){ btn.textContent = 'Sélectionne le code puis copie-le'; }
    }
    btn.onclick = function(){
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(code).then(copied).catch(legacyCopy);
      } else { legacyCopy(); }
    };
  }
</script>
</body>
</html>`;

    res.status(200).type('html').send(html);
  }
}
