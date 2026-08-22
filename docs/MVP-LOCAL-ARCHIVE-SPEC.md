# Mom-Baby P0-L 本地加密归档规范

> **文档版本：** v1.0
>
> **日期：** 2026-08-21
>
> **状态：** P0-L 公开发布实施合同
>
> **适用范围：** iOS MVP，本地单安装、单受信任成人模式
>
> **基线：** [MVP PRD](./MVP-PRD.md) v0.4；受已接受的 [ADR-001](./ADR-001-MVP-SCOPE-AND-DATA-BOUNDARY.md) 强制约束
>
> **关联文档：** [iOS 技术设计](./MVP-IOS-TECHNICAL-DESIGN.md) · [技术架构](./MVP-TECHNICAL-ARCHITECTURE.md)

---

## 1. 目的与发布边界

本规范定义用户主动创建、保存和恢复的单文件加密归档。它解决的是换机、卸载、设备损坏前的主动备份与恢复，不是账号云同步、多人协作或灾备服务。

公开发布必须满足以下二选一：

1. 完整实现本规范并通过第 13 节的发布 Gate；
2. 由一份新的 Accepted ADR 明确取代 ADR-001 的当前归档 Gate，并记录产品、隐私、法务和 Apple 发布负责人的共同批准以及具备同等恢复能力的验收证据。

导出文件可由用户保存到 Files、iCloud Drive、第三方文件提供商、Finder 或分享目标。这些都是 App 沙盒之外的用户控制副本；选择外部目标不等于 App 使用 CloudKit，也不改变“无自建服务端”的结论。App 不承诺外部提供商的保留、删除、同步或访问控制语义。

保存到 Photos 只适用于用户主动保存单张 MomentAsset，不是本规范的归档目标。照片库中的副本可能由 iCloud Photos 同步，删除本地资料不会删除该外部副本。

## 2. 威胁模型

### 2.1 必须防御

- 未取得口令的离线文件读取；
- 归档内容、顺序、长度字段被篡改；
- 帧删除、重复、重排、拼接、截断和跨归档替换；
- 错误口令被误报为有效归档；
- 恶意归档导致路径穿越、任意 SQL、越界分配、整数溢出或无限工作；
- 导出期间业务记录或媒体变化造成数据库与文件不一致；
- App 被杀、设备重启、磁盘写满或文件提供商中断造成“看似成功但不可恢复”的归档。

### 2.2 明确不防御

- 已解锁且被恶意代码控制的设备、越狱内核或运行时内存提取；
- 用户输入口令时的肩窥、系统级键盘记录或主动截屏；
- 弱口令的离线猜测；KDF 只能提高成本，不能补偿低熵；
- 文件名、总字节数、文件系统时间戳和归档存在性等外部元数据泄露；
- 用户把明文导出、照片副本或解锁后的内容交给第三方；
- NAND/SSD 控制器、快照或磨损均衡留下的取证残留。

归档不会证明操作者是某个具体家庭成员。LocalAuthentication 只验证当前设备认可的 owner credential；恢复后仍是“本安装的一名受信任成人”，不能把 Face ID、Touch ID 或设备密码当作人员身份。

## 3. 密钥与口令合同

### 3.1 密钥层次

- 每次导出生成独立的 32 字节 Archive Master Key（AMK）；
- AMK、盐、nonce prefix 与 archive_id 必须来自系统 CSPRNG；
- 口令经 Argon2id v1.3（version 0x13）派生 32 字节 Key Encryption Key（KEK）；
- KEK 只用于 AES-256-GCM 包装 AMK；
- 数据密钥为 HKDF-SHA-256(AMK, salt = core_hash, info = UTF-8 MomBaby/ArchiveData/v1, length = 32)；
- 口令、KEK、AMK 和数据密钥只驻留内存，不写入 Keychain、日志、崩溃字段或归档会话表；退出相关流程后尽力清零缓冲区。

### 3.2 口令规则

- 用户输入先按 Unicode NFC 标准化，再以 UTF-8 编码；
- NFC 前原始 UTF-8 最多 4096 bytes；规范化后接受 12–128 个扩展字素、最多 1024 个 Unicode scalar 且 UTF-8 最多 4096 bytes，导出时要求二次输入一致；任一上限超出都在运行 KDF 前拒绝；
- UI 必须明确说明：没有账号恢复通道，口令遗失后无人能够解密；
- 不提供提示问题、默认口令、设备密码替代或静默降级；
- 错误口令、损坏 envelope 和被篡改 core 对外统一显示“口令错误或归档已损坏”，避免 oracle。

### 3.3 Argon2id 参数策略

新建 v1 归档的最低参数为：

| 参数 | 默认值 | 导入允许范围 |
|---|---:|---:|
| memory | 128 MiB | 64–256 MiB |
| iterations | 3 | 3–10 |
| parallelism | 1 | 1–4 |
| output | 32 bytes | 固定 32 bytes |
| salt | 32 random bytes | 固定 32 bytes |

工程可在最低支持设备上把默认 memory 或 iterations 向上校准到约 0.75–1.5 秒，但不得低于表中最低值；同一已开始导出的参数不得漂移。导入先做整数和范围检查，再运行 KDF。超出上限的参数直接拒绝，不能据攻击者输入申请任意内存或 CPU。

该参数组是 Mom-Baby 的项目 profile，不声称等同于 RFC 9106 的任一推荐配置。公开发布前的独立密码评审必须同时确认 `memory=128 MiB / iterations=3 / parallelism=1` 在最低支持设备上的安全性、时延和内存压力；若评审要求调整，新 writer 默认值、兼容范围、格式说明与 golden vectors 必须一起版本化，reader 不得靠猜测参数。

### 3.4 密码学依赖 Gate

Apple CryptoKit 提供 SHA-256、HKDF 和 AES-GCM；Argon2id 需要经过批准的第三方实现。引入前必须：

- 固定源代码版本与提交哈希，优先源码构建，禁止不透明预编译二进制；
- 核对维护者、许可证、发布签名或校验和、已知漏洞和 transitive dependencies；
- 纳入 lockfile、SBOM、依赖更新流程和隐私清单检查；
- 在所有支持架构运行 Argon2 官方 known-answer tests、越界参数测试及内存压力测试；
- 安全负责人书面批准实现和版本。

第三方依赖未通过 Gate 时，归档能力不得公开发布；不能悄悄改用 PBKDF2、较弱参数或自研密码算法。

## 4. v1 容器格式

所有整数使用网络字节序（big-endian）。文件由 prefix、core、key envelope、认证帧和唯一 completion 帧依次组成。v1 扩展名为 .mombabyarchive。

### 4.1 Prefix

| 字段 | 长度 | 值或约束 |
|---|---:|---|
| magic | 8 | ASCII MBARCH01 |
| format_major | UInt16 | 1 |
| format_minor | UInt16 | 0 |
| core_length | UInt32 | 1–16384 |
| envelope_length | UInt32 | 固定 60 |
| core | core_length | UTF-8 JSON，见 4.2 |
| key envelope | 60 | wrap_nonce 12 + ciphertext 32 + tag 16 |

未知 major 必须拒绝。reader 只接受本地 `featureProfiles` registry 中**精确存在**的 `(format_minor, 已排序 feature_flags 集合, logical_schema_version)` 三元组；v1.0 唯一 profile 是 `(0, [], 1)`。因此 minor 1 即使携带空 flags 也必须拒绝，不能用“空集都在 allowlist”绕过版本协商。

### 4.2 Public core

core 由 exporter 按 RFC 8785 JCS 写成无 BOM、无前后空白的 UTF-8 JSON。Importer 先按规范性 JSON Schema 校验，再以文件中的原始 core bytes 计算：

core_hash = SHA-256(core_bytes)

允许且必须出现的键只有：

- archive_id：小写 UUID；
- created_at_ms：正整数；
- logical_schema_version：正整数；
- kdf：name = argon2id、version、memory_kib、iterations、parallelism、salt_base64；
- data_cipher：name = aes-256-gcm、frame_plaintext_max = 4194304、nonce_prefix_base64；
- feature_flags：已排序且无重复的字符串数组。v1.0 registry 为空，因此 writer 必须写 `[]`，reader 必须拒绝任何非空值；未来 flag 必须随 format minor、schema 和 golden vectors 一起发布。

core 不得包含姓名、生日、照片、业务 ID、设备名或路径。解析器拒绝未知键、重复键、非整数数字、非法 Base64、非规范 UUID、NaN、Infinity、过深 JSON 和越界参数。

### 4.3 AMK envelope

wrap_nonce 为 12 个随机字节。ciphertext 和 tag 是：

AES-256-GCM-Seal(
  key = KEK,
  nonce = wrap_nonce,
  plaintext = AMK,
  AAD = UTF-8 MomBaby/ArchiveKey/v1 || core_hash
)

同一 KEK 下不得复用 wrap_nonce。修改 core、KDF 参数或 envelope 必须导致打开失败。

### 4.4 认证帧

每帧固定头如下，随后是 ciphertext 和 16 字节 GCM tag：

| 字段 | 长度 | 约束 |
|---|---:|---|
| type | UInt8 | 1 manifest、2 records、3 media、255 completion |
| flags | UInt8 | v1 必须为 0 |
| reserved | UInt16 | 必须为 0 |
| sequence | UInt64 | 从 0 开始严格连续 |
| plaintext_length | UInt32 | 0–4194304 |
| ciphertext_length | UInt32 | 必须等于 plaintext_length |

nonce = nonce_prefix（4 bytes）|| sequence（8-byte big-endian）。

frame_aad = UTF-8 MomBaby/ArchiveFrame/v1 || core_hash || 完整的 20-byte frame header。

帧使用数据密钥 AES-256-GCM 加密。Importer 必须在把任何明文交给业务解析器前验证 tag；sequence 重复、跳号、回退、溢出、未知 type/flags 或长度不一致均立即失败。

一个 archive_id 对应一次随机 AMK 和 nonce_prefix。任何 frame 可能已部分发出或完成状态不确定时，整个 cryptographic emission 永久废弃；新 emission 必须生成新的 archive_id/core/AMK/nonce prefix 并从 sequence 0 重建。绝不截断后以旧 key 重用 sequence，也不以新 key 接着旧文件写；只有已经带唯一 completion 且从头完整验证过的文件可以继续做纯字节复制/外部 handoff 重试。

### 4.5 Payload 与 completion

[`schemas/mombaby-archive-v1.schema.json`](./schemas/mombaby-archive-v1.schema.json) 是 core、manifest、record envelope/各 entity payload、media header 与 completion 的规范性键/类型/范围合同；[`entity registry`](./schemas/mombaby-archive-v1-entity-registry.json) 固定 kind 顺序、对象 ID、引用和允许的 SCC；[`SQLite mapping`](./schemas/mombaby-archive-v1-sqlite-mapping.json) 对附录 A 的全部表/字段做导出、重映射、重算、manifest 投影或排除分类。CI 从 `PRAGMA table_info` 对账，任何未分类表/字段立即失败。三个文件共同组成 schema bundle；所有 object 都是 `additionalProperties: false`，所有必填键均列入 `required`。正文、DDL 和机器合同不一致时停止 writer/reader 发布并先修订 ADR、规范、schema 与 vectors，不能让 decoder 选择“尽量读取”。编码规则固定为：

Schema 中的 `x-maxUtf8Bytes`、`x-requiresCalendarValidation`、`x-requiresIanaTimeZoneValidation`、`x-requireCanonicalBase64`、`x-decodedByteLength`、`x-maxPixels` 与 `x-chunkDataMaxBytes` 是项目语义注解。CI 使用 strict JSON Schema validator 时必须显式注册这些关键字；若 schema 结构阶段配置为忽略未知注解，则同一测试流程仍必须运行下面定义的 strict semantic verifier，不能把 `strict=false` 当作跳过这些限制。

- manifest、每条 record、media header 和 completion 分别使用 RFC 8785 JCS；不做 BOM、Unicode 正规化或 locale 转换，用户字符串按已验证的 Unicode scalar 原样往返；
- manifest 可以跨多个相邻 type 1 帧，拼接后恰好是一个 JCS object，无换行，且必须位于任何 records/media 帧之前；
- records 是 UTF-8 JSON Lines：每条为一个 JCS record object 加单个 LF (`0x0A`)，禁止 CRLF/空行；一条记录不得跨帧，record 帧非空且必须以 LF 结束；同一 `entity_kind` 按 `object_id` UTF-8 字节序，kind 再按 schema registry 顺序输出；
- record 顶层键恰为 `entity_kind/entity_schema_version/object_id/payload`；kind/version 必须命中 schema 的 one-of 分支，未知 kind、version、键或 enum 整体拒绝；
- 每个 media frame 恰含一个 chunk：`UInt16 header_length + JCS header + chunk bytes`。header 键恰为 `asset_id/variant/chunk_index/chunk_count/chunk_plaintext_length`；真实 chunk length 仍必须从已认证的 frame plaintext length 减去 UInt16 与实际 header bytes 独立得出，并与 `chunk_plaintext_length` 完全相等，不能按归档自报值分配。相同 asset/variant 的 chunk 连续、不与其他媒体交错，index 从 0 到 count-1。`media_chunk_data_max` 固定为 4,000,000 bytes，非最后块必须恰为该长度，最后块为剩余的 1...4,000,000 bytes，单媒体最多 14 块；frame plaintext length、manifest range/count/bytes/SHA-256 必须全部一致；
- 帧顺序只允许一个或多个 manifest → 零个或多个 records → 零个或多个 media → 唯一 completion；单帧明文最大 4 MiB，实现必须流式加解密，不把整个归档、manifest 或全部照片载入内存；
- 最后一帧必须是唯一 type 255 completion，之后不允许任何字节。

manifest 顶层键集合**恰为** `manifest_schema_version/archive_id/logical_schema_version/schema_bundle_sha256/record_encoding/record_count/media_count/media_payload_byte_count/record_sets/media_items`。`record_encoding` 固定为 `jcs-rfc8785-jsonl-lf-v1`；`record_sets` 必须把 registry 的 27 个 kind 全部且按顺序列出，即使 count 为 0 也不能省略。每项恰含 `entity_kind/entity_schema_version/count/plaintext_byte_length/plaintext_sha256/first_data_frame_index/data_frame_count`；空集合的 byte length/count 为 0、hash 为 SHA-256(empty)、first index 为 null。`first_data_frame_index` 是忽略 manifest 帧后，从首个 records/media data frame 起算的零基 index，避免 manifest 长度依赖自身帧数。

每个 `media_items` 项恰含 `asset_id/purpose/variant/mime_type/width_px/height_px/byte_size/sha256/chunk_count/first_data_frame_index`，按 `(asset_id, variant)` 升序；`moment→display`、`avatar→avatar`、所有 formula/bottle evidence purpose→`evidence`，v1 不允许 thumbnail/original。计数、范围和 hash 的跨字段关系由严格 semantic verifier 再检查，不能只依赖 JSON Schema。

completion 的键集合**恰为** `completion_schema_version/archive_id/logical_schema_version/schema_bundle_sha256/total_frame_count/manifest_frame_count/record_frame_count/media_frame_count/record_count/media_count/manifest_plaintext_byte_length/manifest_plaintext_sha256/records_plaintext_byte_length/records_plaintext_sha256/media_payload_byte_count/pre_completion_file_sha256`。`total_frame_count = manifest_frame_count + record_frame_count + media_frame_count + 1` 且 `completion.sequence = total_frame_count - 1`；`pre_completion_file_sha256` 覆盖文件 `[offset 0, completion frame header offset)` 的原始 bytes，不含 completion header。缺失、额外、重复或任一 count/hash/range 不匹配时，文件无效，UI 不得显示“导出成功”。

`manifest_plaintext_*` 覆盖按 sequence 拼接的全部 type 1 plaintext；`records_plaintext_*` 覆盖按 sequence 拼接的全部 type 2 plaintext（包括每条 JSONL 的 LF）；`media_payload_byte_count` 只累计原始 chunk bytes，不含 UInt16 或 media header。record set 的 data-frame ranges 必须按 registry 顺序形成从 0 开始、无重叠/无空洞的 records 区间；随后 media item ranges按 manifest 顺序连续覆盖所有 media 帧。frame type、range、逐 kind/per-media hash、manifest 总数和 completion 总数必须从流中独立重算并完全相等；core、manifest、completion 的 archive ID/logical version 也必须一致。

### 4.6 Schema bundle identity

`schema_bundle_sha256` 使用固定 domain `MomBaby/ArchiveSchemaBundle/v1\0`，随后按以下逻辑名顺序拼接三个本地受信任 JSON 的 JCS bytes：`schema.json`、`entity-registry.json`、`sqlite-mapping.json`。每项编码为 `UInt16BE(name_utf8_length) || name_utf8 || UInt64BE(jcs_byte_length) || jcs_bytes`，最后对完整字节串取 SHA-256。App 的 writer/reader 只使用随二进制发布并通过签名/构建校验的 bundle，不解析归档或远程地址提供的 schema。manifest 与 completion 的 bundle hash 必须相同并命中本 App 支持表；未知 hash 即使 `logical_schema_version=1` 也拒绝，避免同版本合同漂移。

## 5. 逻辑数据格式与 allowlist

归档是逻辑导出，不包含 SQLite 文件、WAL、SHM、SQL 文本、任意表名、绝对路径、安全作用域 bookmark 或 Keychain 数据。

v1 可导出的实体 allowlist 恰为 registry 中以下 27 种：

1. `growth_standard_version`、`baby_profile`、`lactating_profile`、`consent_record`、`module_preference`；
2. `timer_session`、`timer_channel`、`timer_segment`、`care_event`、`feeding_detail`、`diaper_detail`、`nursing_side_detail`、`pumping_record`、`growth_record`；
3. `formula_product`、`formula_product_version`、`formula_container`、`formula_container_version`、`bottle_item`、`bottle_identity_version`；
4. `media_asset`、`moment`、`moment_asset`、`formula_evidence`、`bottle_evidence`、`formula_use`、`bottle_use`。

所有 nullable payload 键仍必须出现并显式写 `null`。顶层 `object_id` 承载实体 ID；复合主键实体按 registry 的 UUIDv5 算法生成。vault/actor/device ID、`current_consent_id`、local revision、软删除标记、命令 ID、缓存、路径和保护状态不进入 payload：恢复时分别重映射、创建当前 consent、重置或重算。历史 consent 仅用于展示证据，不获得当前授权。

明确排除：

- device_installation、restore sentinel、LocalAuthentication 状态和设备密钥；
- `app_setting`（当前仅为设备/App 锁与说明确认等设备态；未来业务设置需以逐 key enum/schema 新增格式版本，禁止导出任意 JSON）；
- operation ledger、active resource lock、worker claim、诊断日志；
- media import、purge、migration、maintenance、archive job/journal；
- sandbox 相对路径、临时文件、可重建 thumbnail 与缓存；
- 任何未来新增但尚未加入格式 allowlist 的表或字段。

manifest 给出每种 entity kind 的 schema version、count、记录帧范围和明文 SHA-256；每个媒体条目给出 opaque ID、purpose、variant、MIME allowlist 值、宽高、字节数、SHA-256 和媒体帧范围。记录引用必须使用 UUID，不允许由归档指定文件名或落盘路径。

记录编码规则必须固定在版本化 encoder/decoder 中：UTF-8、无重复键、整数毫秒时间、ISO 8601 date-only、显式 null 语义、字符串长度上限与确定性键序。不得直接把 Swift Codable 当前内存结构视为永久格式。

快照中的非终态 timer 不跨设备延续。Exporter 在逻辑层把 `ready/running/paused/waiting_for_side/finalizing` 归一为 `abandoned`：以快照时已持久化的 `last_activity_at_ms`（不得早于 segment start）闭合开放 segment，channel 变为 `abandoned`，session 记录 `ended_at_ms` 与 `clock_verification_state=wall_only_after_process_loss`，不生成 care/pumping final record，也不导出 active lock。原设备数据库中的活动 session 不因此改变。Importer 只安装这一终态历史；“重新开始”从当前时间创建全新 session，不能把跨设备 wall-clock 区间接到旧 segment。

## 6. 一致性快照与导出流程

### 6.1 快照 pin

导出由单个 ArchiveExportCoordinator 串行执行：

1. 让用户选择 `verified Files` 或 `local handoff` 输出模式，预检数据库健康、源/目标空间、格式上限和无 migration/restore/purge 冲突；
2. 通过唯一 DataActor 开启 BEGIN IMMEDIATE，记录 snapshot_data_revision 并建立 archive_export_session；
3. 在该事务的同一 SQLite snapshot 内，把 allowlist 业务记录（含上述 timer 归一化）物化成受文件保护的逻辑 staging stream；
4. 在提交该事务前为所有需导出的媒体建立 archive_media_pin，固定 asset_id、variant 与 expected_sha256；物化或 pin 失败必须回滚并删除 staging；
5. 提交后释放数据库锁；后续业务编辑产生新 revision，不改变本次快照；
6. 逐个打开 pinned replica，验证文件仍在受保护根目录、状态为 ready/protected、大小和 SHA-256 一致，再把 records/media 流式写入所选输出 sink；
7. 所有帧、completion、sink flush/fsync 和适用的目标回读验证成功后，才进入对应成功状态。

被 pin 的 replica 不得被删除、覆盖、移动、垃圾回收或重生成。若文件缺失或 hash 改变，本次导出失败；不能跳过它后继续宣称完整。结束、取消或失败清理 staging 后才释放 pins。

启动维护把 staging 目录与已提交的 archive_export_session 对账：没有会话的目录先移入 quarantine，下一次扫描仍无引用且超过 24 小时才删除；存在未终态会话的目录必须进入恢复状态机，不能被通用 orphan scanner 抢先处理。

### 6.2 空间与文件保护

v1 使用 UInt64 长度、sequence、offset 和 checked arithmetic，格式上限为 8 TiB；媒体进入 App 前维护 `estimated_archive_bytes`，若新增内容连同 frame/manifest/encryption 最坏开销会超过该上限则在导入前拒绝并解释“当前格式无法完整归档”，不能先接受成一个永远无法完整恢复的 vault。该上限必须显著高于当前支持设备容量；未来硬件接近上限前通过新 format major/multi-volume ADR 扩展。

默认 `verified Files` 模式先取得用户选择且可创建、写入、flush、重新打开读取和最终移动的 Files/File Provider URL，在目标目录以随机临时名直接流式写归档，因此本机不需要第二份完整媒体。开始前本机需要 `staging logical bytes + 数据库/manifest 工作集 + 20% margin` 且保留 256 MiB 系统余量，目标需要 `estimated archive bytes + 20% margin`；provider 无法报告容量时明确提示并把任一 ENOSPC 纳入可恢复失败路径。

`local handoff` 模式先在 App 受保护 staging 生成完整文件，供 Share Sheet 或 Finder 交接；它额外要求本机具有 `estimated archive bytes` 空间。容量不足时隐藏该模式并引导使用 verified Files，不能因此阻断用户创建完整归档。

物化记录、本机 handoff partial 和恢复 staging 位于 `Application Support/MomBaby/ArchiveStaging/<session-id>`，使用 `NSFileProtectionComplete`、请求排除 iCloud/系统备份并读回验证属性。目录或属性创建失败时 fail closed。verified Files 的外部临时文件不受 App 文件保护属性承诺，但内容从 prefix 后均为认证密文；UI 必须说明中断可能在用户所选位置留下无效 partial，并提供在仍有访问权时删除它的操作。

### 6.3 原子与可恢复输出

- 每次 cryptographic emission 生成全新的 archive_id、salt、AMK、wrap nonce、nonce prefix 和 core，sequence 从 0 开始；
- 每完成一帧并 flush 后，在同一数据库事务 CAS 持久化 `emission_epoch/last_complete_sequence/checkpoint_byte_offset/checkpoint_prefix_sha256`；checkpoint 只用于审计、进度与崩溃判定，不作为可恢复 SHA-256 内部状态；
- 只要写 frame header/ciphertext/tag/completion 的系统调用出现部分写入、结果不确定、I/O error、进程终止或 claim 过期，就**永久放弃该 emission**。不得截尾后用同一 AMK/nonce prefix 重用未完成 sequence；接管者保留已物化 snapshot 与仍有效 pins，要求用户重新输入口令，递增 emission_epoch，以全新密钥/core 从 sequence 0 重建；
- snapshot materialization、pins 或 pinned hash 不完整时连 snapshot 一并作废，从新数据 revision 开始；
- verified Files 在用户目标目录写随机 `.partial`，完成后关闭并重新打开，从头验证总长度、所有 tag/completion 和整档 SHA-256；provider 支持同目录原子 rename 时再改最终名，不支持时以完整 completion 作为有效标志并用协调 move，任何无法回读的 provider 不属于 verified Files；
- local handoff 只在 App staging 内的完整文件通过同样自检后进入 `archive_validated_locally`。Share Sheet/Finder 返回只表示系统 handoff 完成，App 无法回读接收方副本，因此 UI/收据必须区分 `handoff_completed` 与 `external_copy_verified`，不得把前者写成“目标备份已验证”；
- 外部传输失败时，完整且仍在 24 小时 TTL 内的本地 staging 可以换目标重试；verified Files 的无效 partial 在 App 仍持有 URL 权限时清理，否则明确提示用户删除；
- 成功的本地 staging 最长保留 24 小时，失败/取消最长 1 小时；到期协调清理，不静默覆盖用户目标文件。

导出状态机固定为 `preparing → materializing → awaiting_destination → writing → validating_output → external_copy_verified`，local handoff 分支为 `writing → archive_validated_locally → handing_off → handoff_completed`；任一步可进入 `failed/cancelled`，不确定 emission 回到 `awaiting_destination` 前必须递增 emission_epoch 并废弃旧 partial。每次 claim 在同一事务写随机 claim_id、令 operation_epoch += 1，并设置 heartbeat_at_ms 与 claim_expires_at_ms = now + 120 秒；续租、状态和 checkpoint 都 CAS 当前 `(id, claim_id, operation_epoch, emission_epoch)`。过期、时钟倒拨或进程重启后只有新 operation epoch 接管，旧 worker 的 frame/completion/state commit 均失败。

## 7. 导入、跨版本与原子安装

### 7.1 前置条件

P0-L 只允许导入到尚无业务数据的新安装或空 vault。非空 vault 不合并，避免 ID、版本、计时与删除语义冲突。导入入口先完成专用的恢复 onboarding：确认“单受信任成人”边界并签署当前版本 consent，但在验证成功前不创建宝宝等业务事实；归档中的历史 consent 不替代本次同意。

### 7.2 恶意输入资源上限

在解密/分配前强制以下上限：

| 项目 | 上限 |
|---|---:|
| 整个文件 | 8 TiB；所有 length/offset 使用 UInt64/checked arithmetic，且仍受目标设备容量约束 |
| core | 16 KiB |
| 单帧明文/密文 | 4 MiB |
| 帧数 | 2,100,000 |
| manifest 明文 | 512 MiB；必须流式解析，禁止整块分配 |
| 逻辑记录数 | 10,000,000 |
| 媒体条目数 | 1,000,000 |
| 单媒体 | 50 MiB |
| JSON 嵌套 | 32 |
| 普通字符串 | 64 KiB；更小的领域上限优先 |

所有长度相加、offset、chunk count、实体 count 使用 checked arithmetic。Importer 在 KDF 前读取真实文件长度，在解密前建立按当前可用空间、预计数据库/WAL/媒体输出和 20% margin 计算的本次 restore budget；无法容纳时先失败，不靠逐步写满磁盘。超过任一上限、压缩 payload、未知 MIME、未知 entity kind、非法/不存在的日历日期、未在 schema registry 声明的引用环、悬空引用、重复 ID、hash 不符、额外尾部或不符合 iOS DDL/严格 repository verifier 的数据均拒绝整个导入。合法循环只限 registry 显式声明的 SCC：`baby_profile↔media_asset(avatar)`、三组 `subject↔current immutable version`、`timer_session↔care_event(final/source)`、`timer_session↔pumping_record(final/session)`；Importer 先完整构图与校验，再在 deferred transaction 按固定 SCC 顺序写入。`moment.derived_from_moment_id` 必须是 DAG；历史 consent 只单向引用 profile，不属于 SCC。不得把“允许合法 SCC”扩展成接受任意环。v1 不支持归档内压缩，因此不存在按攻击者声明的解压尺寸分配。

媒体还必须复用 iOS 技术设计的安全解码限制：每边不超过 20,000 px、总像素不超过 80 MP、静态单帧、累计并发解码中间态不超过 100 MiB，并 downsample 后写 display/thumbnail。不能只相信 MIME、扩展名或 manifest 尺寸。

### 7.3 版本策略

- format major 控制容器和密码学结构；v1 reader 永久保留到产品正式终止导入能力；
- logical_schema_version 控制 allowlist 逻辑实体；旧版本必须经纯逻辑、逐版本 migrator 导入到当前 DDL；
- migrator 只接收强类型对象，不能执行归档提供的 SQL、表名、路径或动态 class；
- 比当前 App 更新的 logical schema fail closed，提示升级 App；可展示不含业务明文的版本信息；
- 每个已公开 writer 版本都必须保留 golden archive 与 backward-import 测试；删除 reader 需要独立产品、数据恢复和法务决策。

### 7.4 Staged restore

导入在全新受保护 staging vault 内完成：

1. 读取 prefix/core 并执行廉价上限检查；
2. 用户输入口令，解开 AMK；顺序验证全部帧、completion 和 hash；
3. 验证 manifest、引用图、业务约束与媒体安全边界；
4. 创建当前版本空数据库，经 allowlist importer 和版本 migrator 写入，不安装外来 SQLite。允许 SCC 只能走 registry 固定装载计划：consent-before-profile；`baby_profile.avatar_asset_id` 先以 null 插入、媒体验证落库后再回填；product/container/bottle version-before-subject；timer 的 care/pumping cycle 按下一句 staging。为满足终态子图不可追加约束，Importer 在同一个 deferred transaction 中按 manifest 稳定顺序**逐个 session**执行：把归档的 finished/abandoned timer 先以 `finalizing`、空 final pointer 的临时形态插入，立即建齐该 session 的 closed channel/segment 与 care/pumping/nursing fact，通过单 session verifier 后立即写回归档终态与 final pointer，再处理下一个 session；禁止批量留下两个同 baby/profile/type 的 `finalizing` session，否则会与 active-slot 唯一约束冲突。detached nursing 的 DDL 仅为该 staging 形态允许 `finalizing + baby_id=null + detached_at!=null`，正式 verifier 不允许它在提交后残留；
5. 生成新的 local_vault、local_actor、device_installation、restore sentinel 与当前 consent；保留业务实体 ID，但把 vault/actor 根引用重映射到本安装；
6. 以内容 hash 生成新的媒体相对路径，写临时名、fsync、rename，并核对数据库引用；
7. 确认所有归档内非终态 timer 已按 §5 归一为 `abandoned`、没有 active lock/final record；恢复页只允许查看中断事实或从当前时间创建新 session，不允许延长旧 segment；
8. 运行 foreign_key_check、integrity_check、领域 verifier，并按 manifest 对账 27 类已导入逻辑记录的 `object_id`、payload、逐类 count/hash 和媒体 checksum；恢复生成的 current consent 及 vault/actor/device 安装态按预期增量另行断言，不计入归档记录等量比较，mapping 标为重映射/重算/排除的字段也不做源库物理值等同断言；
9. 对数据库执行最终 checkpoint/close，fsync 全部媒体、数据库、COMPLETE marker 和 staging vault 目录，确认没有存活 reader/句柄；
10. 把 `ArchiveStaging/<session>/vault` 以同卷原子 rename 安装到唯一 `Vaults/<new-vault-id>`，随后 fsync `ArchiveStaging` 与 `Vaults` 两个父目录；目标预先存在、跨卷或无法证明 rename 原子性时 fail closed；
11. 先把 CurrentVault 原子替换为 `unavailable:<restore-operation-id>` 并 fsync `MomBaby` 父目录，再在已安装 vault 完整复验后原子替换为 `active:<new-vault-id>` 并再次 fsync；只有 active pointer durable 后才清理旧空 vault和 journal。

受保护且请求排除备份的 `Application Support/MomBaby/RestoreJournals/<session-id>.json` 是唯一安装 journal，采用临时文件 + 原子 replace + 父目录 fsync。phase 固定为 `validating → staging_complete → moving_to_vaults → vault_installed → pointer_unavailable → pointer_committed → cleanup_complete`，只含 session/operation ID、旧/新 vault 相对目录、expected COMPLETE/schema/media hashes 和时间，不含密钥或业务内容。启动恢复规则固定为：

- `staging_complete` 之前删除/隔离不完整 staging，原 vault 不变；
- rename 后若 vault 完整而 pointer 尚未提交，保持 unavailable、复验并继续提交；若不完整则保持 unavailable 并进入只读恢复页；
- pointer_committed 后只接受其指向且 COMPLETE/hash 全部匹配的新 vault，关闭残留句柄后完成清理；
- journal、pointer 和目录互相矛盾时绝不按修改时间猜测，也不同时开放两个可写 vault。

磁盘写满、进程被杀、设备重启、文件提供商失联、错误口令或任一验证失败，都不得修改当前 vault。失败 staging 可重试或清理；密钥丢失后必须重新输入口令。

## 8. 外部副本、删除与隐私文案

导出确认页必须显示：

- 归档包含婴儿、哺乳、喂养、成长和照片等敏感数据；
- 文件由用户口令加密，口令遗失无法恢复；
- 保存到 iCloud Drive/第三方 Files/分享目标后，副本受该提供商和账号控制；
- 从 App 删除资料或卸载 App 不会删除外部归档、Photos 副本或对方已接收的分享；
- App 无法枚举或远程撤销这些副本。

整库删除应先使本地 vault 不可访问，并按 iOS 技术设计执行 WAL checkpoint、secure_delete、VACUUM/临时文件和目录清理；它不承诺闪存取证擦除。归档删除只作用于 App 仍有权限访问且用户明确选择的那个 URL；不得搜索或批量删除 Files/iCloud 中的同名文件。

日志、analytics 和崩溃报告不得记录口令、salt、nonce、AMK、业务 ID、原始文件名、安全作用域 URL、照片 hash 或解密失败的具体认证阶段。

## 9. 错误与用户可恢复性

稳定错误类别：

- unsupportedVersion：升级 App，不尝试部分导入；
- passwordOrCorrupt：重新输入口令或换一份归档；
- resourceLimit：说明归档超过本版本安全上限；
- integrityFailed：拒绝整体导入，不保留部分业务数据；
- insufficientSpace：保留原 vault，提示释放空间；
- destinationUnavailable：local handoff 保留本地完整 staging；verified Files 保留 snapshot/pins、废弃旧 emission，在 TTL 内重选目标并用新密钥从 sequence 0 重建；
- interrupted：导入按 install journal 回滚/继续原子安装；导出可复用仍完整的逻辑 snapshot/pins，但必须永久废弃不确定的 cryptographic emission，重新输入口令并以全新 key/core 从 sequence 0 重建，绝不从“最后有效帧”续写；
- dependencyUnavailable：密码学初始化/self-test 失败，禁用导入导出。

任何错误都不能提供“忽略并继续”“只恢复能读的部分”或绕过认证的选项。产品可另行开发只读诊断工具，但不属于 P0-L，且不能将未认证数据安装到正式 vault。

## 10. 测试向量

仓库必须提交去标识化、非真实用户数据的确定性向量。固定 RNG、口令、core bytes 和业务 fixture 后至少包含：

1. Argon2id v1.3 KEK known-answer；
2. AMK envelope 的 nonce、AAD、ciphertext 与 tag；
3. 单个 manifest/records/media/completion frame 的完整 bytes；
4. 多帧媒体和 sequence 边界；
5. 完整小型 golden archive 及预期 manifest/归档 SHA-256；
6. 错误口令、core 单 bit、frame header/cipher/tag 单 bit；
7. 帧删除、重复、重排、跨归档拼接、截断和 completion 后附加字节；
8. KDF/长度/count/JSON 深度整数边界与 checked-overflow；
9. 路径穿越字符串、未知 entity/schema/MIME、重复 ID、悬空和循环引用；
10. core/manifest/record/payload/media header/completion 每层的未知键、重复键、BOM、CRLF、空行、缺尾 LF、跨帧行、同帧混 kind；
11. media chunk 重排/交错/短中间块/错误 count，及 `minor=1 + feature_flags=[]`；
12. 删除宝宝后仅保留成人 nursing/pumping 图（含 detached finished session、channel、segment、detail）的 golden round-trip；删除成人后仅保留宝宝 care snapshot，source timer 必须为 null；
13. 历史 consent 不成为当前授权，App 锁、设备 ID、路径、worker/job 数据不进入恢复结果；
14. 旧 logical schema 到当前 schema 的 golden import。

向量生成器仅用于测试，不能把固定 RNG 编入生产 target。iOS 真机测试必须覆盖最低支持设备的峰值内存、KDF 时延和跨 4 GiB 的 UInt64 流式 offset；8 TiB/最大 frame-count 边界使用 checked-arithmetic 单元测试、稀疏文件或受控虚拟 sink，CI 可使用较小但结构等价的 fault-injection fixtures。

## 11. 故障注入矩阵

下列边界逐一注入 kill、ENOSPC 或 I/O error：

- 记录物化前/后、媒体 pin 事务前/后；
- 每种 frame header、ciphertext、tag、checkpoint 和 completion 写入期间；
- 任意不完整/结果不确定 frame 后重启，证明旧 archive_id/AMK/nonce prefix 永不再次使用，旧 worker completion 被 epoch CAS 拒绝；
- fsync 前后；
- 文件提供商临时复制、校验和 rename 前后；
- 归档解密、逻辑 migrator、数据库 commit、媒体 rename、COMPLETE marker、staging→Vaults rename、两个父目录 fsync 和 CurrentVault unavailable/active 指针切换前后；
- cleanup 释放 pins 与删除 staging 前后。

每个用例都必须证明：旧 vault 仍可打开，或新 vault 已完整提交；不会出现两个可写 current vault、悬空 pin、把 partial 当成功、静默遗漏媒体或绕过重新输入口令。

## 12. 可访问性与文案验收

- 口令、确认、显示/隐藏、进度、取消、失败和成功状态具有 VoiceOver label/hint；
- Dynamic Type 到无障碍尺寸不遮挡口令遗失和外部副本警告；
- KDF、扫描和复制期间提供可读进度或“不确定时长”状态，不阻塞主线程；
- 颜色不是唯一错误信号；错误焦点移动到可操作恢复入口；
- 导出/导入中断后的恢复页清楚区分“归档仍在 App 内”“已复制到外部”“尚未验证”；
- zh-Hans 固定文案通过隐私、法务和可用性验收，不使用“绝对安全”“永久删除”“云端不会保存”等保证。

## 13. Definition of Done 与发布 Gate

只有全部满足才可启用公开导入/导出：

- 格式 v1 byte contract、[`schemas/mombaby-archive-v1.schema.json`](./schemas/mombaby-archive-v1.schema.json)、entity registry 与所有上限已冻结并有代码常量，schema 自身通过 meta-schema 和正反 fixtures；
- 独立实现或独立测试路径可以读取 golden archive，全部密码学向量通过；
- 第三方 Argon2id 依赖完成安全/许可证/SBOM/隐私清单 Gate；
- 真机性能达到：默认 KDF 在最低支持设备目标区间，导出/导入流式峰值内存不超过批准预算；
- 所有篡改、恶意输入、路径/schema allowlist 与资源耗尽测试通过；
- 快照 revision、media pins、hash 对账、非终态 timer 导出归一为 abandoned 且恢复后新开 session 的测试通过；
- 全部故障注入点证明原子性与可恢复清理，且没有密钥或业务数据进入日志；
- 从每个曾公开 writer/logical schema 的 golden archive 恢复并通过当前 DDL verifier；
- Files 本地、iCloud Drive、至少一个第三方 provider 的 direct verified 成功/中断/回读测试通过；Finder/分享路径分别验证 `archive_validated_locally`、`handoff_completed` 文案不冒充 `external_copy_verified`；
- VoiceOver、Dynamic Type、低空间、后台/前台、设备重启和文件保护真机测试通过；
- 导出前/成功/删除资料/恢复前的隐私文案经产品、隐私与法务签字；
- T0 工程 Gate 与 T6 发布 Gate 将本清单作为阻断项，证据链接可追溯到 CI run、测试 ID、依赖审查与签字记录。

任一项缺失时，开发版只能隐藏在内部 feature flag 后；不得向公开用户展示一个无法被当前 App 完整验证和恢复的“备份成功”入口。

## 14. 规范性参考

- [RFC 9106：Argon2 Memory-Hard Function](https://www.rfc-editor.org/rfc/rfc9106)
- [NIST SP 800-38D：GCM/GMAC](https://csrc.nist.gov/pubs/sp/800/38/d/final)
- [Apple CryptoKit](https://developer.apple.com/documentation/cryptokit)
