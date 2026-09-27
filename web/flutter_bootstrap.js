// 自定义 Flutter Web 启动配置（构建时 {{...}} 占位符会被自动替换）。
//
// 默认情况下 CanvasKit 与回退字体（Noto Sans SC / Roboto）都从 gstatic.com
// 下载，国内访问失败/缓慢会导致首屏中文缺字。这里改为：
// - CanvasKit：直接用构建产物自带的本地副本 ./canvaskit/
// - 回退字体：走同源 /gstatic/ 代理（线上由 Vercel Edge Function
//   api/gstatic.js 转发到 fonts.gstatic.com，本地开发由 dev_proxy.py 转发），
//   响应带一年期 immutable 缓存，首次之后全部命中浏览器缓存。
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: './canvaskit/',
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      fontFallbackBaseUrl: '/gstatic/',
    });
    await appRunner.runApp();
  },
});
