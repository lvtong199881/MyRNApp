#!/bin/bash
# React Native Bundle 发布脚本
# 用法:
#   ./release.sh        # 发布 release 版本
#   ./release.sh debug  # 发布 debug 版本

set -e

# 配置
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_OWNER="lvtong199881"
REPO_NAME=$(node -p "require('./package.json').name")
MODE="${1:-release}"

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

# 根据模式选择标题和 commit 过滤规则
if [ "$MODE" == "debug" ]; then
    echo "========================================"
    echo "🔧 React Native Bundle Debug Release"
    echo "========================================"
    COMMIT_FILTER="release:|debug:"
    COMMIT_PREFIX="debug"
    VERSION_PATTERN='^v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
else
    echo "========================================"
    echo "📦 React Native Bundle Release"
    echo "========================================"
    COMMIT_FILTER="release:|debug:"
    COMMIT_PREFIX="release"
    VERSION_PATTERN='^v[0-9]+\.[0-9]+\.[0-9]+$'
fi

# 1. 获取最新 tag 并计算新版本
LATEST_TAG=$(git tag -l --sort=-v:refname | grep -E "$VERSION_PATTERN" | head -1 | sed 's/^v//')
if [ -z "$LATEST_TAG" ]; then
    echo "❌ 未找到 tag"
    exit 1
fi
echo "📌 当前版本: $LATEST_TAG"

if [ "$MODE" == "debug" ]; then
    # Debug: 自增最后一位
    LAST_NUM=$(echo "$LATEST_TAG" | awk -F. '{print $NF}')
    NEW_NUM=$((LAST_NUM + 1))
    BASE_VERSION=$(echo "$LATEST_TAG" | sed 's/\.[^.]*$//')
    NEW_VERSION="${BASE_VERSION}.${NEW_NUM}"
else
    # Release: 取前3段，自增 patch
    IFS='.' read -ra PARTS <<< "$LATEST_TAG"
    MAJOR="${PARTS[0]}"
    MINOR="${PARTS[1]}"
    PATCH=$(echo "${PARTS[2]}" | sed -E 's/[^0-9].*$//')
    NEW_PATCH=$((PATCH + 1))
    NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"
fi
echo "🆕 新版本: $LATEST_TAG → $NEW_VERSION"

# 2. 更新 package.json
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.version = '$NEW_VERSION';
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
"
echo "✅ package.json 已更新为 v$NEW_VERSION"

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
PREV_COMMIT=$(git log --oneline -2 | tail -1 | awk '{print $1}')
if [ -z "$PREV_COMMIT" ]; then
    PREV_COMMIT="initial"
fi
echo "📝 上一个版本 commit: $PREV_COMMIT"

# 6. 生成 changelog 内容
CHANGELOG_CONTENT="## v$NEW_VERSION ($(date '+%Y-%m-%d'))

### 改动
"
COMMIT_BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/commit"
if [ "$PREV_COMMIT" != "initial" ]; then
    COMMITS=$(git log $PREV_COMMIT..HEAD --format="- %s ([%h](${COMMIT_BASE_URL}/%H))" 2>/dev/null | grep -v -E "$COMMIT_FILTER" || true)
    if [ -n "$COMMITS" ]; then
        CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
${COMMITS}"
    else
        CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
- 自动版本更新"
    fi
else
    COMMITS=$(git log --oneline --format="- %s ([%h](${COMMIT_BASE_URL}/%H))" 2>/dev/null | grep -v -E "$COMMIT_FILTER" || true)
    if [ -n "$COMMITS" ]; then
        CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
${COMMITS}"
    else
        CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
- 初始版本"
    fi
fi
CHANGELOG_CONTENT="${CHANGELOG_CONTENT}"

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
git commit -m "${COMMIT_PREFIX}: v$NEW_VERSION"
echo "✅ 已提交: ${COMMIT_PREFIX}: v$NEW_VERSION"

# 9. Git 推送（先 pull rebase 处理冲突）
git fetch origin
git pull --rebase origin main
git push
echo "✅ 已推送到远程仓库"

# 10. 生成 tag message 并创建 tag
echo "📝 生成 commit diff..."
if [ "$PREV_COMMIT" != "initial" ]; then
    TAG_MESSAGE=$(git log $PREV_COMMIT..HEAD --format="• %s ([%h](${COMMIT_BASE_URL}/%H))" 2>/dev/null | grep -v -E "$COMMIT_FILTER" || true)
else
    TAG_MESSAGE=$(git log --oneline --format="• %s ([%h](${COMMIT_BASE_URL}/%H))" 2>/dev/null | grep -v -E "$COMMIT_FILTER" || true)
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

# 转换 COMMIT_PREFIX 首字母大写
PREFIX_DISPLAY=$(echo "$COMMIT_PREFIX" | sed 's/.*/\U&/')

echo ""
echo "========================================"
echo "🎉 ${PREFIX_DISPLAY} v$NEW_VERSION 完成!"
echo "========================================"
echo "📦 Release: https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/v${NEW_VERSION}"
echo "========================================"
