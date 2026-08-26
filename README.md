# 回见

“回见”是一款面向 iPhone / iPad 的空间记录应用。它不是把用户固定在一个拍摄点的 360° 全景相册，而是以 **6DoF 空间记录**为目标：用户可以采集一个房间或点位，在有限的已采集范围内移动、旋转和缩放查看，并把文字、图片或语音信息绑定到空间中的物品。

> 项目目前处于 MVP 初始化阶段。现阶段优先验证“采集、浏览、标注、保存”的产品闭环，高质量摄影测量与 3D Gaussian Splatting（3DGS）将作为后续能力接入。

## 产品路线

核心技术路线为：

```text
iPhone / iPad
  ARKit 采集图像、相机位姿、深度与空间网格
        ↓
  本地低精度预览、场景管理与空间标注
        ↓
  服务端摄影测量（规划：COLMAP / AliceVision）
        ↓
  带纹理网格（USDZ / GLB）+ 可选 3DGS 视觉层（SPZ）
        ↓
  RealityKit / Metal 浏览、测量与标注
```

网格将作为碰撞、测量和标注的稳定几何基础；3DGS 只负责高真实感外观，避免把不稳定的视觉点云当作权威空间几何。

## 当前已初始化

- SwiftUI 应用框架与原生 Xcode 工程
- 首页场景资料库、空状态和场景详情页
- ARKit / RealityKit 采集界面
- LiDAR 场景重建能力检测、深度语义和网格可视化
- 跟踪状态、网格数量、采集时长和覆盖进度提示
- 本地 JSON 场景索引与示例标注数据结构
- 相机权限声明和不支持设备的降级提示
- 数据模型单元测试

当前“完成采集”会保存一次场景记录及采集统计，还不会持久化原始相机帧、网格或 USDZ 文件。这部分是下一阶段的首要实现项，README 不将初始化骨架描述成已完成的重建产品。

## 环境要求

- Xcode 16 或更新版本
- iOS 17.0 或更新版本
- 真机运行 AR 采集
- 推荐带 LiDAR 的 iPhone Pro 或 iPad Pro

不带 LiDAR 的设备仍可使用 ARKit 位姿跟踪，但无法生成同等质量的实时空间网格。模拟器只能查看非 AR 界面。

## 运行

1. 使用 Xcode 打开 `ReSee.xcodeproj`。
2. 在 Signing & Capabilities 中选择自己的开发团队。
3. 选择一台 iOS 真机并运行 `ReSee` scheme。
4. 首次进入采集页时允许相机权限。

也可以使用命令行检查工程：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ReSee.xcodeproj \
  -scheme ReSee \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

## 目录结构

```text
ReSee/
├── App/                 # 应用入口、根视图与视觉规范
├── Features/
│   ├── Capture/         # AR 采集体验与会话桥接
│   ├── Library/         # 场景资料库
│   └── Viewer/          # 场景详情与浏览入口
├── Models/              # 场景、采集和空间标注模型
├── Resources/           # Info.plist 与 Assets
└── Services/            # 本地场景仓库
ReSeeTests/              # 单元测试
```

## 数据设计

场景索引保存在应用沙盒 `Application Support/Scenes/scenes.json`。空间标注不只保存一次 AR 会话的世界坐标，还预留了模型版本、法线、三角形编号和重心坐标：

```text
annotationID
modelVersion
position / normal
meshTriangleID / barycentricCoordinate
title / note / mediaReferences
```

后续模型重新生成时，可以通过三角形与重心坐标迁移标注，减少对易变化的 ARKit 会话坐标系的依赖。

## 下一步

1. 按关键帧策略落盘图像、内参、位姿、深度和网格。
2. 把一次采集封装为可校验、可恢复、可分块上传的场景包。
3. 导出 USDZ，并完成 RealityKit 网格浏览、射线命中和文字标注。
4. 接入服务端 COLMAP 位姿优化与带纹理网格生成。
5. 加入模型版本、标注迁移、离线下载和质量检测。
6. 最后评估 SPZ / 3DGS 的移动端渲染与内存预算。

## 许可证注意事项

本仓库当前只使用 Apple 原生框架。未来引入重建组件时应锁定具体版本并审查全部传递依赖：COLMAP（BSD-3-Clause）、Open3D（MIT）通常较易用于商业项目；OpenMVS（AGPL-3.0）、ORB-SLAM3（GPL-3.0）以及部分原始 3DGS 实现需要额外评估，不应默认可直接集成到闭源 App。

