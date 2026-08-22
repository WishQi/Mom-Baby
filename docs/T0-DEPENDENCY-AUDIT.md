# T0 依赖审计：GRDB.swift

| 项目 | 结论 |
| --- | --- |
| 审计日期 | 2026-08-22 |
| 审计范围 | T0 当前唯一第三方运行时依赖 `GRDB.swift` |
| 上游版本 | `7.11.1`（上游 tag `v7.11.1`） |
| SwiftPM requirement | `exact: "7.11.1"` |
| 产品 | `GRDB`；不使用 `GRDB-dynamic` |
| 当前 lockfile 解析值 | `7.11.1` / revision `b83108d10f42680d78f23fe4d4d80fc88dab3212` |
| 许可证 | MIT |
| SBOM | **NOT RUN** |
| 漏洞扫描 | **NOT RUN** |

## 1. 选择与锁定

T0 使用 [GRDB.swift `v7.11.1`](https://github.com/groue/GRDB.swift/releases/tag/v7.11.1)。截至审计日，GitHub 官方 latest release 将该版本标为非 draft、非 prerelease，发布日期为 2026-06-18。

仓库中的 [`MomBabyCore/Package.swift`](../MomBabyCore/Package.swift) 使用精确版本约束：

```swift
.package(
    url: "https://github.com/groue/GRDB.swift.git",
    exact: "7.11.1"
)
```

`Persistence` 依赖标准 `GRDB` product：

```swift
.product(name: "GRDB", package: "GRDB.swift")
```

选择标准、静态链接路径的 `GRDB`，不选择显式动态 product `GRDB-dynamic`。上游要求两个 product 只选一个，并建议不确定时优先 `GRDB`；`GRDB-dynamic` 面向多个 target 只链接一次共享动态 framework 的场景，T0 没有该需求。证据见上游 [Swift Package Manager 安装说明](https://github.com/groue/GRDB.swift/blob/v7.11.1/README.md#swift-package-manager) 和 [`Package.swift`](https://github.com/groue/GRDB.swift/blob/v7.11.1/Package.swift)。

精确版本 requirement 仍不能代替 lockfile。当前 [`MomBabyCore/Package.resolved`](../MomBabyCore/Package.resolved) 与 [Xcode workspace lockfile](../Mom-Baby.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved) 都将 `grdb.swift` 解析为 `7.11.1`、revision `b83108d10f42680d78f23fe4d4d80fc88dab3212`；这是审计时实际解析值，而不是根据 tag 名推测的 commit。两个入口的 lockfile 必须随依赖声明提交，后续实际解析结果继续以 lockfile 为准。

## 2. 工具链与平台边界

GRDB `7.11.1` 的官方要求为：

- Swift 6.1+ / Xcode 16.3+；
- iOS 13.0+、macOS 10.15+、tvOS 13.0+、watchOS 7.0+；
- SQLite 3.20.0+。

其包清单声明 `// swift-tools-version:6.1` 和 Swift language mode v6。证据见上游 [`README.md`](https://github.com/groue/GRDB.swift/blob/v7.11.1/README.md#grdb) 与 [`Package.swift`](https://github.com/groue/GRDB.swift/blob/v7.11.1/Package.swift)。MomBabyCore 当前声明 Swift tools 6.2、Swift 6 language mode，以及 iOS 18 / macOS 15 最低平台，不低于上游要求。

标准 GRDB 安装使用目标操作系统自带的 SQLite；锁定 GRDB 版本**不会**锁定系统 SQLite 的具体版本、编译选项或功能集合。因此：

- 不把某个 iOS 版本当前观察到的 SQLite patch version 写成应用合同；
- SQL、migration、约束及使用到的 SQLite 特性必须在最低支持系统上验证；
- 若未来依赖新的 SQLite 特性，需先明确其系统可用性或另立自定义 SQLite 方案 Gate。

证据见上游 [安装边界说明](https://github.com/groue/GRDB.swift/blob/v7.11.1/README.md#installation)。

## 3. 许可证

GRDB `v7.11.1` 的上游 [`LICENSE`](https://github.com/groue/GRDB.swift/blob/v7.11.1/LICENSE) 为 MIT License，版权声明为 `Copyright (C) 2015-2025 Gwendal Roué`。发布产物及第三方声明中必须保留该许可证要求的 copyright 和 permission notice。

本节只完成许可证文本识别，不代表 SBOM 或全供应链审计已经通过。

## 4. Privacy Manifest

GRDB `v7.11.1` 的包清单把 `GRDB/PrivacyInfo.xcprivacy` 复制为 target resource。官方 [`PrivacyInfo.xcprivacy`](https://github.com/groue/GRDB.swift/blob/v7.11.1/GRDB/PrivacyInfo.xcprivacy) 声明：

| Key | 上游内容 |
| --- | --- |
| `NSPrivacyTracking` | `false` |
| `NSPrivacyCollectedDataTypes` | 空数组 |
| `NSPrivacyTrackingDomains` | 空数组 |
| `NSPrivacyAccessedAPITypes` | 空数组 |

这只说明该版本 GRDB 自身的 manifest 内容，不替代 Mom-Baby 对自身数据收集和 Required Reason API 使用的声明，也不证明最终归档中所有依赖的 privacy manifest 已完整聚合。

每个 Release Candidate 必须用 Xcode Archive 生成 Privacy Report，检查 App 与所有嵌入 SDK 的聚合结果，并与仓库内 App manifest、实际代码路径及 App Store privacy labels 对照。Apple 对聚合报告的说明见 [Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests)。本次依赖审计没有生成 Archive privacy report。

## 5. 明确不引入的变体

### SQLCipher

T0 不引入 SQLCipher。上游说明 SwiftPM 下启用 SQLCipher 需要 fork GRDB 并修改其 `Package.swift`；上游包清单中的 SQLCipher dependency 和编译选项默认均被注释。标准 `GRDB` 使用系统 SQLite，不提供 SQLCipher 数据库加密。

若未来威胁模型或合规要求需要 SQLCipher，必须另立依赖和迁移 Gate，至少重新审查 fork 维护、SQLCipher 版本与许可证、密钥生命周期、明文库迁移、WAL/恢复行为、二进制冲突、SBOM、漏洞和隐私影响。证据见上游 [Encryption](https://github.com/groue/GRDB.swift/blob/v7.11.1/README.md#encryption) 说明。

### GRDB-dynamic

T0 不引入 `GRDB-dynamic`。若未来出现多个 target 必须共享同一动态 framework 的实际链接需求，再以包体、启动、符号和测试证据单独评估；不得同时链接 `GRDB` 与 `GRDB-dynamic`。

## 6. 未完成项与 Gate

| Gate | 当前状态 | 放行条件 |
| --- | --- | --- |
| Lockfile | 已生成；当前解析为 `7.11.1` / `b83108d10f42680d78f23fe4d4d80fc88dab3212` | 提交 `Package.resolved`；CI/发布所用实际 revision 继续以 lockfile 为准 |
| SBOM | **NOT RUN** | 对最终解析依赖生成并留存 SBOM；结果纳入发布记录 |
| 漏洞扫描 | **NOT RUN** | 扫描最终 lockfile/SBOM，人工处置命中项并记录依据 |
| Archive Privacy Report | **NOT RUN** | 每个 Release Candidate 生成聚合报告，并与 App manifest、实际 API 使用和 App Store labels 对照 |
| 最低系统 SQLite 验证 | 本审计未运行 | 在最低支持 iOS 18 / macOS 15 环境执行 schema、migration 和所用 SQLite 特性测试 |

任何 GRDB 版本升级都必须通过独立 PR 完成以下工作后才能合入：

1. 继续使用 exact requirement，更新并提交 `Package.resolved`；
2. 阅读目标版本 release notes 和适用的 migration guide；
3. 重新核对工具链、平台、系统 SQLite 边界和 product 选择；
4. 重新核对许可证与目标版本打包的 `PrivacyInfo.xcprivacy`；
5. 运行 schema/migration/恢复相关测试；
6. 重新生成 SBOM、执行漏洞扫描，并在 Release Candidate Archive 中复核 Privacy Report。

在上述状态仍为 `NOT RUN` 时，不得把对应 Gate 描述为“已通过”。

## 7. 固定验证入口

`scripts/verify-t0.sh` 是 T0 的固定本地/CI 入口：先核对附录 A 与 schema fixture、执行无敏感日志扫描，再通过共享 scheme 运行 Core、App unit 与 UI tests，最后执行 Swift 6 Release Simulator build。CI 可用 `MOMBABY_TEST_DESTINATION` 指定已安装的 iOS 18 模拟器；默认值为本仓库当前验证矩阵中的 `iPhone 16 Pro / iOS 18.6`。

该脚本存在不等于 Gate 已通过；SBOM、漏洞扫描、Archive Privacy Report、最终 `.app` entitlements 与真机文件保护仍按上表分别留存证据。
