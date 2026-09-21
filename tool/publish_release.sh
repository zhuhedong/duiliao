#!/usr/bin/env bash
set -e

# ==============================================================================
# Duiliao 移动端自动发版与 GitHub Release 推送脚本
# 用法:
#   ./tool/publish_release.sh [version_tag] [release_message]
# 示例:
#   ./tool/publish_release.sh v1.0.1 "iOS 27 玻璃拟态重构与在线升级支持"
# ==============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TAG="$1"
MESSAGE="$2"

if [ -z "$TAG" ]; then
  # 尝试从 duiliao_app/pubspec.yaml 读取版本号
  APP_VERSION=$(grep '^version:' duiliao_app/pubspec.yaml | sed 's/version:[[:space:]]*//;s/+.*//')
  TAG="v$APP_VERSION"
  echo "未指定标签，默认使用 pubspec.yaml 版本: $TAG"
fi

# 确保以 'v' 开头
if [[ ! "$TAG" =~ ^v ]]; then
  TAG="v$TAG"
fi

if [ -z "$MESSAGE" ]; then
  MESSAGE="Duiliao 随身运营端 $TAG 发布"
fi

# 检查当前分支
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "==> 当前分支: $BRANCH"
echo "==> 准备发布标签: $TAG"
echo "==> 发版说明: $MESSAGE"

# 检查是否存在未提交的修改
if ! git diff-index --quiet HEAD --; then
  echo "警告: 检测到未提交的本地更改，正在自动提交..."
  git add .
  git commit -m "chore(release): prepare for release $TAG"
  git push origin "$BRANCH"
fi

# 检查标签是否已存在
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "错误: 标签 $TAG 在本地已存在！"
  echo "如需重新发布，请先删除旧标签: git tag -d $TAG && git push origin :refs/tags/$TAG"
  exit 1
fi

# 创建带附注的标签
echo "==> 创建本地 Git 标签: $TAG"
git tag -a "$TAG" -m "$MESSAGE"

# 推送标签到远端
echo "==> 推送标签 $TAG 到远端 origin..."
git push origin "$TAG"

echo ""
echo "=============================================================================="
echo "🎉 标签 $TAG 推送成功！"
echo "GitHub Actions CI/CD 已自动触发。"
echo "正在自动执行:"
echo "  1. 编译 Android Release APK (含 arm64-v8a 优化包)"
echo "  2. 自动创建 GitHub Release"
echo "  3. 自动生成更新日志并上传 APK 资产"
echo "手机端将在检测更新时自动收到新版本推送与应用内升级提示！"
echo "=============================================================================="
