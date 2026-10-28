import Foundation

/// 发 HTTP 请求的那一层，测试时换成假的
public protocol AgentTransport {
    func send(method: String, url: URL, key: String, body: Data?) async throws -> (status: Int, data: Data)
}

public struct URLSessionTransport: AgentTransport {
    public init() {}
    public func send(method: String, url: URL, key: String, body: Data?) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

/// DeepSeek 对话补全（OpenAI 格式）和余额接口
public struct DeepSeekClient {
    public static let model = "deepseek-flash"
    public let baseURL: URL
    public let transport: AgentTransport

    public init(baseURL: URL = URL(string: "https://api.deepseek.com")!, transport: AgentTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public struct ToolCall: Equatable {
        public let id: String
        public let name: String
        public let arguments: String
    }

    public struct Reply {
        public let content: String
        public let toolCalls: [ToolCall]
        public let usage: AgentUsage
        /// 原样的 assistant 消息，回传给下一轮
        public let rawMessage: [String: Any]
    }

    public enum Failure: Error, Equatable {
        case badKey          // 401
        case noBalance       // 402
        case busy            // 429 / 5xx
        case network         // 连不上、超时
        case badResponse(Int)
    }

    /// tools 为空时不带工具；json 为 true 时要求输出 JSON 对象
    public func chat(messages: [[String: Any]], tools: [[String: Any]], key: String, json: Bool = false) async throws -> Reply {
        var body: [String: Any] = [
            "model": DeepSeekClient.model,
            "messages": messages,
            "thinking": ["type": "disabled"],
            "temperature": 0.9,
        ]
        if !tools.isEmpty { body["tools"] = tools }
        if json { body["response_format"] = ["type": "json_object"] }
        // 键排好序：同样的工具和前文每次发出去一字不差，才能命中 DeepSeek 的缓存
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (status, resp) = try await call("POST", "chat/completions", key: key, body: data)
        guard let json = try? JSONSerialization.jsonObject(with: resp) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else { throw Failure.badResponse(status) }
        let calls = (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { c -> ToolCall? in
            guard let id = c["id"] as? String, let f = c["function"] as? [String: Any], let name = f["name"] as? String else { return nil }
            return ToolCall(id: id, name: name, arguments: f["arguments"] as? String ?? "{}")
        }
        let u = json["usage"] as? [String: Any] ?? [:]
        let usage = AgentUsage(promptCacheHitTokens: u["prompt_cache_hit_tokens"] as? Int ?? 0,
                               promptCacheMissTokens: u["prompt_cache_miss_tokens"] as? Int ?? (u["prompt_tokens"] as? Int ?? 0),
                               completionTokens: u["completion_tokens"] as? Int ?? 0)
        var raw: [String: Any] = ["role": "assistant", "content": message["content"] as? String ?? ""]
        if let tc = message["tool_calls"] { raw["tool_calls"] = tc }
        return Reply(content: (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                     toolCalls: calls, usage: usage, rawMessage: raw)
    }

    /// 账户余额（人民币），取不到返回 nil
    public func balance(key: String) async -> String? {
        guard let (status, data) = try? await call("GET", "user/balance", key: key, body: nil), status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let infos = json["balance_infos"] as? [[String: Any]] else { return nil }
        return (infos.first { $0["currency"] as? String == "CNY" } ?? infos.first)?["total_balance"] as? String
    }

    /// 429、5xx 等 2 秒重试一次
    private func call(_ method: String, _ path: String, key: String, body: Data?) async throws -> (Int, Data) {
        let url = baseURL.appendingPathComponent(path)
        for attempt in 0..<2 {
            let status: Int, data: Data
            do {
                (status, data) = try await transport.send(method: method, url: url, key: key, body: body)
            } catch {
                if attempt == 0 { try? await Task.sleep(nanoseconds: 2_000_000_000); continue }
                throw Failure.network
            }
            switch status {
            case 200: return (status, data)
            case 401: throw Failure.badKey
            case 402: throw Failure.noBalance
            case 429, 500...599:
                if attempt == 0 { try? await Task.sleep(nanoseconds: 2_000_000_000); continue }
                throw Failure.busy
            default: throw Failure.badResponse(status)
            }
        }
        throw Failure.network
    }
}
