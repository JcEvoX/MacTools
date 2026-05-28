# 设备电量插件

`DeviceBattery` 在组件面板中聚合本机和外设电量。它不访问外部网页，也不会上传设备信息。

## 数据来源

- Mac 内置电池：`IOPowerSources`。
- 蓝牙与 Apple 外设：`system_profiler SPBluetoothDataType -json`、`IOBluetoothDevice` 和相关 `IORegistry` 服务。
- 雷柏 VT 系列鼠标：厂商 HID 接口，匹配 `VendorID = 0x24AE`、`PrimaryUsagePage = 0xFF00`、`PrimaryUsage = 0x0001`。

雷柏设备的 Product ID、report id 和电量偏移来自本地维护记录 `/Users/charles_lu/Downloads/rapoo-mouse-battery.md`。插件只监听 input report，不主动发送刷新命令。

## 布局

组件设置中提供三种布局：

- 网格：默认布局，适合 3 到 6 台设备同时扫读。
- 列表：适合长设备名、AirPods 分体电量和来源排查。
- 大卡片：参考 AirBattery 的大电量视觉，把低电量或主设备放在第一视觉层。

## 权限

系统电池和蓝牙系统信息通常不需要额外授权。雷柏 HID 读取可能被 macOS 归入输入监控权限；如果 `IOHIDManagerOpen` 返回 `0xE00002E2`，插件会提示打开输入监控设置。

