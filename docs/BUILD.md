# 构建步骤（第 1–2 步）

## 方式 A：GitHub Actions（无需 Mac）

1. 在 GitHub 新建空仓库 `QuietSnap`（不要勾选 README）。
2. 本机执行：

```sh
cd QuietSnap
git init
git add .
git commit -m "QuietSnap init"
git branch -M main
git remote add origin git@github.com:<你的用户名>/QuietSnap.git
git push -u origin main
```

3. 打开仓库 **Actions → Build**，工作流已启用 `rootless` + `roothide` 两个变体。
4. 构建完成后：
   - Artifacts：`packages-roothide`（zip，内含 deb）
   - 或 Releases 里的 `5.2.0-<run>` 发布包
5. 把 roothide 的 deb 传到手机安装：

```sh
# 手机 SSH 或 NewTerm
dpkg -i com.axs.quietsnap_5.2.0-*_iphoneos-arm64.deb
killall -9 SpringBoard
```

## 方式 B：本地 macOS + Theos

```sh
# 一次性准备
brew install ldid dpkg
git clone --recursive https://github.com/roothide/theos ~/theos
export THEOS=~/theos

# 构建
cd QuietSnap
sh build.sh roothide          # 只出 roothide 包
sh build.sh all               # 三种 scheme 全出
```

产物位于 `packages/`。

## 常见编译错误

| 报错 | 处理 |
|---|---|
| `'substrate.h' file not found` | Theos 的 include 目录缺 libsubstrate 头；重装/更新 theos |
| `'roothide.h' file not found` | 必须用 roothide/theos，且 `THEOS_PACKAGE_SCHEME=roothide` |
| `'rootless.h' file not found` | 构建 rootless 时需要 libroot 头；或用 `build.sh roothide` |
| `unknown type name 'uint32_t'` | 已加 `<stdint.h>`；若仍报，检查 SDK 头 |
| `dpkg-deb: command not found` | `brew install dpkg` |
| `error: unable to find SDK iphoneos16.5` | Xcode 15.4+，或改 `AxsQuietSnapBuild.mk` 的 SDK 版本 |
| `MSHookFunction was not declared` | 确认 `AxsQuietSnap_LIBRARIES = substrate` 且 substrate.h 存在 |

把 `make` 的完整报错发出来即可继续修。
