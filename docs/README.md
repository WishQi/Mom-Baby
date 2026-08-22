# Mom-Baby 文档索引

## 产品与设计

- [`MVP-PRD.md`](./MVP-PRD.md)：产品范围、领域规则、验收标准和竞品研究。
- [`ADR-001-MVP-SCOPE-AND-DATA-BOUNDARY.md`](./ADR-001-MVP-SCOPE-AND-DATA-BOUNDARY.md)：已接受的 P0-L 范围、身份、备份、导出和未来云恢复决策。
- [`../prototype/README.md`](../prototype/README.md)：高保真交互原型与设计板使用方式。

## 技术方案

- [`MVP-TECHNICAL-ARCHITECTURE.md`](./MVP-TECHNICAL-ARCHITECTURE.md)：架构结论、纯端上/CloudKit/自建服务比较、范围调整和交付计划。
- [`MVP-IOS-TECHNICAL-DESIGN.md`](./MVP-IOS-TECHNICAL-DESIGN.md)：iOS 模块、数据库、计时、媒体、安全、导出、测试和实施顺序。
- [`T0-DEPENDENCY-AUDIT.md`](./T0-DEPENDENCY-AUDIT.md)：T0 当前第三方运行时依赖、精确锁定、许可证、Privacy Manifest 与尚未完成的供应链 Gate。
- [`MVP-LOCAL-ARCHIVE-SPEC.md`](./MVP-LOCAL-ARCHIVE-SPEC.md)：公开发布所需的端到端加密完整归档格式、导入协议和安全测试合同。
- [`schemas/mombaby-archive-v1.schema.json`](./schemas/mombaby-archive-v1.schema.json) · [`entity registry`](./schemas/mombaby-archive-v1-entity-registry.json) · [`SQLite mapping`](./schemas/mombaby-archive-v1-sqlite-mapping.json)：归档 v1 的机器可读格式、27 类实体顺序/引用和 44 表逐字段映射合同。
- [`MVP-SERVER-TECHNICAL-DESIGN.md`](./MVP-SERVER-TECHNICAL-DESIGN.md)：后续密文云、同步、家庭权限和召回资料服务的 P1 架构/安全基线；不是已冻结的 wire protocol，OpenAPI、密码 profile 与 P1 客户端合同另设实施 Gate。

## 当前推荐发布边界

首发基线为 **P0-L 本地 MVP**：无账号、无业务服务端，所有核心记录功能离线可用。ADR-001 与 PRD v0.4 已把私密云空间移到 P1-S；家庭协作和召回监测分别作为 P1-C、P1-R0 独立立项。未取得 Apple 书面解释前，敏感文件请求排除系统 iCloud Backup，公开发布前必须提供可验证的用户主动加密归档恢复路径。Files、Photos 或分享面板产生的副本可能进入 iCloud/第三方，属于用户主动外部边界，不在 App 删除控制内。
