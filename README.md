# MyRNApp

纯 React Native Bundle 项目，用于动态加载 React Native 页面。

## 项目结构

```
MyRNApp/
├── src/                    # 页面代码
│   └── App.tsx
├── dist/                   # 打包输出目录（不提交）
│   └── index.android.bundle
├── release.sh              # 发布脚本
├── package.json
└── ...
```

## 开发

```bash
# 安装依赖
npm install

# 开发调试
npm start

# 打包 Bundle
npm run release
```

## 发布流程

`npm run release` 会自动完成：

1. 读取 `package.json` version，自增 patch 版本
2. 更新 `package-lock.json`
3. 打包 bundle 到 `dist/index.android.bundle`
4. 生成 `CHANGELOG.md`
5. Git commit 并 push
6. 创建 git tag

## Bundle 加载

### Android
```
https://github.com/lvtong199881/MyRNApp/raw/{tag}/dist/index.android.bundle
```

### iOS
```
https://github.com/lvtong199881/MyRNApp/raw/{tag}/dist/main.jsbundle
```

或使用 main 分支：
- Android: `https://github.com/lvtong199881/MyRNApp/raw/main/dist/index.android.bundle`
- iOS: `https://github.com/lvtong199881/MyRNApp/raw/main/dist/main.jsbundle`
