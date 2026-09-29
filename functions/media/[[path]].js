const RANGE = /^bytes=(\d*)-(\d*)$/;

/**
 * Range の値を、ファイルの大きさに収まる [start, end]（end を含む）にする。
 * 1 つの範囲だけ扱う。読めない・範囲外なら null。
 * @param {string} header - Range ヘッダーの値（例: "bytes=0-99"）
 * @param {number} size - ファイルの大きさ（バイト）
 * @returns {[number, number] | null} 範囲
 * @example
 * parseRange('bytes=0-99', 1000) // [0, 99]
 * parseRange('bytes=-100', 1000) // [900, 999]
 */
const parseRange = (header, size) => {
  const m = RANGE.exec(header.trim());
  if (!m || (m[1] === '' && m[2] === '')) return null;
  if (m[1] === '') {
    const suffix = Number(m[2]);
    if (suffix === 0) return null;
    return [Math.max(0, size - suffix), size - 1];
  }
  const start = Number(m[1]);
  const end = m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1);
  if (start >= size || start > end) return null;
  return [start, end];
};

/**
 * 動画などの静的ファイルを、Range リクエストに対応して返す。
 * Pages の静的配信は Range に 200 で全体を返すので、iOS Safari が動画を再生できない。そのための 206。
 * ファイルは数 MB までなので、全体を読んでから切り出す。
 * @param {{ request: Request, env: { ASSETS: { fetch: (req: Request | string) => Promise<Response> } } }} context
 * @returns {Promise<Response>}
 */
const handle = async (context) => {
  const { request } = context;
  const res = await context.env.ASSETS.fetch(new Request(request.url, { method: 'GET' }));
  const range = request.headers.get('Range');
  // 無いファイルは Pages が index.html を返すので、そのまま渡す
  if (!res.ok || (res.headers.get('Content-Type') ?? '').startsWith('text/html')) return res;

  const headers = new Headers(res.headers);
  headers.set('Accept-Ranges', 'bytes');
  headers.set('Cache-Control', 'public, max-age=86400');
  const body = await res.arrayBuffer();
  const size = body.byteLength;

  if (!range) {
    headers.set('Content-Length', String(size));
    return new Response(request.method === 'HEAD' ? null : body, { status: 200, headers });
  }

  const r = parseRange(range, size);
  if (!r) {
    headers.set('Content-Range', `bytes */${size}`);
    return new Response(null, { status: 416, headers });
  }
  const [start, end] = r;
  headers.set('Content-Range', `bytes ${start}-${end}/${size}`);
  headers.set('Content-Length', String(end - start + 1));
  return new Response(request.method === 'HEAD' ? null : body.slice(start, end + 1), { status: 206, headers });
};

export const onRequestGet = handle;
export const onRequestHead = handle;
