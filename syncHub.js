/**
 * syncHub.js — 服务端数据变更广播 WebSocket 服务
 *
 * 让所有打开的前端页面实时感知数据变化：任一标签页增删改待办/分类/设置后，
 * 服务端向所有在线页面推送 { type: 'changed' }，前端收到后重新拉取数据实现多端同步。
 *
 * - 手写原生 WebSocket（参照 loghub.js 的成熟实现）：握手 + 发送分帧 + 30s ping 保活。
 * - 只做「单向广播」，客户端状态只通过下游重新 GET 拉取，服务端不缓存业务数据。
 * - 不做鉴权，与 /api/* 数据接口当前无鉴权的现状保持一致（局域网个人应用）。
 */
const crypto = require('crypto');

const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

// 活跃的数据同步 WebSocket 客户端
const dataClients = new Set();

// ── 发送分帧（服务端不掩码）──────────────────────────────
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

class SyncClient {
  constructor(socket) {
    this.socket = socket;
    this._buf = Buffer.alloc(0);
    socket.on('data', (d) => this._onData(d));
    socket.on('close', () => dataClients.delete(this));
    socket.on('error', () => dataClients.delete(this));
  }

  sendText(text) { sendFrame(this.socket, 0x1, text); }
  sendPing() { sendFrame(this.socket, 0x9, Buffer.alloc(0)); }
  close() {
    try { sendFrame(this.socket, 0x8, Buffer.alloc(0)); } catch (_) { /* ignore */ }
    this.socket.destroy();
    dataClients.delete(this);
  }

  // 客户端只读，仅解析帧以处理 close/ping，不做业务
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

function attachSocket(req, socket) {
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
  dataClients.add(new SyncClient(socket));
}

// 向所有在线页面广播「数据已变更」信号
function broadcast() {
  const payload = JSON.stringify({ type: 'changed' });
  for (const c of dataClients) {
    try { c.sendText(payload); } catch (_) { /* 忽略单客户端异常 */ }
  }
}

// 每 30s ping 保活，防止中间设备断开空闲连接
setInterval(() => {
  for (const c of dataClients) {
    try { c.sendPing(); } catch (_) { /* ignore */ }
  }
}, 30000).unref();

module.exports = { attachSocket, broadcast };