// Vercel Edge Function：掌上公交接口同源代理。
// 上游接口风控只认 Origin: https://h5.mygolbs.com（错误/缺失时返回加密垃圾），
// 而浏览器禁止 JS 设置 Origin，因此 Web 端必须经由本代理注入该请求头。
export const config = { runtime: 'edge' };

const UPSTREAM = 'https://h5.mygolbs.com/ApiData.do';
const FAKE_ORIGIN = 'https://h5.mygolbs.com';

export default async function handler(req) {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
      },
    });
  }

  let resp;
  try {
    resp = await fetch(UPSTREAM, {
      method: 'POST',
      headers: {
        'Content-Type':
          req.headers.get('content-type') ??
          'application/x-www-form-urlencoded',
        // 风控关键头：必须是 h5.mygolbs.com 自身
        Origin: FAKE_ORIGIN,
        Referer: `${FAKE_ORIGIN}/`,
        'User-Agent':
          req.headers.get('user-agent') ??
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
      body: await req.text(),
      // 上游若响应慢，避免边缘函数长时间挂起
      signal: AbortSignal.timeout(20000),
    });
  } catch (e) {
    // 上游连接失败/超时/DNS 异常：此前未捕获会导致 Edge 返回无细节的
    // 「internal error」；现在把原因带回给客户端展示
    return new Response(
      JSON.stringify({
        status: '99',
        msg: `代理请求失败：${e?.message ?? e}`,
      }),
      {
        status: 502,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-store',
        },
      },
    );
  }

  const headers = new Headers(resp.headers);
  headers.delete('content-encoding'); // 边缘运行时自动解压，避免下游二次解压报错
  headers.delete('content-length');
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Cache-Control', 'no-store');

  return new Response(resp.body, {
    status: resp.status,
    headers,
  });
}
