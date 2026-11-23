# 真机验收清单（第 5 步）

设备：iPhone 14 Pro Max · iOS 16.5 · Dopamine 3.0.13-30（roothide）

## 安装后

```sh
dpkg -i com.axs.quietsnap_*.deb
killall -9 SpringBoard
log stream --predicate 'process == "SpringBoard"' | grep QuietSnap
```

预期日志：

```
[QuietSnap] loaded (enabled=NO)
```

## 用例

| # | 操作 | 预期 | 关键日志 |
|---|---|---|---|
| 1 | 打开设置 → 静默快拍 | 面板正常，无崩溃 | — |
| 2 | 打开「启用插件」 | 配置写入 `com.axs.quietsnap.plist` | — |
| 3 | 双击音量加（默认） | 震动，约 1 秒后相册多一张照片 | `photo saved` |
| 4 | 长按音量加 | 震动，开始录像；再长按停止 | `video started` / `video stopping` |
| 5 | 长按音量减 | 开始录音；再长按停止，生成 `.m4a` | `audio started` / `audio stopping` |
| 6 | 录像时播放音乐 | 音乐不中断（mix 开） | — |
| 7 | 控制中心添加两个磁贴 | 点击可开始/停止，图标高亮同步 | — |
| 8 | 打开「锁屏时禁用」，锁屏后按手势 | 无任何动作 | 无日志 |
| 9 | 关闭「静音拍摄」再拍照 | 能听到系统快门声 | — |
| 10 | 关闭「显示提示浮层」 | 不再出现轻提示 | — |
| 11 | 改保存目录到 `/var/mobile/Media/Test` | 文件写到新目录 | — |
| 12 | 4K + 60fps 录像 | 设备不支持时自动降级，不崩溃 | — |
| 13 | 录像中触发拍照 | 拍照被跳过，不崩溃 | `photo skipped: video recording` |
| 14 | 录音中触发录像 | 录像被跳过 | `video skipped: audio recording` |

## 失败排查

| 现象 | 检查 |
|---|---|
| 无 `[QuietSnap] loaded` | 注入失败：确认 `AxsQuietSnap.plist` 在 DynamicLibraries 下、包已 respring |
| 有 loaded，按键无反应 | `SBVolumeHardwareButton` 方法名不匹配；用 Frida 查该类方法列表 |
| `AVErrorApplicationIsNotAuthorizedToUseDevice (-11852)` | TCC：给 `com.apple.springboard` 相机/麦克风授权 |
| `audio started` 后无声 | 检查 `AVAudioSession` 是否被其他进程占用；确认麦克风 TCC |
| SpringBoard 进安全模式 | 删除插件或 `dpkg -r com.axs.quietsnap`；把崩溃日志发我 |

## 快速自检

```sh
sh tools/smoke-test.sh
```

脚本会检查包状态、关键文件、偏好文件与 SpringBoard 进程。
