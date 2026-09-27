// Vercel Edge Function：fonts.gstatic.com 同源代理（Flutter Web 回退字体）。
//
// 引擎按 fontFallbackBaseUrl + 字体路径请求，如：
//   /gstatic/s/notosanssc/v37/xxx.woff2
// 本函数把它转发到 https://fonts.gstatic.com/s/notosanssc/v37/xxx.woff2。
// 兼容引擎剥掉「/s/」前缀的拼接方式（/gstatic/notosanssc/...）。
export const config = { runtime: 'edge' };

const UPSTREAM = 'https://fonts.gstatic.com';

export default async function handler(req) {
  const url = new URL(req.url);
  let path = (url.searchParams.get('path') ?? '').replace(/^\/+/, '');
  if (!path) return new Response('missing path', { status: 400 });
  if (!path.startsWith('s/')) path = `s/${path}`;
  // 只放行官方字体路径形态：s/<family>/<version>/<file>
  if (!/^s\/[a-z0-9-]+\/v\d+\//i.test(path)) {
    return new Response('forbidden', { status: 403 });
  }
  const resp = await fetch(`${UPSTREAM}/${path}`, {
    headers: {
      'User-Agent':
        req.headers.get('user-agent') ??
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
    signal: AbortSignal.timeout(20000),
  });
  const headers = new Headers(resp.headers);
  headers.delete('content-encoding'); // 边缘运行时已解压，避免下游二次解压报错
  headers.delete('content-length');
  headers.set('Access-Control-Allow-Origin', '*');
  // 字体文件内容不变，长缓存彻底消除「首次加载缺字」
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  return new Response(resp.body, {
    status: resp.status,
    headers,
  });
}
