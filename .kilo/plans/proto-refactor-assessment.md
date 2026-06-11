# Proto 重构评估书

## 当前状态

| 项目 | 数量 |
|------|------|
| `src/generated/` 现有 Java 类 | 1,908 |
| `Deobfuscated.proto` 中定义的消息 | 9,111 |
| 手写代码 import 的 proto 类型 | **758** |
| 758 中存在于 Deobfuscated.proto | 611 |
| 758 中**不存在**于 Deobfuscated.proto | **147** |
| 手写代码 import 的混淆名类型 | **0** ✅ |

## 缺失的 147 个消息

这 147 个消息存在于当前 `src/generated/` Java 中，但**不在** `Deobfuscated.proto` 里：

```
AbilityInvokeArgument, AbilityMetaSpecialEnergy, AbilityScalarType,
AddCustomTeamRsp, AskAddFriendNotify, AskAddFriendReq,
AvatarDelNotify, AvatarPropNotify, AvatarSkillChangeNotify,
AvatarSkillDepotChangeNotify, AvatarUnlockTalentNotify, ...

（其中 5 个在 proto-6.5/ 目录有独立 proto 定义，其余 142 个来源不明）
```

## 方案对比

### 方案 A：直接删 + 提取（你的原始想法）
- 删掉 1908 个旧 Java
- 只从 Deobfuscated.proto 提取 611 个可用消息
- **后果**：缺失 147 个消息 → 编译失败 → 无法运行

### 方案 B：提取 + 补充缺口（推荐）
1. 从 Deobfuscated.proto 提取 611 个已翻译消息 → 字段号正确
2. 对缺失的 147 个，**保留其现有 Java 类，不删除**
3. 最终生成目录 = 611 个新生 + 147 个保留 → 758 个足够
- **后果**：611 个消息字段号正确，147 个保留的可能有错号（但不影响功能因为是辅助消息）

### 方案 C：全量对比修正（最安全）
1. 不删任何文件
2. 对比 611 个 Deobfuscated.proto 中的消息 vs 对应生成 Java
3. 只修正字段号不一致的地方
4. 其余文件不动
- **后果**：无编译风险，无功能缺失，字段号逐步修正

## 推荐方案：B + C 混合

1. 运行字段号对比脚本 → 列出所有不一致的消息
2. 对字段号错的消息 → 从 Deobfuscated.proto 提取修正版
3. 对 147 个缺口消息 → 保留旧生成 Java
4. 最终只需替换少量文件

## 风险矩阵

| 风险 | 概率 | 影响 | 缓解 |
|------|:---:|------|------|
| 缺失消息导致编译失败 | 高（方案A） | 无法启动 | 保留缺口消息的旧 Java |
| 新生成类 import 引用旧类不兼容 | 中 | 编译错误 | 保留所有未被替换的旧类 |
| 部分功能缺失（钓鱼等未实现功能） | 低 | 仅客户端体验 | 本来就不实现，无所谓 |
| 混淆类未被清理 | 低 | 无影响 | 不被引用的混淆类不影响运行 |

## 预期收益

| Bug | 修复后 |
|-----|--------|
| 挑战失败 UI 弹窗 | ✅ `DungeonChallengeFinishNotify` 字段号修正 → 6.6 客户端正确解析 |
| 掉落物拾取 | ✅ `SceneGadgetInfo.TrifleGadget` 字段号修正 → 客户端显示拾取 UI |
| 其它字段号错误的包 | ✅ 一并修正 |

## 建议下一步

1. 先跑字段号对比脚本，搞清楚 611 个消息中有几个字段号错了
2. 针对性替换那几个错的（估计不超过 20 个）
3. 147 个缺口消息不动
