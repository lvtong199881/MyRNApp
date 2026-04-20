#!/bin/bash
# React Native Bundle Debug 发布脚本
# 用法: ./debug.sh

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

# 1. 获取 package.json 版本作为 base 版本
CURRENT_VERSION=$(node -p "require('./package.json').version")
if [ -z "$CURRENT_VERSION" ]; then
    echo "❌ 无法读取 package.json 版本"
    exit 1
fi
echo "📌 当前版本: $CURRENT_VERSION"

# 查找该版本之后的最新 debug 版本号
LATEST_DEBUG=$(git tag -l | grep "^v${CURRENT_VERSION}\\." | sort -V | tail -1 | sed 's/^v//')
if [ -z "$LATEST_DEBUG" ]; then
    # 第一个 debug 版本
    NEW_VERSION="${CURRENT_VERSION}.0"
else
    # 自增最后一位
    LAST_NUM=$(echo "$LATEST_DEBUG" | awk -F. '{print $NF}')
    NEW_NUM=$((LAST_NUM + 1))
    NEW_VERSION="${CURRENT_VERSION}.${NEW_NUM}"
fi
echo "🆕 Debug 版本: $CURRENT_VERSION → $NEW_VERSION"

# 2. 更新 package.json
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.version = '$NEW_VERSION';
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
"
echo "✅ package.json 已更新"

# 3. npm install 更新 package-lock.json
echo "📦 运行 npm install..."
npm install --silent
echo "✅ package-lock.json 已更新"

# 4. 清理并打包 bundle（Android + iOS）
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

# 5. 获取上一个版本的 commit SHA
PREV_TAG=$(git describe --tags --abbrev=0 HEAD~0 2>/dev/null | sed 's/^v//')
if [ -z "$PREV_TAG" ]; then
    PREV_COMMIT=$(git rev-list --max-parents=0 HEAD --format=%s | head -1)
    PREV_COMMIT="initial"
else
    PREV_COMMIT=$(git log --oneline -1 | awk '{print $1}')
fi
echo "📝 上一个版本 commit: $PREV_COMMIT"

# 6. 生成 changelog 内容
CHANGELOG_CONTENT="## v$NEW_VERSION ($(date '+%Y-%m-%d'))

### 改动
"
# 获取自上一个版本以来的所有 commit（带链接，排除 release/debug commit）
COMMIT_BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/commit"
if [ "$PREV_COMMIT" != "initial" ]; then
    COMMITS=$(git log $PREV_COMMIT..HEAD --format="- %s ([%h](${COMMIT_BASE_URL}/%H))" --grep -E "release:|debug:" --invert-grep 2>/dev/null)
    if [ -n "$COMMITS" ]; then
        CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
${COMMITS}"
    else
        CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
- 自动版本更新"
    fi
else
    COMMITS=$(git log --oneline --format="- %s ([%h](${COMMIT_BASE_URL}/%H))" --grep -E "release:|debug:" --invert-grep 2>/dev/null)
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

# 7. 更新 CHANGELOG.md
if [ -f CHANGELOG.md ]; then
    echo "$CHANGELOG_CONTENT" | cat - CHANGELOG.md > temp_changelog.md && mv temp_changelog.md CHANGELOG.md
else
    echo "# Changelog" > CHANGELOG.md
    echo "" >> CHANGELOG.md
    echo "$CHANGELOG_CONTENT" >> CHANGELOG.md
fi
echo "✅ CHANGELOG.md 已更新"

# 8. Git 提交
git add -A
git commit -m "debug: v$NEW_VERSION"
echo "✅ 已提交: debug: v$NEW_VERSION"

# 9. Git 推送（先 pull rebase 处理冲突）
git fetch origin
git pull --rebase origin main
git push
echo "✅ 已推送到远程仓库"

# 10. 生成 commit diff（带链接，排除 release/debug commit）
echo "📝 生成 commit diff..."
COMMIT_BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/commit"
if [ "$PREV_COMMIT" != "initial" ]; then
    TAG_MESSAGE=$(git log $PREV_COMMIT..HEAD --format="• %s ([%h](${COMMIT_BASE_URL}/%H))" --grep -E "release:|debug:" --invert-grep 2>/dev/null)
else
    TAG_MESSAGE=$(git log --oneline --format="• %s ([%h](${COMMIT_BASE_URL}/%H))" --grep -E "release:|debug:" --invert-grep 2>/dev/null)
fi
git tag -a "v$NEW_VERSION" -m "${TAG_MESSAGE}"
git push origin "v$NEW_VERSION"
echo "✅ 已创建并推送 tag: v$NEW_VERSION"

# 11. 创建 GitHub Release
echo "📦 创建 GitHub Release..."
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
echo "✅ Release v$NEW_VERSION 已创建"

# 12. 上传 bundle 文件到 Release
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
echo "🔧 Debug v$NEW_VERSION 完成!"
echo "========================================"
echo "📦 Release: https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/v${NEW_VERSION}"
echo "========================================"
