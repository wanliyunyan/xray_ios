//
//  LibXrayRuntime.swift
//  Xray
//
//  Created by pan on 2026/8/3.
//

import Foundation
import LibXray

/// LibXray 统一 JSON 调用层产生的错误。
enum LibXrayRuntimeError: LocalizedError {
    /// Swift 请求模型无法转换为 UTF-8 JSON 字符串。
    case invalidJSON

    /// LibXray 返回值不是符合当前接口模型的 JSON 对象。
    case invalidResponse

    /// LibXray 返回 `success = false`，关联值为底层错误信息。
    case invocationFailed(String)

    /// 面向界面和日志的本地化错误描述。
    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "无法生成 LibXray 请求"
        case .invalidResponse:
            "LibXray 返回了无效响应"
        case let .invocationFailed(message):
            message
        }
    }
}

/// `pingBatch` 单项结果。
struct LibXrayPingResult: Decodable, Sendable {
    let success: Bool
    let delay: Int
    let error: String?
}

/// `pingBatch` 单项配置。
struct LibXrayPingConfiguration: Encodable, Sendable {
    let xrayJSON: String
    let outboundTag: String?

    private enum CodingKeys: String, CodingKey {
        case xrayJSON = "xrayJson"
        case outboundTag
    }
}

/// 封装 LibXray API v3 的类型化 JSON 调用协议和常用运行时操作。
///
/// 业务代码只调用下面的 endpoint 方法。方法名、payload 键和响应结构由 Codable 模型
/// 固定在边界内，避免接口变更或拼写错误静默进入运行时。
enum LibXrayRuntime {
    /// LibXray 26.9.9 统一调用协议要求的 API 版本。
    private static let apiVersion = 3

    /// 保护 `LibXrayInvoke` 的进程内互斥锁。
    private static let invocationLock = NSLock()

    /// 将分享链接转换为只包含规范化出站的 Xray JSON。
    static func convertShareLinksToXrayJSON(_ text: String) throws -> Data {
        let response: ConvertedConfigurationResponse = try invoke(
            method: .convertShareLinksToXrayJSON,
            payload: ConvertShareLinksRequest(text: text)
        )
        return try JSONEncoder().encode(response)
    }

    /// 返回内置 Xray Core 版本号。
    static func coreVersion() throws -> String {
        let response: XrayVersionResponse = try invoke(method: .xrayVersion)
        return response.version
    }

    /// 请求 LibXray 分配指定数量的可用本地端口。
    static func freePorts(count: Int) throws -> [Int] {
        let response: FreePortsResponse = try invoke(
            method: .getFreePorts,
            payload: FreePortsRequest(count: count)
        )
        return response.ports
    }

    /// 并发测试一组出站配置的延迟。
    static func pingBatch(
        configurations: [LibXrayPingConfiguration],
        timeout: Int,
        targetURL: URL
    ) throws -> [LibXrayPingResult] {
        let response: PingBatchResponse = try invoke(
            method: .pingBatch,
            payload: PingBatchRequest(
                configs: configurations,
                timeout: timeout,
                url: targetURL.absoluteString
            )
        )
        return response.results
    }

    /// 通过 `runXray` 直接传入配置 JSON 启动 Xray Core。
    static func start(configJSON: String) throws {
        let _: EmptyResponse = try invoke(
            method: .runXray,
            payload: RunXrayRequest(xrayJSON: configJSON)
        )
    }

    /// 通过 `stopXray` 停止当前 Xray 实例。
    static func stop() throws {
        let _: EmptyResponse = try invoke(method: .stopXray)
    }

    /// 查询 Xray 是否处于运行状态。
    static func isXrayRunning() throws -> Bool {
        let response: XrayStateResponse = try invoke(method: .getXrayState)
        return response.running
    }

    private static func invoke<Response: Decodable>(
        method: Method
    ) throws -> Response {
        try perform(
            RequestWithoutPayload(apiVersion: apiVersion, method: method),
            method: method
        )
    }

    private static func invoke<Payload: Encodable, Response: Decodable>(
        method: Method,
        payload: Payload
    ) throws -> Response {
        try perform(
            Request(apiVersion: apiVersion, method: method, payload: payload),
            method: method
        )
    }

    private static func perform<RequestModel: Encodable, Response: Decodable>(
        _ request: RequestModel,
        method: Method
    ) throws -> Response {
        invocationLock.lock()
        defer { invocationLock.unlock() }

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            throw LibXrayRuntimeError.invalidJSON
        }
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw LibXrayRuntimeError.invalidJSON
        }

        let responseJSON = LibXrayInvoke(requestJSON)
        guard let responseData = responseJSON.data(using: .utf8) else {
            throw LibXrayRuntimeError.invalidResponse
        }

        let response: ResponseEnvelope<Response>
        do {
            response = try JSONDecoder().decode(ResponseEnvelope<Response>.self, from: responseData)
        } catch {
            throw LibXrayRuntimeError.invalidResponse
        }

        guard response.success else {
            let message = response.error?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let errorMessage = message.flatMap { $0.isEmpty ? nil : $0 }
                ?? "LibXray \(method.rawValue) 执行失败"
            throw LibXrayRuntimeError.invocationFailed(errorMessage)
        }
        guard let data = response.data else {
            throw LibXrayRuntimeError.invalidResponse
        }
        return data
    }
}

private extension LibXrayRuntime {
    enum Method: String, Encodable {
        case getFreePorts
        case convertShareLinksToXrayJSON = "convertShareLinksToXrayJson"
        case pingBatch
        case runXray
        case stopXray
        case xrayVersion
        case getXrayState
    }

    struct RequestWithoutPayload: Encodable {
        let apiVersion: Int
        let method: Method
    }

    struct Request<Payload: Encodable>: Encodable {
        let apiVersion: Int
        let method: Method
        let payload: Payload
    }

    struct ResponseEnvelope<Response: Decodable>: Decodable {
        let success: Bool
        let data: Response?
        let error: String?
    }

    struct ConvertShareLinksRequest: Encodable {
        let text: String
    }

    struct ConvertedConfigurationResponse: Codable {
        let outbounds: [JSONValue]
    }

    struct FreePortsRequest: Encodable {
        let count: Int
    }

    struct FreePortsResponse: Decodable {
        let ports: [Int]
    }

    struct PingBatchRequest: Encodable {
        let configs: [LibXrayPingConfiguration]
        let timeout: Int
        let url: String
    }

    struct PingBatchResponse: Decodable {
        let results: [LibXrayPingResult]
    }

    struct RunXrayRequest: Encodable {
        let xrayJSON: String

        private enum CodingKeys: String, CodingKey {
            case xrayJSON = "xrayJson"
        }
    }

    struct XrayVersionResponse: Decodable {
        let version: String
    }

    struct XrayStateResponse: Decodable {
        let running: Bool
    }

    struct EmptyResponse: Decodable {}

    indirect enum JSONValue: Codable {
        case object([String: JSONValue])
        case array([JSONValue])
        case string(String)
        case integer(Int64)
        case number(Double)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int64.self) {
                self = .integer(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else if let value = try? container.decode([String: JSONValue].self) {
                self = .object(value)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "不支持的 LibXray JSON 值"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .object(let value):
                try container.encode(value)
            case .array(let value):
                try container.encode(value)
            case .string(let value):
                try container.encode(value)
            case .integer(let value):
                try container.encode(value)
            case .number(let value):
                try container.encode(value)
            case .bool(let value):
                try container.encode(value)
            case .null:
                try container.encodeNil()
            }
        }
    }
}
