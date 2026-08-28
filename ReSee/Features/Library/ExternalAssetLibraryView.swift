import SwiftUI

struct ExternalAssetLibraryView: View {
    @EnvironmentObject private var repository: ExternalAssetRepository

    @State private var isImporting = false
    @State private var pendingURLs: [URL] = []
    @State private var isChoosingStorage = false
    @State private var isShowingDownload = false

    var body: some View {
        Group {
            if repository.assets.isEmpty {
                emptyState
            } else {
                assetList
            }
        }
        .background(AppTheme.background)
        .navigationTitle("外部资源")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isImporting = true
                    } label: {
                        Label("从文件载入", systemImage: "folder")
                    }
                    Button {
                        isShowingDownload = true
                    } label: {
                        Label("从网络下载", systemImage: "arrow.down.circle")
                    }
                } label: {
                    Label("添加资源", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: ExternalAssetFormat.importContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                pendingURLs = urls
                isChoosingStorage = !urls.isEmpty
            case let .failure(error):
                repository.report(error)
            }
        }
        .confirmationDialog(
            "如何保存这些文件？",
            isPresented: $isChoosingStorage,
            titleVisibility: .visible
        ) {
            Button("复制到回见") {
                let urls = pendingURLs
                pendingURLs = []
                Task { await repository.importFiles(urls: urls, copyIntoLibrary: true) }
            }
            Button("保留原位置") {
                let urls = pendingURLs
                pendingURLs = []
                Task { await repository.importFiles(urls: urls, copyIntoLibrary: false) }
            }
            Button("取消", role: .cancel) { pendingURLs = [] }
        } message: {
            Text("复制后原文件被移动或删除仍可浏览；保留原位置不额外占用空间，但依赖原文件持续可用。")
        }
        .sheet(isPresented: $isShowingDownload) {
            DownloadExternalAssetView()
                .environmentObject(repository)
        }
        .overlay {
            if repository.isTransferring {
                transferOverlay
            }
        }
        .alert(
            "外部资源处理失败",
            isPresented: Binding(
                get: { repository.lastError != nil },
                set: { if !$0 { repository.clearError() } }
            )
        ) {
            Button("知道了", role: .cancel) { repository.clearError() }
        } message: {
            Text(repository.lastError ?? "未知错误")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有外部资源", systemImage: "square.and.arrow.down")
        } description: {
            Text("载入 2:1 全景图片，或 PLY、SPLAT、SPZ 格式的 Gaussian Splatting 场景。")
        } actions: {
            Button {
                isImporting = true
            } label: {
                Label("从文件载入", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)

            Button {
                isShowingDownload = true
            } label: {
                Label("从网络下载", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private var assetList: some View {
        List {
            Section {
                ForEach(repository.assets) { asset in
                    NavigationLink(value: asset) {
                        ExternalAssetRow(asset: asset)
                    }
                }
                .onDelete(perform: repository.delete)
            } header: {
                Text("全景与空间文件")
            } footer: {
                Text("删除引用资源只会移除列表记录，不会删除原文件；下载和复制的文件会一并清理。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .listStyle(.insetGrouped)
        .navigationDestination(for: ExternalAsset.self) { asset in
            ExternalAssetViewerView(asset: asset)
        }
    }

    private var transferOverlay: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text(repository.transferProgressDescription ?? "正在处理")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ExternalAssetRow: View {
    let asset: ExternalAsset

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: asset.kind.systemImage)
                .font(.title2)
                .foregroundStyle(asset.kind == .gaussianSplat ? AppTheme.success : AppTheme.accent)
                .frame(width: 56, height: 56)
                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                Text(asset.name).font(.headline)
                Text("\(asset.kind.title) · \(asset.formatSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(asset.storage.title) · \(asset.totalByteCount.formattedFileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DownloadExternalAssetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repository: ExternalAssetRepository

    @State private var address = ""
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/scene.splat", text: $address)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("资源名称（可选）", text: $name)
                } header: {
                    Text("文件地址")
                } footer: {
                    Text("支持 JPG、JPEG、PNG、HEIC、HEIF 全景图片，以及 PLY、SPLAT、SPZ 高斯文件。下载内容会保存到回见的外部资源目录。")
                }
            }
            .navigationTitle("从网络下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("下载") {
                        let address = address
                        let name = name
                        dismiss()
                        Task { await repository.download(from: address, name: name) }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

extension Int64 {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
