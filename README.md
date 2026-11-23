# 静默快拍 QuietSnap

自己维护的 Theos 插件：音量键手势触发**后台拍照 / 录像 / 录音**。
面向 iPhone 14 Pro Max · iOS 16.5 · Dopamine (roothide 隐根)。

> 本项目是独立实现，与 K2gecamen 无任何代码关系，不含任何授权校验或破解逻辑。

## 功能

| 功能 | 说明 |
|---|---|
| 拍照 | AVCapturePhotoOutput，支持后置/前置/0.5x 超广角 |
| 录像 | AVCaptureMovieFileOutput，含麦克风音轨，可设 24/30/60 fps |
| 录音 | AVAudioRecorder，AAC 44.1kHz 立体声，可与其他音频混音 |
| 手势 | 音量加/减 的单击、双击、长按，三功能可分别绑定 |
| 控制中心 | 录音 / 录像 两个 1×1 磁贴（依赖 CCSupport） |
| 锁屏 | 可选「锁屏时禁用手势」 |
| 静音 | 可选「静音拍摄」：拍摄窗口内屏蔽系统快门/提示音 |
| 提示 | 可选「显示提示浮层」：开始/保存时显示不可触摸的轻提示 |
| 限制 | 可选最长录像时长；剩余空间低于 200 MB 时自动跳过 |
| 语言 | 中文 / English（en.lproj） |
| 输出 | 保存到相册，或保存到自定义目录（默认 `/var/mobile/Media/QuietSnap`） |
| 反馈 | 触感反馈可开关 |

同一手势绑定多个功能时，优先级：**照片 > 录像 > 录音**。

## 目录结构

```
QuietSnap/
├── Hooks/AxsQuietSnapMain.xm          # SBVolumeHardwareButton 手势入口 + %ctor
├── Headers/AxsQuietSnapPrivate.h      # SpringBoard 私有类声明
├── Sources/
│   ├── AxsQuietSnapConfig.*           # 配置快照（只读）
│   ├── AxsQuietSnapPreferences.h      # 读写偏好（面板写、插件读）
│   ├── AxsQuietSnapPaths.h            # rootless / roothide 路径适配
│   ├── AxsQuietSnapGesture.*          # 单击/双击/长按状态机
│   ├── AxsQuietSnapCapture.*          # 手势 → 拍照/录像/录音调度
│   ├── AxsQuietSnapPhoto.*            # 拍照
│   ├── AxsQuietSnapVideo.*            # 录像
│   ├── AxsQuietSnapAudio.*            # 录音
│   └── AxsQuietSnapStorage.*          # 目录/文件名/相册写入
├── AxsQuietSnapPrefs/                 # 设置面板（PreferenceLoader）
├── AxsQuietSnapCCAudio/               # 控制中心：录音磁贴
├── AxsQuietSnapCCVideo/               # 控制中心：录像磁贴
├── AxsQuietSnap.plist                 # 注入过滤器（仅 SpringBoard）
├── docs/BUILD.md                      # 构建步骤与常见错误
├── docs/ACCEPTANCE.md                 # 真机验收清单
├── tools/smoke-test.sh                # 设备端自检脚本
└── build.sh                           # rootful / rootless / roothide 构建
```

## 构建环境

- 需要 [theos](https://theos.dev)（roothide 打包请用 roothide 维护的 theos 分支）
- iOS SDK 16.5（`AxsQuietSnapBuild.mk` 中已固定）
- 依赖头文件：`rootless.h` 或 `roothide.h`（随对应 theos 提供）

```sh
export THEOS=~/theos
cd QuietSnap

sh build.sh roothide        # 生成 roothide 包（本机目标环境）
# 或同时构建：
sh build.sh rootful rootless roothide
```

产物：`packages/com.axs.quietsnap_5.2.0_iphoneos-arm64.deb`（文件名随 scheme 变化）。

安装（设备上）：

```sh
dpkg -i com.axs.quietsnap_*.deb
killall -9 SpringBoard
```

## 使用

1. 设置面板：**设置 → 静默快拍**，打开「启用插件」。
2. 分别给拍照/录像/录音绑定手势（默认：双击音量加=拍照，长按音量加=录像，长按音量减=录音）。
3. 控制中心：编辑控制中心，添加「静默录音」「静默录像」磁贴；点击即开始/停止。
   磁贴状态会优先读取真实录制状态。
4. 触发后：
   - 拍照：震动 → 约 0.5–1 秒后保存；
   - 录像：震动 → 开始/停止；
   - 录音：震动 → 开始/停止。
5. 日志（Mac 或设备终端）：

```sh
log stream --predicate 'process == "SpringBoard"' | grep QuietSnap
```

## 权限（重要）

拍照/录音走系统 TCC。SpringBoard 不是普通 App，可能没有相机/麦克风授权：

- 若日志出现 `AVErrorApplicationIsNotAuthorizedToUseDevice`（-11852），需要给
  `com.apple.springboard` 授予 TCC 权限。
- 常见做法是使用你越狱环境里的 **TCC 绕过** 插件；或手动写入 TCC 数据库（**先备份**）：

```sh
# 设备上以 root 执行，路径与表结构随 iOS 版本不同，请先确认
cp /var/mobile/Library/TCC/TCC.db /var/mobile/Library/TCC/TCC.db.bak
sqlite3 /var/mobile/Library/TCC/TCC.db "
INSERT OR REPLACE INTO access
(service, client, client_type, auth_value, auth_reason, auth_version,
 indirect_object_identifier, flags, last_modified)
VALUES
('kTCCServiceCamera','com.apple.springboard',0,2,4,1,'UNUSED',0,strftime('%s','now')),
('kTCCServiceMicrophone','com.apple.springboard',0,2,4,1,'UNUSED',0,strftime('%s','now')),
('kTCCServicePhotos','com.apple.springboard',0,2,4,1,'UNUSED',0,strftime('%s','now')),
('kTCCServicePhotosAdd','com.apple.springboard',0,2,4,1,'UNUSED',0,strftime('%s','now'));
"
killall -9 tccd SpringBoard
```

> 改 TCC.db 属于系统级修改，可能导致权限异常；操作前务必备份。
> 另外 iOS 会检查 `NSCameraUsageDescription` / `NSMicrophoneUsageDescription`：
> 若 SpringBoard 缺少对应描述，首次调用可能直接崩溃（安全模式）。
> 这种情况下请先用 TCC 绕过插件，或给 SpringBoard 的 Info.plist 补上描述后再启用。

## 已知限制

- 相机在 SpringBoard 内启动，首次拍摄有约 0.5–1 秒初始化延迟。
- 录像与拍照不能同时进行（同一摄像头会话）；录像时拍照会被跳过。
- 录音与录像不能同时进行。
- **不隐藏**系统相机/麦克风指示点（绿点/橙点），这是有意为之。
- 控制中心磁贴依赖 **CCSupport**；安装/更新后需注销一次，并在控制中心手动添加。
- 控制中心与手势共用同一录制状态：录像中点击录音磁贴会被忽略，反之亦然。
- 「静音拍摄」通过 hook `AudioServicesPlaySystemSound*` 实现，只作用于 SpringBoard 进程内、且仅限拍摄窗口（约 2 秒）；不会全局静音，也不影响震动。
- 4K + 60fps 可能不被所有镜头支持，插件会自动退回设备支持的分辨率。

## 校验

```sh
python3 ~/path/to/axs-ios-tweaks/scripts/doctor.py QuietSnap
```

`doctor.py` 会对 `captureOutput:...`、`audioRecorderDidFinishRecording:...` 等
**AVFoundation 协议方法名**，以及 CC 模块要求的 `iconGlyph` / `isSelected` / `setSelected:`
报 “custom selector lacks plugin prefix”。这些名字由系统协议/CCSupport 规定，不能改名，属静态规则误报。
