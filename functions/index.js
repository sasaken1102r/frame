const CLI_UA = /^(curl|wget|httpie|fetch|libfetch|python-requests|go-http-client)\b|\b(curl|wget|httpie)\//i;

/**
 * コマンドラインのツール（curl・wget など）からのアクセスなら、インストーラー i を返す。
 * ブラウザなら静的ファイル（説明ページ）に任せる。
 * @param {{ request: Request, env: { ASSETS: { fetch: (req: Request | string) => Promise<Response> } }, next: () => Promise<Response> }} context
 * @returns {Promise<Response>}
 */
const handle = async (context) => {
  const ua = context.request.headers.get('User-Agent') ?? '';
  if (!CLI_UA.test(ua)) return context.next();

  const res = await context.env.ASSETS.fetch(new URL('/i', context.request.url));
  if (!res.ok) return context.next();

  return new Response(res.body, {
    status: 200,
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'no-cache',
      'X-Content-Type-Options': 'nosniff',
    },
  });
};

/**
 * GET: curl・wget などにはインストーラーを返す
 * @param {Parameters<typeof handle>[0]} context
 * @returns {Promise<Response>}
 */
export const onRequestGet = (context) => handle(context);

/**
 * HEAD: curl -I でも GET と同じヘッダーが見えるようにする
 * @param {Parameters<typeof handle>[0]} context
 * @returns {Promise<Response>}
 */
export const onRequestHead = (context) => handle(context);
