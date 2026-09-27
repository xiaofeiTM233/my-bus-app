// Vercel Edge Function：Nominatim 逆地理同源代理。
// 国内直连 nominatim.openstreetmap.org 不稳定，Web 端经此代理访问。
// 仅放行 /reverse（逆地理编码），查询参数原样透传。
export const config = { runtime: 'edge' };

const UPSTREAM = 'https://nominatim.openstreetmap.org';

export default async function handler(req) {
  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/api\/nominatim/, '') || '/';
  if (path !== '/reverse') {
    return new Response('forbidden', { status: 403 });
  }
  const resp = await fetch(`${UPSTREAM}${path}${url.search}`, {
    headers: {
      // Nominatim 使用政策要求可识别的 User-Agent
      'User-Agent':
        req.headers.get('user-agent') ?? 'my-bus-app/1.0 (bus arrival query)',
      'Accept-Language': 'zh-CN,zh;q=0.9',
    },
    signal: AbortSignal.timeout(15000),
  });
  const headers = new Headers(resp.headers);
  headers.delete('content-encoding');
  headers.delete('content-length');
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Cache-Control', 'no-store');
  return new Response(resp.body, {
    status: resp.status,
    headers,
  });
}
