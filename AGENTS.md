# AGENTS.md - 回见开发规范

## 项目定位

“回见”（工程名 `ReSee`）是一款原生 iOS 空间记录应用。当前阶段以固定点 360° 全景完成采集与浏览闭环，长期目标是通过 ARKit 采集相机位姿、深度和空间网格，形成可在有限采集范围内移动查看、缩放和标注的 6DoF 数字空间。

当前仓库已实现“场景列表 → 球面方向 AR 采集 → 本地全景生成与保存 → 360° 查看”的 MVP：每个点位采集 52 个球面目标，通过相机位姿和内参生成 2:1 等距柱状全景图，并支持连续环视与缩放。多点模式只在三个离散全景点位之间切换，不是连续 6DoF。生成后尚未持久化原始相机帧、深度、网格或 USDZ，也尚未接入摄影测量和 3DGS；空间标注仍是规划能力。实现和文档不得把这些规划能力描述成已经完成。

## 技术栈与要求

- Swift 5、SwiftUI
- ARKit、RealityKit
- XCTest
- Xcode 16 或更新版本
- iOS 18.0 或更新版本
- AR 采集必须在 iOS 真机验证；推荐带 LiDAR 的 iPhone Pro 或 iPad Pro
- 不引入第三方依赖，除非需求确实需要并已评估许可证、包体积和维护成本；当前外部 3DGS 浏览固定使用 MIT 许可的 MetalSplatter 1.0.1

完整产品路线、数据设计与开源组件选择见 `README.md`。

## 工程结构

```text
ReSee/
├── App/                 # 应用入口、根导航和视觉规范
├── Features/
│   ├── Capture/         # AR 会话、采集状态和引导
│   ├── Library/         # 本地场景资料库
│   └── Viewer/          # 场景详情、浏览和标注入口
├── Models/              # 场景、采集摘要和空间标注模型
├── Resources/           # Info.plist 与 Assets
└── Services/            # 本地持久化及未来服务接口
ReSeeTests/              # 单元测试
```

新增 Swift 文件时，要确认已加入正确 target。修改 `project.pbxproj` 时保持 ID 唯一、分组与磁盘目录一致，并避免写入 `xcuserdata` 等本机状态。

## 构建与测试

不要修改机器全局 `xcode-select`；命令行操作显式使用完整 Xcode：

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -list -project ReSee.xcodeproj
```

无签名模拟器构建：

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ReSee.xcodeproj \
  -scheme ReSee \
  -sdk iphonesimulator \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

编译应用与测试 target：

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ReSee.xcodeproj \
  -scheme ReSee \
  -sdk iphonesimulator \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

模拟器服务可用时，使用明确 destination 执行测试。不要把 `build-for-testing` 写成“测试已运行”，也不要把 CoreSimulator、签名或沙盒故障归因于业务代码。

验证范围应与改动风险相称：纯文档或 agent 规范变更无需强制构建整个 App；Swift、Assets、Info.plist 或 Xcode 工程变化至少完成构建；AR 行为变化还需要真机验证并说明设备能力。

## Swift 与 SwiftUI 约定

- 使用 4 空格缩进，遵循 Swift API Design Guidelines。
- 类型使用 `UpperCamelCase`，属性、方法和枚举 case 使用 `lowerCamelCase`。
- 优先使用值类型表达领域数据，服务和共享状态根据生命周期使用引用类型。
- UI 可观察状态和持久化入口保持在主 actor；ARSession 高频回调只传递必要数据，并限制刷新频率。
- 避免强制解包、静默吞错和无边界的后台任务。用户可恢复的错误应提供明确中文提示。
- SwiftUI 视图保持职责单一；业务状态、持久化和 AR 会话逻辑不要堆进大型 View body。
- 用户可见文案当前统一使用中文。新增文案应简洁、准确，不承诺尚未实现的重建质量。
- 保持深色视觉基调和 `AppTheme` 设计令牌；新增颜色、间距和容器样式优先复用现有规范。

## ARKit 与空间采集约束

- 每次创建 AR 配置前检查对应能力：世界跟踪、场景重建、深度语义等不得假定所有设备支持。
- LiDAR 是增强能力，不是所有流程的隐式前提。不支持时提供可理解的视觉定位降级状态。
- 模拟器不能证明相机、深度、网格、追踪恢复或性能正确；涉及这些功能必须标记为待真机验证。
- ARSession delegate 回调频率很高。不得在每一帧直接编码图片、写 JSON 或触发 SwiftUI 全量刷新；原始采集应采用明确的关键帧、背压、磁盘预算和失败恢复策略。
- 低光、玻璃、镜面、纯色墙和重复纹理会影响质量。采集引导与质量判断要允许受限状态，而不是伪造覆盖完成。
- 网格负责射线命中、碰撞、测量和标注几何；未来的 3DGS 只作为视觉层，不能成为精确几何的唯一来源。
- AR 世界坐标只属于一次会话。持久标注应绑定模型版本，并保留模型坐标、表面法线、三角形 ID 和重心坐标等迁移信息。

## 数据、版本与隐私

- 场景索引当前保存于应用沙盒 `Application Support/Scenes/scenes.json`。
- 原始采集数据、派生模型和用户标注需要分别建模；不要只保留最终模型，也不要把大型二进制塞进场景索引 JSON。
- 持久化结构一旦随对外版本发布，就视为兼容边界。修改结构时提供默认值、迁移或明确的不可兼容策略，并增加编码往返测试。
- `modelVersion` 表示标注所依赖的模型版本。重新生成模型时不能无条件复用旧三角形索引。
- 相机画面、深度、位姿、网格、世界地图、位置和用户附件都属于敏感数据。只采集完成功能所需的信息，权限文案必须与实际行为一致。
- 不得把真实用户采集包、照片、音视频、位置、证书、provisioning profile、密钥或服务令牌提交到仓库。
- 日志不得输出原始媒体、精确位置、访问令牌或可恢复完整空间的信息。

## 测试要求

- 数据模型变化至少覆盖 Codable 往返、默认值或迁移路径。
- 持久化测试使用临时目录，不读写用户真实 `Application Support`。
- AR 逻辑尽量把可测试的状态映射、覆盖计算和关键帧判断从框架回调中拆出。
- 测试用户可见行为和稳定接口，不依赖与功能无关的内部布局或历史实现。
- 修复缺陷时补充能够复现该问题的最小测试；无法自动化的真机问题记录设备、系统版本和复现步骤。

## 工作区与 Git

- 保留用户已有变更，不还原或覆盖与当前任务无关的文件。
- `DerivedData/`、`.build/`、`xcuserdata/`、`*.xcuserstate`、本地采集和导出目录必须保持忽略。
- 不使用破坏性 Git 命令清理工作区。
- 用户要求创建 commit 时，遵循 `.agents/skills/commit/SKILL.md`：先展示英文 Conventional Commit 信息、完整文件清单和验证结果，等待中文明确确认后才能暂存和提交。
- commit 不等于 push、tag 或发布；这些外部变更需要单独明确授权。
