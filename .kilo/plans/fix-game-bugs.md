# Bug 修复计划：LunaGC 游戏服务器 (Genshin 6.6)

## 概述
LunaGC Grasscutter 原神私服报告了四个 bug：
1. 进入副本后立即弹出挑战失败 UI（"退出挑战"按钮），副本无法游玩；切换场景时也偶现相同界面
2. 部分副本（如 dungeonId=1）无法进入，即使用指令也进不去；`SceneMeta.of()` 返回 null 导致 NPE
3. 怪物掉落物不掉落
4. 部分怪物（Boss）不自然生成

---

## Bug 1：副本内 / 场景切换时弹出"挑战失败"UI（退出挑战）

### 根因分析
**问题 A：场景切换时退出挑战 UI**

当玩家通过传送点切换场景时，旧场景 `Scene.removePlayer()`（`Scene.java:229`）检测到该场景有活跃的 `WorldChallenge`，发送 `DungeonChallengeFinishNotify(isSuccess=false)`。客户端收到后显示挑战失败界面。

**问题 B：进入副本后立即弹出退出挑战 UI（更严重）**

副本的 Lua 脚本在初始化时调用多个函数，这些函数有缺陷导致脚本执行异常，最终触发 `CauseDungeonFail()` → `failDungeon()` → `DungeonSettleNotify`，客户端显示副本失败界面。

具体缺陷链：
1. **`RefreshGroup` 忽略关键参数**（`ScriptLib.java:960-972`）：
   - Lua 脚本传入 `refresh_level_revise` 和 `exclude_prev` 参数
   - Java 实现仅读取 `group_id` 和 `suite`，其余参数被丢弃
   - 副本初始化依赖这些参数正确设置 group suite，参数丢失导致 group 状态异常
   
2. **`GetServerTime` 产生不必要的警告**（`ScriptLib.java:783-787`）：
   - 功能本身正常工作（返回当前时间）
   - 但 `logger.warn` 产生大量噪音日志，可能掩盖真正的错误

3. **缺失 Lua 脚本文件 + NPE**（见 Bug 2 详细分析）：
   - 部分 dungeon 场景的 `.lua` 脚本文件缺失
   - `DungeonData.getStartPosition()` 调用 `SceneMeta.of(sceneId).config` 时空指针异常
   - 异常导致 dungeon 初始化中断，触发 `CauseDungeonFail()`

4. **`removePlayer()` 未清理挑战状态**（`Scene.java:229-231`）：
   - 仅发送通知包，未调用 `challenge.fail()` 清理
   - 挑战状态残留影响后续操作

### 修复方案
1. **修复 `RefreshGroup` 实现**（`ScriptLib.java:960-972`）：
   - 读取 `refresh_level_revise` 参数并传递给 `SceneScriptManager.refreshGroup()`
   - 读取 `exclude_prev` 参数并使用（当前 `refreshGroup` 硬编码 `excludePrev=false`）
2. **降级 `GetServerTime` 日志级别**：将 `logger.warn` 改为 `logger.debug`
3. **修复 `DungeonData.getStartPosition()` / `getStartRotation()` NPE**（兜底）：
   - 当 `SceneMeta.of(sceneId)` 返回 null 时，返回默认位置（如 `GameConstants.START_POSITION`）而不是 NPE
4. **在 `World.transferPlayerToScene()` 调用 `removePlayer` 前清理挑战**：
   - 检测 `oldScene.getChallenge().inProgress()` → 调用 `challenge.fail()` 正确结束
5. **`removePlayer()` 改为防御性代码**：如果 challenge 已在外部清理则跳过

### 需修改的文件
- `src/main/java/emu/grasscutter/scripts/ScriptLib.java` — 修复 `RefreshGroup` 参数传递、降级 `GetServerTime` 日志
- `src/main/java/emu/grasscutter/data/excels/dungeon/DungeonData.java` — 修复 NPE，添加默认位置回退
- `src/main/java/emu/grasscutter/game/world/World.java` — 场景切换前清理挑战
- `src/main/java/emu/grasscutter/game/world/Scene.java` — `removePlayer()` 防御性改进

---

## Bug 2：部分副本无法进入（指令也进不去 + NPE 崩溃）

### 根因分析
1. **`EnterDungeonCommand` 错误判断**（第26行）：
   ```java
   if (dungeonId == targetPlayer.getSceneId())
   ```
   将**副本ID**（如 1001）与**场景ID**（如 3）错误比较。两者概念完全不同。

2. **`DungeonData.getStartPosition()` / `getStartRotation()` NPE**（第70-78行）：
   ```java
   public Position getStartPosition() {
       return SceneMeta.of(this.getSceneId()).config.born_pos;  // NPE!
   }
   ```
   当副本场景的 `.lua` 脚本文件缺失时，`SceneMeta.of()` 返回 null，直接 NPE。日志证据：
   ```
   Could not find script at path Scene/20328/scene20328.lua
   NullPointerException: ... SceneMeta.of(int) is null
       at DungeonData.getStartPosition(DungeonData.java:71)
       at World.transferPlayerToScene(World.java:403)
   ```

3. **`enterDungeon()` 返回值 bug**（`DungeonSystem.java:108-115`）：
   - 当 `transferPlayerToScene()` 失败时，DungeonManager 未设置
   - 但方法仍返回 `true`，掩盖了错误
   - 玩家看到"进入成功"消息但实际未进入副本

4. **`DungeonData` 查找失败**：`GameData.getDungeonDataMap().get(dungeonId)` 对不存在的 dungeonId 返回 null，直接返回 false 但无日志提示

### 修复方案
1. **修复 `DungeonData.getStartPosition()` 和 `getStartRotation()` NPE**：
   ```java
   public Position getStartPosition() {
       var meta = SceneMeta.of(this.getSceneId());
       if (meta == null) return GameConstants.START_POSITION;
       return meta.config.born_pos != null ? meta.config.born_pos : GameConstants.START_POSITION;
   }
   ```
2. **修复 `EnterDungeonCommand` 错误判断**：替换为正确的 dungeon 状态检查
3. **修复 `enterDungeon()` 返回值**：根据 `transferPlayerToScene` 结果返回
4. **添加诊断日志**：在 `enterDungeon()` 中记录 dungeonId 不存在、传送失败等异常情况

### 需修改的文件
- `src/main/java/emu/grasscutter/data/excels/dungeon/DungeonData.java`
- `src/main/java/emu/grasscutter/command/commands/EnterDungeonCommand.java`
- `src/main/java/emu/grasscutter/game/dungeons/DungeonSystem.java`

---

## Bug 3：怪物不掉落物品

### 根因分析
`data/` 目录下**完全缺失**三个必需的 JSON 数据文件：

| 文件 | 使用者 | 用途 |
|------|--------|------|
| `Drop.json` | `DropSystemLegacy`（DropSystemLegacy.java:33） | 旧版回退掉落数据 |
| `ChestDrop.json` | `DropSystem`（DropSystem.java:35） | 宝箱掉落索引 |
| `MonsterDrop.json` | `DropSystem`（DropSystem.java:48） | 怪物掉落索引 |

`Scene.killEntity()`（`Scene.java:554-563`）中怪物死亡时：
1. 先尝试 `DropSystem.handleMonsterDrop()`——需要 `MonsterDrop.json` + `DropTableExcelConfigData.json`（后者存在于 `resources/Server/`）
2. 回退到 `DropSystemLegacy.callDrop()`——需要 `Drop.json`

两个路径都因数据文件缺失而失败。`DropSystem` 构造器中的 `catch (Exception ignored)` 静默吞掉异常。

### 修复方案
1. **生成 `MonsterDrop.json`**——将怪物 `drop_tag` + `level` 映射到 `drop_id`
2. **生成 `ChestDrop.json`**——宝箱掉落的类似索引
3. **生成 `Drop.json`**——旧版掉落格式，映射 `monsterId` → `DropData` 列表
4. **改进异常处理**——将 `catch (Exception ignored)` 替换为显式异常日志
5. 在 `Scene.killEntity()` 中添加回退日志

### 需修改/创建的文件
- `data/MonsterDrop.json`（新建）
- `data/ChestDrop.json`（新建）
- `data/Drop.json`（新建）
- `src/main/java/emu/grasscutter/game/drop/DropSystem.java`
- `src/main/java/emu/grasscutter/game/drop/DropSystemLegacy.java`
- `src/main/java/emu/grasscutter/game/world/Scene.java`

---

## Bug 4：Boss 怪物不自然生成

### 根因分析
同上分析。Lua 脚本函数实现缺陷（`MarkPlayerAction` 未实现、`RefreshGroup` 参数丢失、suite 未找到）导致依赖 group 脚本的 Boss 无法生成。

### 修复方案
与 Bug 1 的 `RefreshGroup` 修复联动：
1. **实现 `MarkPlayerAction`**——即使空操作也防止脚本错误级联
2. **修复 `RefreshGroup`**（Bug 1 已包含）
3. **为 Boss 添加回退生成**——group 加载失败时回退到空间生成数据

### 需修改的文件
- `src/main/java/emu/grasscutter/scripts/ScriptLib.java`——实现 `MarkPlayerAction`
- `src/main/java/emu/grasscutter/game/world/Scene.java`——Boss 生成回退

---

## 实施顺序

1. **Bug 2（副本 NPE + 入口）**——修复 `DungeonData` NPE，这是最紧迫的崩溃问题
2. **Bug 1（副本挑战失败UI）**——修复 `RefreshGroup` 参数，正确的副本初始化是后续修复的基础
3. **Bug 3（怪物掉落）**——创建缺失的掉落数据文件
4. **Bug 4（Boss 生成）**——实现 `MarkPlayerAction` + 生成回退

## 验证方式

1. 使用 `/dungeon 1001` 等指令进入各类秘境——确认不再弹出"退出挑战"界面，副本可正常游玩
2. 通过世界入口进入副本——同上验证
3. 在各地图传送点之间传送——确认不弹出挑战失败界面
4. 在大世界击杀怪物——确认掉落物正常出现
5. 前往 Boss 刷新位置——确认 Boss 正常出现
