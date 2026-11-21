// READ-ONLY by itself: sends the one HTTP request it is given and nothing else.
//
// The Node half of the shared transport's fallback (Dw.Http.ps1). Some sandboxed agent shells
// run PowerShell under a restricted token that cannot acquire TLS credentials from the platform
// (SEC_E_NO_CREDENTIALS), so every HTTPS call from PowerShell fails while Node, which ships its
// own TLS, still connects. Invoke-DwHttp hands such a call to this helper.
//
// Input (stdin, one JSON object): { url, method, headers: {name: value}, bodyBase64?,
//   timeoutSec (0 = none), skipCertificateCheck, followRedirects }.
// Output (stdout, one JSON object): { status, statusText, url, headers: {name: [values]}, bodyHex }
//   or { error: { kind: timeout|tls|dns|connect|other, code, message } }.
// The request, its headers and any token travel on stdin only, never on the command line, and
// nothing here prints a header. Requires Node 18 or later (global fetch).
//
// Example: echo {"url":"http://127.0.0.1:8080/"} | node Dw.Http.mjs

const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const text = Buffer.concat(chunks).toString('utf8').replace(/^﻿/, '');

function answer(value) {
  process.stdout.write(JSON.stringify(value));
}

function classify(error) {
  const cause = error && error.cause ? error.cause : {};
  const code = String(cause.code || error.code || '');
  const name = String((error && error.name) || '');
  let kind = 'other';
  if (name === 'TimeoutError' || name === 'AbortError' || code === 'UND_ERR_CONNECT_TIMEOUT' || code === 'UND_ERR_HEADERS_TIMEOUT' || code === 'UND_ERR_BODY_TIMEOUT') kind = 'timeout';
  else if (code === 'ENOTFOUND' || code === 'EAI_AGAIN') kind = 'dns';
  else if (/CERT|SELF_SIGNED|UNABLE_TO_VERIFY|ERR_TLS|ERR_SSL/.test(code)) kind = 'tls';
  else if (code === 'ECONNREFUSED' || code === 'ECONNRESET' || code === 'EHOSTUNREACH' || code === 'ENETUNREACH') kind = 'connect';
  const detail = cause && cause.message && cause.message !== error.message ? `: ${cause.message}` : '';
  return { kind, code, message: `${(error && error.message) || 'request failed'}${detail}` };
}

let request;
try {
  request = JSON.parse(text);
} catch {
  answer({ error: { kind: 'other', code: 'BAD_INPUT', message: 'The Node transport received no JSON request on stdin.' } });
  process.exit(0);
}

// The certificate bypass follows the caller's gate (a loopback base URL or an explicit opt-in);
// this process carries one request, so the setting dies with it.
if (request.skipCertificateCheck) process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

const init = {
  method: request.method || 'GET',
  headers: request.headers || {},
  redirect: request.followRedirects === false ? 'manual' : 'follow'
};
if (typeof request.bodyBase64 === 'string') init.body = Buffer.from(request.bodyBase64, 'base64');
if (Number(request.timeoutSec) > 0) init.signal = AbortSignal.timeout(Number(request.timeoutSec) * 1000);

try {
  const response = await fetch(request.url, init);
  const body = Buffer.from(await response.arrayBuffer());
  const headers = {};
  response.headers.forEach((value, name) => {
    if (name === 'set-cookie') return;
    headers[name] = [value];
  });
  const cookies = typeof response.headers.getSetCookie === 'function' ? response.headers.getSetCookie() : [];
  if (cookies.length) headers['set-cookie'] = cookies;
  answer({ status: response.status, statusText: response.statusText, url: response.url, headers, bodyHex: body.toString('hex') });
} catch (error) {
  answer({ error: classify(error) });
}
