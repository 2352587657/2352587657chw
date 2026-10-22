# 方野 · Blocklands

一个 Godot 4 第一人称方块建造游戏原型，面向 Windows。无需付费素材或额外插件。

## 在 Windows 上打开游戏

1. 从 https://godotengine.org/download/windows/ 下载 **Godot 4.6 标准版**（不需要 .NET 版），解压并打开。
2. 将本项目下载到电脑并解压。如果从 GitHub 下载，使用绿色 **Code → Download ZIP**；需先确保本次代码已保存到 GitHub。
3. 在 Godot 项目管理器中点击 **导入**，选中本项目的 `project.godot`，再点击 **导入并编辑**。
4. 等待导入完成，按 **F5** 运行。点击“开始 / 继续游戏”。首次生成地图可能需要几秒。
5. 按 **Esc** 可以释放鼠标并打开菜单。关闭游戏后，地图改动不会保存。

本项目目前是源代码项目，不是双击即可运行的 Windows EXE。若要导出 EXE，在 Godot 的“项目 → 导出”添加 Windows Desktop，按提示安装对应导出模板，再导出到 `build/`。

## 操作

| 操作 | 按键 |
| --- | --- |
| 移动 / 观察 | WASD / 鼠标 |
| 跳跃 | 空格 |
| 挖掉瞄准的方块 | 鼠标左键，距离 6 格以内 |
| 在方块表面放置 | 鼠标右键 |
| 选择草地、泥土、石头、木头、树叶、沙子 | 数字 1–6 |
| 与附近向导交谈 | E，距离 4 格以内 |
| 打开菜单 / 继续 | Esc |

## 当前内容与限制

- 开始、继续、退出菜单；第一人称移动、重力、地面碰撞、跳跃与跌落重生。
- 固定的 44 × 44 格地图，包含山地、河流和水面、可挖的树木、装饰石头与草丛。
- 挖掘和放置；防止在玩家或 NPC 身体内放置方块。自由建造材料无限，挖掘暂不计入背包。
- 友善向导会简单游走、尝试转向避障，并提供一句操作对话；还不是完整寻路或任务系统。
- 水面为视觉效果，没有游泳和水流模拟。装饰小石头、草丛暂不可采集，可挖掘地形中的石头。
- 地图有限且没有边界墙；走出地图或向下挖穿后会跌落重生。没有存档、背包、工具、音效或战斗。
- 当前每格使用独立网格与碰撞，适合小地图原型；大地图需要分块网格优化。

## 后续替换模型

`scripts/player.gd` 负责玩家移动和观察；`scripts/game.gd` 管理地形数据、交互、菜单和 NPC。地形以 `Vector3i` 坐标记录方块，模型外观由 `add_block` 创建；装饰由 `add_decoration` 创建，NPC 外观在 `create_npc` 创建。后续可以替换这些可视节点，保留坐标和碰撞规则。复杂模型仍需匹配方块占用范围。

## 云端验证

环境已有 Godot 4.6.3。使用已有 checkout，无需新建 worktree。

```bash
cd /workspace/2352587657chw
mkdir -p /workspace/.local/share /workspace/.local/config /workspace/.local/cache
export XDG_DATA_HOME=/workspace/.local/share
export XDG_CONFIG_HOME=/workspace/.local/config
export XDG_CACHE_HOME=/workspace/.local/cache
godot --headless --path . --editor --import --quit
timeout 45s godot --headless --path . -- --smoke-test
```

冒烟验证涵盖地图生成、角色落地、挖掘、放置、身体重叠保护、瞄准射线、鼠标挖掘、NPC 对话和菜单继续。无窗口验证无法代替 Windows 实机画面与手感检查。
