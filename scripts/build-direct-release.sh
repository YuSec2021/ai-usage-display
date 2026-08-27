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
version="$(awk '/MARKETING_VERSION:/ { print $2; exit }' "$project_root/project.yml")"
tag_name="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
dmg_name="AI-Usage-$version.dmg"
dmg_path="$dist_dir/$dmg_name"

cd "$project_root"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "缺少 XcodeGen。请先执行：brew install xcodegen" >&2
    exit 1
fi

echo "[1/6] 检查发布版本"
"$script_dir/verify-release-version.sh" "${tag_name:-$version}"

echo "[2/6] 生成 Xcode 工程"
xcodegen generate

echo "[3/6] 构建 Release 通用版本"
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

echo "[4/6] 确认“关于”页面版本"
"$script_dir/verify-release-version.sh" "${tag_name:-$version}" "$app_source"

echo "[5/6] 添加临时代码签名并创建 DMG"
rm -rf "$staging_dir"
mkdir -p "$staging_dir" "$dist_dir"
ditto "$app_source" "$app_destination"
codesign --force --deep --sign - --options runtime --timestamp=none "$app_destination"
codesign --verify --deep --strict --verbose=2 "$app_destination"

ln -s /Applications "$staging_dir/Applications"
rm -f "$dmg_path" "$dmg_path.sha256"
hdiutil create \
    -volname "AI Usage" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path"

echo "[6/6] 生成 SHA-256"
(
    cd "$dist_dir"
    shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
)

echo
echo "发布包：$dmg_path"
echo "校验文件：$dmg_path.sha256"
echo "注意：此版本使用临时签名，未经过 Apple 公证。"
