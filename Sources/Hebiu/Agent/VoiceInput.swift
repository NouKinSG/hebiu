import AVFoundation
import HebiuKit
import Speech

/// 说话输入：系统自带的中文语音识别，支持时只在本机识别。
/// 边说边把字填进输入框；停顿一会儿就算说完（自动发送），再点一次麦克风是只停下不发送
final class VoiceInput: ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case denied(String)
    }

    @Published private(set) var state: State = .idle
    /// 边说边更新
    var onText: ((String) -> Void)?
    /// 说完了（停顿够久），带上最后的文字
    var onFinish: ((String) -> Void)?

    static let silence: TimeInterval = 1.8
    static let maxSeconds: TimeInterval = 40

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var text = ""
    private var silenceWork: DispatchWorkItem?
    private var limitWork: DispatchWorkItem?

    /// 本机能不能离线识别中文（不能时用苹果的识别服务）
    var onDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    func toggle() {
        state == .listening ? stop(send: false) : start()
    }

    func start() {
        guard state != .listening else { return }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.state = .denied("没有语音识别权限：系统设置 → 隐私与安全性 → 语音识别里打开 Hebiu")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    DispatchQueue.main.async {
                        guard ok else {
                            self.state = .denied("没有麦克风权限：系统设置 → 隐私与安全性 → 麦克风里打开 Hebiu")
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            state = .denied("语音识别现在用不了，等会儿再试")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.addsPunctuation = true
        self.request = request
        text = ""

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            Log.write("voice: engine failed \(error.localizedDescription)")
            state = .denied("麦克风打不开：\(error.localizedDescription)")
            cleanUp()
            return
        }
        state = .listening
        Log.write("voice: start (on device: \(recognizer.supportsOnDeviceRecognition))")
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.state == .listening else { return }
                if let result {
                    self.text = result.bestTranscription.formattedString
                    self.onText?(self.text)
                    self.armSilence()
                    if result.isFinal { self.stop(send: true) }
                } else if error != nil {
                    self.stop(send: !self.text.isEmpty)
                }
            }
        }
        let limit = DispatchWorkItem { [weak self] in self?.stop(send: true) }
        limitWork = limit
        DispatchQueue.main.asyncAfter(deadline: .now() + VoiceInput.maxSeconds, execute: limit)
    }

    /// 说了字以后停顿这么久，就算说完
    private func armSilence() {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop(send: true) }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + VoiceInput.silence, execute: work)
    }

    func stop(send: Bool) {
        guard state == .listening else { return }
        state = .idle
        cleanUp()
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.write("voice: stop (\(final.count) chars, send: \(send))")
        if send, !final.isEmpty { onFinish?(final) }
    }

    private func cleanUp() {
        silenceWork?.cancel()
        limitWork?.cancel()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
