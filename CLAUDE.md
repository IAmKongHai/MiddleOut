# CLAUDE.md

## Release & Notarization Workflow

发布 DMG 前必须完成 Apple 公证，否则用户安装时会被 Gatekeeper 拦截。

### 步骤

```bash
# 1. Release 构建
xcodebuild -project MiddleOut.xcodeproj -scheme MiddleOut -configuration Release clean build CONFIGURATION_BUILD_DIR=/tmp/MiddleOut-Release

# 2. 用 Developer ID 证书签名（必须带 --options runtime）
codesign --force --options runtime \
  --entitlements MiddleOut/MiddleOut.entitlements \
  --sign "Developer ID Application: XIANLIANG XIE (2ZSNV9MWK6)" \
  /tmp/MiddleOut-Release/MiddleOut.app

# 3. 打包 DMG
mkdir -p /tmp/MiddleOut-dmg-staging
cp -R /tmp/MiddleOut-Release/MiddleOut.app /tmp/MiddleOut-dmg-staging/
ln -s /Applications /tmp/MiddleOut-dmg-staging/Applications
hdiutil create -volname "MiddleOut" -srcfolder /tmp/MiddleOut-dmg-staging -ov -format UDZO MiddleOut-vX.X.dmg
rm -rf /tmp/MiddleOut-dmg-staging

# 4. 提交公证（等待 Apple 审核通过）
xcrun notarytool submit MiddleOut-vX.X.dmg --keychain-profile "notarytool-profile" --wait

# 5. 装订公证票据到 DMG
xcrun stapler staple MiddleOut-vX.X.dmg
```

### 注意事项

- Keychain profile `notarytool-profile` 已存储（Apple ID: konghai007@gmail.com, Team: 2ZSNV9MWK6）
- 如果 profile 丢失，重新存储：`xcrun notarytool store-credentials "notarytool-profile" --apple-id konghai007@gmail.com --team-id 2ZSNV9MWK6`
- 签名必须用 **Developer ID Application** 证书，不能用 Development 证书
- `--options runtime` 是公证的硬性要求（Hardened Runtime）
- DMG 文件不要提交到 git
