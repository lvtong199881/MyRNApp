#!/bin/bash
# React Native Bundle 发布脚本
# 用法: ./release.sh

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
echo "📦 React Native Bundle Release"
echo "========================================"

# 1. 读取当前版本
CURRENT_VERSION=$(node -p "require('./package.json').version")
echo "📌 当前版本: $CURRENT_VERSION"

# 2. 计算下一个 release 版本
# 规则：如果是 debug 版本（4段），去掉第4段再自增；否则直接自增 patch
# 例如: 0.0.12.0 → 0.0.13, 0.0.12-mhs.0 → 0.0.13, 0.0.12 → 0.0.13

IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
if [ "${#VERSION_PARTS[@]}" -eq 4 ]; then
    # Debug 版本：去掉第4段，取前3段
    MAJOR="${VERSION_PARTS[0]}"
    MINOR="${VERSION_PARTS[1]}"
    PATCH=$(echo "${VERSION_PARTS[2]}" | sed -E 's/[^0-9].*$//')
else
    # 普通版本：直接取3段
    MAJOR="${VERSION_PARTS[0]}"
    MINOR="${VERSION_PARTS[1]}"
    PATCH=$(echo "${VERSION_PARTS[2]:-0}" | sed -E 's/[^0-9].*$//')
fi
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"
echo "🆕 新版本: $CURRENT_VERSION → $NEW_VERSION"

# 3. 更新 package.json
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.version = '$NEW_VERSION';
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
"
echo "✅ package.json 已更新"

# 4. npm install 更新 package-lock.json
echo "📦 运行 npm install..."
npm install --silent
echo "✅ package-lock.json 已更新"

# 5. 清理并打包 bundle（Android + iOS）
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

# 6. 获取上一个版本的 commit SHA
PREV_COMMIT=$(git log --oneline -2 | tail -1 | awk '{print $1}')
if [ -z "$PREV_COMMIT" ]; then
    PREV_COMMIT=$(git rev-list --max-parents=0 HEAD --format=%s | head -1)
    PREV_COMMIT="initial"
fi
echo "📝 上一个版本 commit: $PREV_COMMIT"

# 7. 生成 changelog 内容
CHANGELOG_CONTENT="## v$NEW_VERSION ($(date '+%Y-%m-%d'))

### 改动
"
# 获取自上一个版本以来的所有 commit（带链接，排除 release commit）
COMMIT_BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/commit"
if [ "$PREV_COMMIT" != "initial" ]; then
    COMMITS=$(git log $PREV_COMMIT..HEAD --format="- %s ([%h](${COMMIT_BASE_URL}/%H))" --grep="release:" --invert-grep 2>/dev/null)
    if [ -n "$COMMITS" ]; then
        CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
${COMMITS}"
    else
        CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
- 自动版本更新"
    fi
else
    COMMITS=$(git log --oneline --format="- %s ([%h](${COMMIT_BASE_URL}/%H))" --grep="release:" --invert-grep 2>/dev/null)
    if [ -n "$COMMITS" ]; then
        CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
${COMMITS}"
    else
        CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
- 初始版本"
    fi
fi
CHANGELOG_CONTENT="${CHANGELOG_CONTENT}

"

# 8. 更新 CHANGELOG.md
if [ -f CHANGELOG.md ]; then
    echo "$CHANGELOG_CONTENT" | cat - CHANGELOG.md > temp_changelog.md && mv temp_changelog.md CHANGELOG.md
else
    echo "# Changelog" > CHANGELOG.md
    echo "" >> CHANGELOG.md
    echo "$CHANGELOG_CONTENT" >> CHANGELOG.md
fi
echo "✅ CHANGELOG.md 已更新"

# 9. Git 提交
git add -A
git commit -m "release: v$NEW_VERSION"
echo "✅ 已提交: release: v$NEW_VERSION"

# 10. Git 推送（先 pull rebase 处理冲突）
git fetch origin
git pull --rebase origin main
git push
echo "✅ 已推送到远程仓库"

# 11. 生成 commit diff（带链接，排除 release commit）
echo "📝 生成 commit diff..."
COMMIT_BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/commit"
if [ "$PREV_COMMIT" != "initial" ]; then
    TAG_MESSAGE=$(git log $PREV_COMMIT..HEAD --format="• %s ([%h](${COMMIT_BASE_URL}/%H))" --grep="release:" --invert-grep 2>/dev/null)
else
    TAG_MESSAGE=$(git log --oneline --format="• %s ([%h](${COMMIT_BASE_URL}/%H))" --grep="release:" --invert-grep 2>/dev/null)
fi
git tag -a "v$NEW_VERSION" -m "${TAG_MESSAGE}"
git push origin "v$NEW_VERSION"
echo "✅ 已创建并推送 tag: v$NEW_VERSION"

# 12. 创建 GitHub Release
echo "📦 创建 GitHub Release..."
# 使用 node 生成 JSON payload（避免 shell 转义问题）
PAYLOAD=$(node -e "
const msg = \`${TAG_MESSAGE}\`;
console.log(JSON.stringify({
  tag_name: 'v${NEW_VERSION}',
  name: 'v${NEW_VERSION}',
  body: msg
}));")
RELEASE_RESPONSE=$(curl -s -X POST "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

# 解析 release ID（兼容多种响应格式）
RELEASE_ID=$(echo "$RELEASE_RESPONSE" | node -e "
const data = require('fs').readFileSync(0, 'utf8');
try {
  const json = JSON.parse(data);
  console.log(json.id || '');
} catch(e) {
  console.log('');
}")

if [ -z "$RELEASE_ID" ]; then
    echo "❌ Release 创建失败"
    echo "响应: $RELEASE_RESPONSE"
    exit 1
fi

if echo "$RELEASE_RESPONSE" | grep -q '"id"'; then
    echo "✅ Release v$NEW_VERSION 已创建"
else
    echo "ℹ️ Release 可能已存在，尝试获取..."
fi

# 13. 获取 release ID
RELEASE_ID=$(curl -s "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/v${NEW_VERSION}" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" | node -e "
const data = require('fs').readFileSync(0, 'utf8');
try {
  const json = JSON.parse(data);
  console.log(json.id || '');
} catch(e) {
  console.log('');
}
")

if [ -z "$RELEASE_ID" ]; then
    echo "❌ 无法获取 Release ID"
    exit 1
fi
echo "📦 Release ID: $RELEASE_ID"

# 14. 上传 bundle 文件到 Release（带错误检查）
upload_asset() {
    local file="$1"
    local name="$2"
    local response
    local asset_id

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
echo "🎉 Release v$NEW_VERSION 完成!"
echo "========================================"
echo "📦 Release: https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/v${NEW_VERSION}"
echo "========================================"
