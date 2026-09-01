/**
 * loghub.js — 服务端日志汇聚 + 网页实时控制台（参考 mimo-proxy 的 console.py）
 *
 * - 零侵入接管 process.stdout.write，把 server.js 里所有 console.log 灌入环形缓冲，
 *   同时仍透传原 stdout（systemd journalctl / 终端照常可见）。
 * - 手写原生 WebSocket，向前端实时推送日志：连接后先发 history，再推增量 line。
 * - 可选访问口令：配置环境变量 CONSOLE_TOKEN 后需口令；未配置默认放行（本地调试）。
 */
const crypto = require('crypto');

const RING_MAX = 1000;
const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const COOKIE_NAME = 'todo_console_token';
const COOKIE_MAX_AGE = 7 * 24 * 3600;

const CONSOLE_TOKEN = process.env.CONSOLE_TOKEN || '';

// 环形缓冲：{ ts, msg }
const ring = [];
// 活跃的 WebSocket 客户端
const clients = new Set();

// ── 日志捕获（零侵入接管 stdout）──────────────────────────
const _origWrite = process.stdout.write.bind(process.stdout);
let pendingLine = '';

function pushLine(line) {
  const entry = { ts: Date.now(), msg: line };
  ring.push(entry);
  if (ring.length > RING_MAX) ring.shift();
  const payload = JSON.stringify({ type: 'line', data: entry });
  for (const c of clients) {
    try { c.sendText(payload); } catch (_) { /* 忽略单客户端异常 */ }
  }
}

function captureWrite(chunk, encoding, cb) {
  let text;
  try {
    text = typeof chunk === 'string' ? chunk : chunk.toString(encoding || 'utf8');
  } catch (_) {
    return _origWrite(chunk, encoding, cb);
  }
  pendingLine += text;
  let idx;
  while ((idx = pendingLine.indexOf('\n')) >= 0) {
    const line = pendingLine.slice(0, idx).replace(/\r$/, '');
    pendingLine = pendingLine.slice(idx + 1);
    if (line) {
      try { pushLine(line); } catch (_) { /* 日志本身出错不致命 */ }
    }
  }
  return _origWrite(chunk, encoding, cb);
}

function install() {
  process.stdout.write = captureWrite;
}

// ── 鉴权 ────────────────────────────────────────────────
function parseCookies(header = '') {
  const out = {};
  for (const part of header.split(';')) {
    const eq = part.indexOf('=');
    if (eq > 0) out[part.slice(0, eq).trim()] = decodeURIComponent(part.slice(eq + 1).trim());
  }
  return out;
}

function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));
}

function isAuthed(cookieHeader) {
  if (!CONSOLE_TOKEN) return true;
  const given = parseCookies(cookieHeader)[COOKIE_NAME] || '';
  return safeEqual(given, CONSOLE_TOKEN);
}

// ── 手写 WebSocket 服务端 ─────────────────────────────────
function sendFrame(socket, opcode, payload) {
  const buf = Buffer.isBuffer(payload) ? payload : Buffer.from(payload, 'utf8');
  const len = buf.length;
  let header;
  if (len < 126) {
    header = Buffer.from([0x80 | opcode, len]);
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  socket.write(Buffer.concat([header, buf]));
}

class WsClient {
  constructor(socket) {
    this.socket = socket;
    this._buf = Buffer.alloc(0);
    socket.on('data', (d) => this._onData(d));
    socket.on('close', () => clients.delete(this));
    socket.on('error', () => clients.delete(this));
  }

  sendText(text) { sendFrame(this.socket, 0x1, text); }
  sendPing() { sendFrame(this.socket, 0x9, Buffer.alloc(0)); }
  close() {
    try { sendFrame(this.socket, 0x8, Buffer.alloc(0)); } catch (_) { /* ignore */ }
    this.socket.destroy();
    clients.delete(this);
  }

  // 客户端只读，这里只解析帧并回应对手，不做业务
  _onData(chunk) {
    this._buf = Buffer.concat([this._buf, chunk]);
    for (;;) {
      if (this._buf.length < 2) return;
      const b0 = this._buf[0];
      const b1 = this._buf[1];
      const opcode = b0 & 0x0f;
      const masked = (b1 & 0x80) !== 0;
      let len = b1 & 0x7f;
      let offset = 2;
      if (len === 126) {
        if (this._buf.length < 4) return;
        len = this._buf.readUInt16BE(2);
        offset = 4;
      } else if (len === 127) {
        if (this._buf.length < 10) return;
        len = Number(this._buf.readBigUInt64BE(2));
        offset = 10;
      }
      const maskLen = masked ? 4 : 0;
      if (this._buf.length < offset + maskLen + len) return;
      if (opcode === 0x8) { // close
        this.close();
        return;
      } else if (opcode === 0x9) { // ping → pong
        try { sendFrame(this.socket, 0xA, Buffer.alloc(0)); } catch (_) { /* ignore */ }
      }
      this._buf = this._buf.slice(offset + maskLen + len);
    }
  }
}

function attachWebSocket(req, socket) {
  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }
  const accept = crypto.createHash('sha1').update(key + WS_GUID).digest('base64');
  const head = [
    'HTTP/1.1 101 Switching Protocols',
    'Upgrade: websocket',
    'Connection: Upgrade',
    `Sec-WebSocket-Accept: ${accept}`,
    '\r\n',
  ].join('\r\n');
  socket.write(head);
  const client = new WsClient(socket);
  clients.add(client);
  client.sendText(JSON.stringify({ type: 'history', data: ring.slice() }));
}

// 每 30s 发送一次 ping 保活，防止中间设备断开空闲连接
setInterval(() => {
  for (const c of clients) {
    try { c.sendPing(); } catch (_) { /* ignore */ }
  }
}, 30000).unref();

// ── HTTP 端点（/console /console/login /console/status）─────
function handleHttp(pathname, req, res) {
  if (pathname === '/console' && req.method === 'GET') {
    const html = isAuthed(req.headers.cookie) ? CONSOLE_HTML : LOGIN_HTML.replace('{{error}}', '');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return true;
  }
  if (pathname === '/console/login' && req.method === 'POST') {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      const token = (new URLSearchParams(body).get('token') || '').trim();
      if (CONSOLE_TOKEN && !safeEqual(token, CONSOLE_TOKEN)) {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(LOGIN_HTML.replace('{{error}}', '口令错误，请重试'));
        return;
      }
      const setCookie = `${COOKIE_NAME}=${encodeURIComponent(token || '')}; HttpOnly; Path=/; Max-Age=${COOKIE_MAX_AGE}; SameSite=Lax`;
      res.writeHead(303, { Location: '/console', 'Set-Cookie': setCookie });
      res.end();
    });
    return true;
  }
  if (pathname === '/console/status' && req.method === 'GET') {
    if (!isAuthed(req.headers.cookie)) {
      res.writeHead(401, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ error: 'unauthorized' }));
      return true;
    }
    const hasError = ring.some((e) => /error|错误|✗|fail/i.test(e.msg));
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ ring_size: ring.length, has_error: hasError }));
    return true;
  }
  return false;
}

// ── 前端：登录口令页 ──────────────────────────────────────
const LOGIN_HTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>运行日志 · 登录</title>
<style>
  :root { color-scheme: dark; }
  body { margin:0; font-family: system-ui,-apple-system,"Segoe UI",sans-serif;
         background:#0d1117; color:#e6edf3; display:flex; align-items:center;
         justify-content:center; min-height:100vh; }
  .card { background:#161b22; border:1px solid #30363d; border-radius:10px;
          padding:28px 30px; width:320px; box-shadow:0 8px 30px rgba(0,0,0,.4); }
  h1 { font-size:18px; margin:0 0 6px; }
  p.sub { color:#8b949e; font-size:13px; margin:0 0 18px; }
  input { width:100%; box-sizing:border-box; padding:10px 12px; border-radius:6px;
          border:1px solid #30363d; background:#0d1117; color:#e6edf3; font-size:14px; }
  input:focus { outline:none; border-color:#2f81f7; }
  button { width:100%; margin-top:14px; padding:10px; border:none; border-radius:6px;
           background:#238636; color:#fff; font-size:14px; cursor:pointer; }
  button:hover { background:#2ea043; }
  .err { color:#f85149; font-size:13px; margin-top:10px; min-height:18px; }
</style>
</head>
<body>
  <form class="card" method="post" action="/console/login">
    <h1>运行日志控制台</h1>
    <p class="sub">请输入访问口令以查看服务器实时日志</p>
    <input type="password" name="token" placeholder="访问令牌" autofocus required>
    <button type="submit">进入</button>
    <div class="err" id="err">{{error}}</div>
  </form>
</body>
</html>`;

// ── 前端：日志控制台页面 ──────────────────────────────────
const CONSOLE_HTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>运行日志</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin:0; font-family: system-ui,-apple-system,"Segoe UI","PingFang SC",sans-serif;
         background:#0d1117; color:#e6edf3; height:100vh; display:flex; flex-direction:column; }
  header { display:flex; align-items:center; gap:12px; padding:10px 16px;
           background:#161b22; border-bottom:1px solid #30363d; flex:0 0 auto; }
  .dot { width:12px; height:12px; border-radius:50%; background:#f85149; flex:0 0 auto; }
  .dot.green { background:#2ea043; box-shadow:0 0 8px #2ea043aa; }
  .dot.red   { background:#f85149; box-shadow:0 0 8px #f85149aa; }
  .title { font-size:14px; font-weight:600; }
  .meta { font-size:12px; color:#8b949e; }
  .spacer { flex:1; }
  #updated { font-size:12px; color:#8b949e; }
  #togglePause { background:#21262d; color:#e6edf3; border:1px solid #30363d;
                 border-radius:6px; padding:6px 12px; font-size:12px; cursor:pointer; }
  #togglePause:hover { background:#30363d; }
  #togglePause.paused { border-color:#1f6feb; color:#58a6ff; }
  main { flex:1 1 auto; overflow-y:auto; padding:8px 16px; background:#0d1117; }
  .line { font-family: ui-monospace,SFMono-Regular,Consolas,"Courier New",monospace;
          font-size:12.5px; line-height:1.6; white-space:pre-wrap; word-break:break-all;
          color:#c9d1d9; }
  .line .ts { color:#57606a; margin-right:8px; }
  .line.err   { color:#f85149; }
  .line.warn  { color:#d29922; }
  .empty { color:#57606a; font-size:13px; text-align:center; padding:40px 0; }
  .spinner { color:#8b949e; font-size:13px; padding:8px 0; }
</style>
</head>
<body>
  <header>
    <div class="dot" id="dot"></div>
    <span class="title" id="statusText">连接中…</span>
    <span class="spacer"></span>
    <span class="meta" id="updated"></span>
    <button id="togglePause">暂停滚动</button>
  </header>
  <main id="log"><div class="spinner">正在连接实时日志…</div></main>
  <script>
    const dot=document.getElementById('dot'), statusText=document.getElementById('statusText'),
          updated=document.getElementById('updated'), logEl=document.getElementById('log'),
          toggleBtn=document.getElementById('togglePause');
    let paused=false;
    function esc(s){ const d=document.createElement('div'); d.textContent=s; return d.innerHTML; }
    function levelOf(msg){
      if(/error|错误|✗|fail|✖/i.test(msg)) return 'err';
      if(/warn|警告|⚠/i.test(msg)) return 'warn';
      return '';
    }
    function addLine(e){
      const div=document.createElement('div');
      div.className='line '+(levelOf(e.msg)||'');
      const ts=e.ts?new Date(e.ts).toLocaleTimeString():'';
      div.innerHTML='<span class="ts">['+esc(ts)+']</span>'+esc(e.msg);
      logEl.appendChild(div);
      if(!paused) logEl.scrollTop=logEl.scrollHeight;
    }
    async function refreshStatus(){
      let hasError=false,size=0;
      try{ const r=await fetch('/console/status'); if(r.ok){ const j=await r.json(); hasError=j.has_error; size=j.ring_size; } }catch(_){}
      if(hasError){ dot.className='dot red'; statusText.textContent='运行中 · 近期有报错'; }
      else { dot.className='dot green'; statusText.textContent='运行正常'; }
      updated.textContent='缓冲 '+size+' 条 · '+new Date().toLocaleTimeString();
    }
    function connect(){
      const proto=location.protocol==='https:'?'wss':'ws';
      const ws=new WebSocket(proto+'://'+location.host+'/console/ws');
      ws.onopen=function(){ refreshStatus(); };
      ws.onmessage=function(ev){
        const m=JSON.parse(ev.data);
        if(m.type==='history'){
          logEl.innerHTML='';
          if(!m.data||!m.data.length){ logEl.innerHTML='<div class="empty">暂无日志</div>'; }
          else { for(const e of m.data){ addLine(e); } }
        } else if(m.type==='line'){ addLine(m.data); }
      };
      ws.onclose=function(){
        if(!logEl.querySelector('.empty')&&!logEl.querySelector('.line')){
          logEl.innerHTML='<div class="empty">与实时日志的连接已断开，正在重连…</div>';
        }
        dot.className='dot red'; statusText.textContent='日志连接断开，重连中';
        setTimeout(connect,2000);
      };
    }
    toggleBtn.addEventListener('click',function(){
      paused=!paused;
      logEl.classList.toggle('paused',paused);
      toggleBtn.classList.toggle('paused',paused);
      toggleBtn.textContent=paused?'恢复滚动':'暂停滚动';
    });
    refreshStatus(); connect(); setInterval(refreshStatus,10000);
  </script>
</body>
</html>`;

module.exports = { install, attachWebSocket, handleHttp };
