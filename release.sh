#!/bin/bash
# React Native Bundle 发布脚本
# 用法: ./release.sh

set -e

# 配置
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$REPO_DIR"

# 检查是否有未提交的改动
if [ -n "$(git status --porcelain)" ]; then
    echo "❌ 存在未提交的改动，请先提交或stash："
    git status --short
    exit 1
fi

echo "========================================"
echo "📦 React Native Bundle Release"
echo "========================================"

# 1. 读取当前版本
CURRENT_VERSION=$(node -p "require('./package.json').version")
echo "📌 当前版本: $CURRENT_VERSION"

# 2. 自增 patch 版本
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR="${VERSION_PARTS[0]}"
MINOR="${VERSION_PARTS[1]}"
PATCH="${VERSION_PARTS[2]:-0}"
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

# 5. 打包 bundle（Android + iOS）
echo "🔨 打包 bundle..."
mkdir -p dist

# 优先使用 nvm 的 node，否则使用系统 node
if [ -d "$HOME/.nvm/versions/node/v24.14.0/bin/node" ]; then
    NODE_CMD="$HOME/.nvm/versions/node/v24.14.0/bin/node"
else
    NODE_CMD="node"
fi

$NODE_CMD node_modules/@react-native-community/cli/build/bin.js bundle \
  --platform android \
  --dev false \
  --entry-file index.js \
  --bundle-output ./dist/index.android.bundle > /dev/null 2>&1
echo "✅ Android Bundle: dist/index.android.bundle"

$NODE_CMD node_modules/@react-native-community/cli/build/bin.js bundle \
  --platform ios \
  --dev false \
  --entry-file index.js \
  --bundle-output ./dist/index.ios.bundle > /dev/null 2>&1
echo "✅ iOS Bundle: dist/index.ios.bundle"

# 6. 获取上一个版本的 commit SHA
PREV_COMMIT=$(git log --oneline -2 | tail -1 | awk '{print $1}')
echo "📝 上一个版本 commit: $PREV_COMMIT"

# 7. 生成 changelog 内容
CHANGELOG_CONTENT="## v$NEW_VERSION ($(date '+%Y-%m-%d'))

### 改动
"
# 获取自上一个版本以来的所有 commit
COMMITS=$(git log $PREV_COMMIT..HEAD --oneline --format="- %s")
if [ -n "$COMMITS" ]; then
    CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
${COMMITS}"
else
    CHANGELOG_CONTENT="${CHANGELOG_CONTENT}
- 自动版本更新"
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

# 10. Git 推送
git push
echo "✅ 已推送到远程仓库"

# 11. 创建 git tag
git tag -a "v$NEW_VERSION" -m "React Native Bundle v$NEW_VERSION"
git push origin "v$NEW_VERSION"
echo "✅ 已创建并推送 tag: v$NEW_VERSION"

echo ""
echo "========================================"
echo "🎉 Release v$NEW_VERSION 完成!"
echo "========================================"
