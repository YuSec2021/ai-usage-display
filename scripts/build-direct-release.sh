#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
build_root="$project_root/.build/direct-release"
products_dir="$build_root/Build/Products/Release"
staging_dir="$build_root/dmg-root"
dist_dir="$project_root/dist"
app_source="$products_dir/AIUsage.app"
app_destination="$staging_dir/AI Usage.app"
version="1.1.0"
dmg_name="AI-Usage-$version.dmg"
dmg_path="$dist_dir/$dmg_name"

cd "$project_root"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "缺少 XcodeGen。请先执行：brew install xcodegen" >&2
    exit 1
fi

echo "[1/5] 生成 Xcode 工程"
xcodegen generate

echo "[2/5] 构建 Release 通用版本"
xcodebuild \
    -project AIUsage.xcodeproj \
    -scheme AIUsage \
    -configuration Release \
    -derivedDataPath "$build_root" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

if [[ ! -d "$app_source" ]]; then
    echo "未找到构建产物：$app_source" >&2
    exit 1
fi

echo "[3/5] 添加临时代码签名"
rm -rf "$staging_dir"
mkdir -p "$staging_dir" "$dist_dir"
ditto "$app_source" "$app_destination"
codesign --force --deep --sign - --options runtime --timestamp=none "$app_destination"
codesign --verify --deep --strict --verbose=2 "$app_destination"

echo "[4/5] 创建 DMG"
ln -s /Applications "$staging_dir/Applications"
rm -f "$dmg_path" "$dmg_path.sha256"
hdiutil create \
    -volname "AI Usage" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path"

echo "[5/5] 生成 SHA-256"
(
    cd "$dist_dir"
    shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
)

echo
echo "发布包：$dmg_path"
echo "校验文件：$dmg_path.sha256"
echo "注意：此版本使用临时签名，未经过 Apple 公证。"
