# 搞健康 后续发布规则

此项目是 V4.0 独立应用。每次后续改动版本号增加 0.01、构建号增加 1，版本以 Info.plist 为准。

- 使用 scripts/build.sh 构建本模块、小组件及应用，并以已授权 Apple Development 团队 5G96498KGJ 签名。
- 用户数据位于 ~/Library/Application Support/GaoSeries/Health/ 与 App Group 5G96498KGJ.com.gaoseries.GaoJianKang；凭据保留原系统钥匙串服务。
- 发布前安全备份并核验所有数据、PDF、Word、照片等附件。不得将缺失或无法读取的数据当作空白数据覆盖。
- 安装新版本、验证业务记录、游戏进度、附件及小组件后，清理旧程序和中间构建。不能删除用户数据或其备份。
- 如需修改其他独立应用，单独更新其源码、版本及安装包，不引用已删除的整合版工程。

- 升级前退出搞健康与搞节奏，运行 `python3 scripts/upgrade_data.py snapshot --version <新版本>`；安装后用返回的私有备份路径运行 `verify-live`，逐项查明所有资料、游戏进度和设置差异。完整保留原 App Group 中 `Health/health.sqlite` 与 `SharedSleep/sleep-records.sqlite`。
- `python3 Tests/test_upgrade_data.py` 和 `./scripts/test_backup.sh` 使用隔离资料/设置检查升级快照、附件、共享睡眠及完整恢复安全。

- `Sources/SharedSleepStore.swift` 是两应用共同的睡眠存档协议，修改时保持搞健康与搞节奏副本一致并分别测试。历史迁移只通过 `seedLegacyOnce` 执行；新记录使用去重写入，不得重复全量导入或覆写另一应用资料库。
