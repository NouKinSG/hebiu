import Foundation

/// 监听单个文件的变化；文件被删除或被编辑器整体替换后会自动重新挂上
public final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?

    public init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        attach()
    }

    private func attach() {
        source?.cancel()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // 文件暂时不存在（比如编辑器正在保存），稍后重试
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.attach() }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self, let src = self.source else { return }
            let flags = src.data
            if flags.contains(.delete) || flags.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.attach()
                    self?.onChange()
                }
            } else {
                self.onChange()
            }
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    deinit { source?.cancel() }
}

/// 读取 ~/.hebiu/events 里新追加的行，每行一个事件名（如 done）
/// 启动时跳过已有内容，避免把旧事件重放一遍；文件超过 64KB 读完后清空
public final class EventInbox {
    private var offset: UInt64 = 0
    private var watcher: FileWatcher?
    private let onEvent: (ClaudeEventLine) -> Void
    private static let maxBytes: UInt64 = 64 * 1024

    /// 每行交出去：事件名，新版钩子还带会话和项目
    public init(onEvent: @escaping (ClaudeEventLine) -> Void) {
        self.onEvent = onEvent
        Paths.prepare()
        offset = fileSize()
        watcher = FileWatcher(url: Paths.events) { [weak self] in self?.drain() }
    }

    private func fileSize() -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: Paths.events.path)[.size] as? UInt64) ?? 0
    }

    private func drain() {
        Paths.prepare()
        let size = fileSize()
        if size < offset { offset = 0 }            // 文件被截断或重建
        guard size > offset, let handle = try? FileHandle(forReadingFrom: Paths.events) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        offset += UInt64(data.count)
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) {
            if let e = ClaudeEventLine(line) { onEvent(e) }
        }
        if offset > EventInbox.maxBytes, let writer = try? FileHandle(forWritingTo: Paths.events) {
            try? writer.truncate(atOffset: 0)
            try? writer.close()
            offset = 0
        }
    }
}

/// 监听一个文件夹里的增删（有文件放进来就通知）；文件夹不存在会先建好
public final class DirectoryWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?

    public init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { Log.write("cannot watch \(url.path)"); return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.onChange() }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    deinit { source?.cancel() }
}
