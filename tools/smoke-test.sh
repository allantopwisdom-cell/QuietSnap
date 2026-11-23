#!/bin/sh
# QuietSnap 装机自检脚本（在越狱设备上以 root 执行）
# 用法：ssh root@device 'sh /path/to/smoke-test.sh'
set -u

PKG="com.axs.quietsnap"
echo "== 1. 包状态 =="
if command -v dpkg >/dev/null 2>&1; then
    dpkg -s "$PKG" 2>/dev/null | sed -n '1,12p' || echo "未安装 $PKG"
else
    echo "找不到 dpkg"
fi

echo
echo "== 2. 已安装文件 =="
if command -v dpkg >/dev/null 2>&1; then
    dpkg -L "$PKG" 2>/dev/null | sed -n '1,40p'
fi

echo
echo "== 3. 关键文件定位 =="
for base in /var/jb / ; do
    for f in \
        "$base/Library/MobileSubstrate/DynamicLibraries/AxsQuietSnap.dylib" \
        "$base/Library/MobileSubstrate/DynamicLibraries/AxsQuietSnap.plist" \
        "$base/Library/PreferenceBundles/AxsQuietSnapPrefs.bundle/AxsQuietSnapPrefs" \
        "$base/Library/ControlCenter/Bundles/AxsQuietSnapCCAudio.bundle/AxsQuietSnapCCAudio" \
        "$base/Library/ControlCenter/Bundles/AxsQuietSnapCCVideo.bundle/AxsQuietSnapCCVideo"; do
        [ -e "$f" ] && echo "OK   $f" || echo "MISS $f"
    done
done

echo
echo "== 4. 当前偏好 =="
PREF="/var/mobile/Library/Preferences/${PKG}.plist"
if [ -f "$PREF" ]; then
    if command -v plutil >/dev/null 2>&1; then
        plutil -p "$PREF" 2>/dev/null | sed -n '1,30p'
    else
        echo "$PREF 存在（无 plutil）"
    fi
else
    echo "尚未写入偏好：$PREF（打开设置面板改一次即可生成）"
fi

echo
echo "== 5. 进程 =="
pgrep -l SpringBoard 2>/dev/null || ps aux 2>/dev/null | grep -i springboard | grep -v grep | head -3
echo
echo "== 6. 实时日志（Ctrl+C 退出）=="
echo "执行：log stream --predicate 'process == \"SpringBoard\"' | grep QuietSnap"
echo
echo "提示：装完/改完设置后需要 killall -9 SpringBoard 才会重载插件。"
