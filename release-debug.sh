#!/bin/bash
# React Native Bundle Debug 发布脚本
# 用法: ./release-debug.sh

set -e

# 配置
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_OWNER="lvtong199881"
REPO_NAME=$(node -p "require('./package.json').name")

# 从环境变量或配置文件读取 GitHub Token
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$GITHUB_TOKEN" ]; then
    if [ -f "$HOME/.github_token" ]; then
        GITHUB_TOKEN=$(cat "$HOME/.github_token")
    fi
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ 未设置 GITHUB_TOKEN 环境变量，也找不到 ~/.github_token 文件"
    exit 1
fi

cd "$REPO_DIR"

# 检查是否有未提交的改动
if [ -n "$(git status --porcelain)" ]; then
    echo "❌ 存在未提交的改动，请先提交或stash："
    git status --short
    exit 1
fi

# 检查 Node.js 版本
echo "📌 Node 版本: $(node --version)"
NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo "❌ Node.js 版本过低，需要 >= 18"
    exit 1
fi

echo "========================================"
echo "🔧 React Native Bundle Debug Release"
echo "========================================"

# 1. 获取当前 release 版本号，并生成 debug 版本
CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
if [ -z "$CURRENT_VERSION" ]; then
    echo "❌ 未找到 release 版本 tag"
    exit 1
fi
echo "📌 当前 release 版本: $CURRENT_VERSION"

# 查找该 release 版本之后的最新 debug 版本号
LATEST_DEBUG=$(git tag -l | grep "^v${CURRENT_VERSION}." | sort -V | tail -1 | sed 's/^v//')
if [ -z "$LATEST_DEBUG" ]; then
    # 第一个 debug 版本
    NEW_VERSION="${CURRENT_VERSION}.0"
else
    # 自增最后一位
    LAST_NUM=$(echo "$LATEST_DEBUG" | awk -F. '{print $NF}')
    NEW_NUM=$((LAST_NUM + 1))
    NEW_VERSION="${CURRENT_VERSION}.${NEW_NUM}"
fi
echo "🔖 Debug 版本: $CURRENT_VERSION → $NEW_VERSION"

# 2. 打包 bundle（Android + iOS）
echo "🔨 打包 bundle..."
rm -rf dist/
mkdir -p dist

bundle_android() {
    node node_modules/@react-native-community/cli/build/bin.js bundle \
      --platform android \
      --dev false \
      --entry-file index.js \
      --bundle-output ./dist/index.android.bundle > /dev/null 2>&1
}

bundle_ios() {
    node node_modules/@react-native-community/cli/build/bin.js bundle \
      --platform ios \
      --dev false \
      --entry-file index.js \
      --bundle-output ./dist/index.ios.bundle > /dev/null 2>&1
}

bundle_android
if [ ! -s dist/index.android.bundle ]; then
    echo "❌ Android Bundle 生成失败"
    exit 1
fi
echo "✅ Android Bundle: dist/index.android.bundle"

bundle_ios
if [ ! -s dist/index.ios.bundle ]; then
    echo "❌ iOS Bundle 生成失败"
    exit 1
fi
echo "✅ iOS Bundle: dist/index.ios.bundle"

# 3. 创建 git tag
echo "🏷️ 创建 git tag..."
git tag -a "v$NEW_VERSION" -m "Debug release v$NEW_VERSION"
git push origin "v$NEW_VERSION"
echo "✅ 已创建并推送 tag: v$NEW_VERSION"

# 4. 创建 GitHub Release
echo "📦 创建 GitHub Release..."
PAYLOAD=$(node -e "
const msg = 'Debug release v${NEW_VERSION}';
console.log(JSON.stringify({
  tag_name: 'v${NEW_VERSION}',
  name: 'v${NEW_VERSION}',
  body: msg
}));
")
RELEASE_RESPONSE=$(curl -s -X POST "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

RELEASE_ID=$(echo "$RELEASE_RESPONSE" | node -e "
const data = require('fs').readFileSync(0, 'utf8');
try {
  const json = JSON.parse(data);
  console.log(json.id || '');
} catch(e) {
  console.log('');
}
")

if [ -z "$RELEASE_ID" ]; then
    echo "❌ Release 创建失败"
    echo "响应: $RELEASE_RESPONSE"
    exit 1
fi
echo "✅ Release v$NEW_VERSION 已创建"

# 5. 上传 bundle 文件到 Release
upload_asset() {
    local file="$1"
    local name="$2"

    response=$(curl -s -w "%{http_code}" -X POST "https://uploads.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/${RELEASE_ID}/assets?name=${name}" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Content-Type: application/octet-stream" \
      --data-binary @"${file}")

    if echo "$response" | grep -q '"id"'; then
        echo "✅ ${name} 已上传"
        return 0
    else
        echo "❌ ${name} 上传失败"
        return 1
    fi
}

echo "📤 上传 bundle 文件..."
upload_asset "dist/index.android.bundle" "index.android.bundle"
upload_asset "dist/index.ios.bundle" "index.ios.bundle"

echo ""
echo "========================================"
echo "🔧 Debug Release v$NEW_VERSION 完成!"
echo "========================================"
echo "📦 Release: https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/v${NEW_VERSION}"
echo "========================================"
