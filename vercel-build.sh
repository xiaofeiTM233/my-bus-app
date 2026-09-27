#!/usr/bin/env bash
# Vercel 构建脚本：安装 Flutter 并构建 Web 产物
# 在 Vercel 项目设置中配置：
#   Framework Preset: Other
#   Build Command:    bash vercel-build.sh
#   Output Directory: build/web
set -e

FLUTTER_DIR="$HOME/flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

flutter config --no-analytics
flutter doctor -v
flutter pub get
# 注入构建 commit id（Vercel 提供 VERCEL_GIT_COMMIT_SHA）
flutter build web --release --dart-define=GIT_COMMIT="${VERCEL_GIT_COMMIT_SHA:-}"
