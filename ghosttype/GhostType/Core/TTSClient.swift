import Foundation
import AVFoundation
import Combine

enum TTSState: Equatable {
    case idle
    case connecting
    case speaking
    case error(String)
}

class TTSClient: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var state: TTSState = .idle

    var voiceId: String = "English_Graceful_Lady"
    var speed: Double = 1.0

    private var webSocketTask: URLSessionWebSocketTask?
    private var audioPlayer: AVAudioPlayer?
    private var audioBuffer = Data()
    private var urlSession: URLSession?
    private var isStopping = false

    func speak(_ text: String, apiKey: String) {
        guard !text.isEmpty else { return }
        guard state != .connecting && state != .speaking else { return }

        isStopping = false
        NSLog("[GhostType][TTS] Starting speech, text length: %d, voice: %@", text.count, voiceId)
        DispatchQueue.main.async { self.state = .connecting }

        audioBuffer = Data()

        var request = URLRequest(url: URL(string: "wss://api.minimax.io/ws/v1/t2a_v2")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        urlSession = session
        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        receiveMessage(text: text)
    }

    func stop() {
        NSLog("[GhostType][TTS] Stopping")
        isStopping = true
        audioPlayer?.stop()
        audioPlayer = nil

        if let task = webSocketTask {
            let finish = ["event": "task_finish"]
            if let data = try? JSONSerialization.data(withJSONObject: finish),
               let str = String(data: data, encoding: .utf8) {
                task.send(.string(str)) { _ in }
            }
            task.cancel(with: .normalClosure, reason: nil)
        }
        webSocketTask = nil
        urlSession = nil
        audioBuffer = Data()

        DispatchQueue.main.async { self.state = .idle }
    }

    // MARK: - WebSocket Message Handling

    private func receiveMessage(text: String) {
        guard let task = webSocketTask else {
            NSLog("[GhostType][TTS] receiveMessage called but webSocketTask is nil")
            return
        }
        NSLog("[GhostType][TTS] Waiting for next WebSocket message...")
        task.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let str):
                    let preview = str.prefix(200)
                    NSLog("[GhostType][TTS] Received message (%d chars): %@", str.count, String(preview))
                    self.handleMessage(str, text: text)
                case .data(let data):
                    NSLog("[GhostType][TTS] Received binary message: %d bytes (unexpected)", data.count)
                @unknown default:
                    NSLog("[GhostType][TTS] Received unknown message type")
                }
            case .failure(let error):
                if self.isStopping {
                    NSLog("[GhostType][TTS] WebSocket error after stop (ignored): %@", error.localizedDescription)
                    return
                }
                NSLog("[GhostType][TTS] WebSocket error: %@", error.localizedDescription)
                DispatchQueue.main.async { self.state = .error(error.localizedDescription) }
            }
        }
    }

    private var audioChunkCount = 0

    private func handleMessage(_ messageStr: String, text: String) {
        guard let data = messageStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("[GhostType][TTS] Failed to parse message as JSON, raw: %@", String(messageStr.prefix(200)))
            receiveMessage(text: text)
            return
        }

        // Log all top-level keys for debugging
        let keys = json.keys.sorted().joined(separator: ", ")
        let event = json["event"] as? String
        NSLog("[GhostType][TTS] Message keys: [%@], event: %@", keys, event ?? "(none)")

        // Handle audio data first — audio chunks arrive in messages that also have an event field
        if let audioData = json["data"] as? [String: Any],
           let hexString = audioData["audio"] as? String {
            audioChunkCount += 1
            if let decoded = hexToData(hexString) {
                audioBuffer.append(decoded)
                NSLog("[GhostType][TTS] Audio chunk #%d: +%d bytes (hex len: %d), buffer total: %d bytes",
                      audioChunkCount, decoded.count, hexString.count, audioBuffer.count)
            } else {
                NSLog("[GhostType][TTS] Audio chunk #%d: hex decode FAILED (hex len: %d, first 40: %@)",
                      audioChunkCount, hexString.count, String(hexString.prefix(40)))
            }

            let isFinal = json["is_final"] as? Bool ?? false
            if isFinal {
                NSLog("[GhostType][TTS] Final audio chunk received, total chunks: %d, buffer: %d bytes", audioChunkCount, audioBuffer.count)
                playAudio()
                sendTaskFinish()
                receiveMessage(text: text)
            } else {
                receiveMessage(text: text)
            }
            return
        }

        // Handle events (after audio data, since audio messages also carry an event field)
        if let event = event {
            switch event {
            case "connected_success":
                NSLog("[GhostType][TTS] Connected, sending task_start")
                sendTaskStart()
                receiveMessage(text: text)

            case "task_started":
                NSLog("[GhostType][TTS] Task started, sending text (%d chars)", text.count)
                audioChunkCount = 0
                DispatchQueue.main.async { self.state = .speaking }
                sendText(text)
                receiveMessage(text: text)

            case "task_finished":
                NSLog("[GhostType][TTS] Task finished (received %d audio chunks, buffer: %d bytes)", audioChunkCount, audioBuffer.count)
                webSocketTask?.cancel(with: .normalClosure, reason: nil)
                webSocketTask = nil
                urlSession = nil

            default:
                NSLog("[GhostType][TTS] Unhandled event: %@", event)
                receiveMessage(text: text)
            }
            return
        }

        // Check for error in response
        if let baseResp = json["base_resp"] as? [String: Any],
           let statusCode = baseResp["status_code"] as? Int,
           statusCode != 0 {
            let msg = baseResp["status_msg"] as? String ?? "Unknown error"
            NSLog("[GhostType][TTS] API error (code %d): %@", statusCode, msg)
            DispatchQueue.main.async { self.state = .error(msg) }
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
            urlSession = nil
            return
        }

        // Unhandled message shape
        NSLog("[GhostType][TTS] Unhandled message shape, keys: [%@]", keys)
        receiveMessage(text: text)
    }

    // MARK: - Protocol Messages

    private func sendTaskStart() {
        let message: [String: Any] = [
            "event": "task_start",
            "model": "speech-2.8-turbo",
            "voice_setting": [
                "voice_id": voiceId,
                "speed": speed
            ],
            "audio_setting": [
                "format": "mp3",
                "sample_rate": 32000,
                "bitrate": 128000
            ]
        ]
        sendJSON(message)
    }

    private func sendText(_ text: String) {
        let message: [String: Any] = [
            "event": "task_continue",
            "text": text
        ]
        sendJSON(message)
    }

    private func sendTaskFinish() {
        let message: [String: Any] = [
            "event": "task_finish"
        ]
        sendJSON(message)
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            NSLog("[GhostType][TTS] sendJSON: failed to serialize dict")
            return
        }
        let event = dict["event"] as? String ?? "?"
        NSLog("[GhostType][TTS] Sending '%@' (%d chars)", event, str.count)
        guard let task = webSocketTask else {
            NSLog("[GhostType][TTS] sendJSON: webSocketTask is nil, cannot send '%@'", event)
            return
        }
        task.send(.string(str)) { error in
            if let error = error {
                NSLog("[GhostType][TTS] Send error for '%@': %@", event, error.localizedDescription)
            } else {
                NSLog("[GhostType][TTS] Sent '%@' OK", event)
            }
        }
    }

    // MARK: - Audio Playback

    private func playAudio() {
        guard !audioBuffer.isEmpty else {
            NSLog("[GhostType][TTS] Empty audio buffer, nothing to play")
            DispatchQueue.main.async { self.state = .idle }
            return
        }

        NSLog("[GhostType][TTS] playAudio: buffer %d bytes, first 8 hex: %@",
              audioBuffer.count,
              audioBuffer.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "))

        do {
            let player = try AVAudioPlayer(data: audioBuffer, fileTypeHint: AVFileType.mp3.rawValue)
            player.delegate = self
            player.volume = 1.0

            let prepared = player.prepareToPlay()
            NSLog("[GhostType][TTS] prepareToPlay: %@, duration: %.2fs, channels: %d, format: %@, volume: %.1f",
                  prepared ? "YES" : "NO",
                  player.duration,
                  player.numberOfChannels,
                  player.format.description,
                  player.volume)

            let started = player.play()
            NSLog("[GhostType][TTS] play() returned: %@, isPlaying: %@",
                  started ? "YES" : "NO",
                  player.isPlaying ? "YES" : "NO")

            audioPlayer = player
        } catch {
            NSLog("[GhostType][TTS] Audio playback error: %@", error.localizedDescription)
            DispatchQueue.main.async { self.state = .error("Playback failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        NSLog("[GhostType][TTS] Playback finished, success: %@", flag ? "YES" : "NO")
        DispatchQueue.main.async { self.state = .idle }
        audioPlayer = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        NSLog("[GhostType][TTS] Decode error: %@", error?.localizedDescription ?? "unknown")
        DispatchQueue.main.async { self.state = .error("Audio decode error") }
        audioPlayer = nil
    }

    // MARK: - Hex Decoding

    private func hexToData(_ hex: String) -> Data? {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard nextIndex != index else { break }
            let byteString = hex[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}
