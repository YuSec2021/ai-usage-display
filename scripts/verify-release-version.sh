#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
tag_name="${1:-}"
app_path="${2:-}"

if [[ -z "$tag_name" ]]; then
    echo "用法：$0 <tag> [AIUsage.app]" >&2
    exit 1
fi

release_version="${tag_name#v}"
project_file="$project_root/project.yml"
about_view="$project_root/Sources/AIUsage/Views/SettingsView.swift"
project_version="$(
    awk '/MARKETING_VERSION:/ { print $2; exit }' "$project_file"
)"

if [[ -z "$project_version" ]]; then
    echo "无法从 project.yml 读取 MARKETING_VERSION。" >&2
    exit 1
fi

if [[ "$release_version" != "$project_version" ]]; then
    echo "版本不一致：Tag 为 $tag_name，项目版本为 $project_version。" >&2
    echo "请先更新 project.yml，并确认“关于”页面显示新版本。" >&2
    exit 1
fi

if ! grep -q 'forInfoDictionaryKey: "CFBundleShortVersionString"' "$about_view"; then
    echo "“关于”页面未从 CFBundleShortVersionString 读取版本。" >&2
    echo "请检查 SettingsView.versionDescription。" >&2
    exit 1
fi

if [[ -n "$app_path" ]]; then
    info_plist="$app_path/Contents/Info.plist"
    if [[ ! -f "$info_plist" ]]; then
        echo "找不到应用 Info.plist：$info_plist" >&2
        exit 1
    fi

    app_version="$(/usr/libexec/PlistBuddy -c \
        'Print :CFBundleShortVersionString' "$info_plist")"
    if [[ "$app_version" != "$release_version" ]]; then
        echo "版本不一致：Tag 为 $tag_name，构建出的 App 为 $app_version。" >&2
        echo "“关于”页面将显示错误版本，停止发布。" >&2
        exit 1
    fi
fi

echo "版本检查通过：Tag、项目配置与“关于”页面均为 $release_version。"
