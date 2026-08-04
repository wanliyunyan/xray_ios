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
    /// Swift 请求字典无法转换为 UTF-8 JSON 字符串。
    case invalidJSON

    /// LibXray 返回值不是有效的 UTF-8 JSON 对象。
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

/// 封装 LibXray 的统一 JSON 调用协议和常用运行时操作。
///
/// 每次请求都会生成包含 `apiVersion`、`method` 和可选 `payload` 的 JSON 对象，
/// 再通过 `LibXrayInvoke` 调用底层。响应必须包含布尔类型的 `success`；成功时读取
/// `data` 字典，失败时将 `error` 转换为 `LibXrayRuntimeError`。
///
/// LibXray 运行状态由进程共享，因此所有调用使用同一把锁串行执行，避免 App 或扩展
/// 内多个任务同时修改底层运行时状态。
enum LibXrayRuntime {
    /// 保护 `LibXrayInvoke` 的进程内互斥锁。
    private static let invokeLock = NSLock()

    /// 调用指定的 LibXray 方法，并解析响应中的 `data` 对象。
    ///
    /// 调用期间会一直持有互斥锁，直到请求完成并解析响应。`payload` 中的值必须是
    /// `JSONSerialization` 支持的类型，例如字符串、数字、数组或字典。
    ///
    /// - Parameters:
    ///   - method: LibXray 方法名。
    ///   - payload: 可选的业务参数；存在时写入请求的 `payload` 字段。
    /// - Returns: 响应中的 `data` 字典；无数据时返回 `nil`。
    /// - Throws:
    ///   - `LibXrayRuntimeError.invalidJSON`：请求无法生成 UTF-8 JSON。
    ///   - `LibXrayRuntimeError.invalidResponse`：底层响应无法解析为 JSON 对象。
    ///   - `LibXrayRuntimeError.invocationFailed`：底层明确返回执行失败。
    ///   - `JSONSerialization` 在请求或响应序列化期间产生的错误。
    static func invoke(
        method: String,
        payload: [String: Any]? = nil
    ) throws -> [String: Any]? {
        invokeLock.lock()
        defer { invokeLock.unlock() }

        var request: [String: Any] = [
            "apiVersion": 1,
            "method": method,
        ]
        if let payload {
            request["payload"] = payload
        }

        let requestData = try JSONSerialization.data(withJSONObject: request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw LibXrayRuntimeError.invalidJSON
        }

        let responseJSON = LibXrayInvoke(requestJSON)
        guard
            let responseData = responseJSON.data(using: .utf8),
            let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else {
            throw LibXrayRuntimeError.invalidResponse
        }

        guard response["success"] as? Bool == true else {
            let message = (response["error"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LibXrayRuntimeError.invocationFailed(
                message?.isEmpty == false ? message! : "LibXray \(method) 执行失败"
            )
        }

        return response["data"] as? [String: Any]
    }

    /// 将运行配置写入 App Group 的配置目录。
    ///
    /// - Parameters:
    ///   - config: 完整的 Xray JSON 配置字符串。
    ///   - fileName: 配置文件名，不包含目录路径。
    /// - Returns: 写入后的共享文件 URL。
    /// - Throws: 文件无法以 UTF-8 原子写入时抛出文件系统错误。
    static func writeConfig(_ config: String, named fileName: String) throws -> URL {
        let destination = Constant.configDirectory.appendingPathComponent(fileName)
        try config.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    /// 通过 LibXray 的 `testXray` 方法校验配置文件。
    ///
    /// - Parameter configURL: 已写入共享目录的配置文件 URL。
    /// - Throws: 配置语法无效、资源缺失或底层校验失败时抛出错误。
    static func test(configURL: URL) throws {
        _ = try invoke(
            method: "testXray",
            payload: ["configPath": configURL.path]
        )
    }

    /// 通过 LibXray 的 `runXray` 方法启动 Xray Core。
    ///
    /// - Parameter configURL: 已通过校验的运行配置文件 URL。
    /// - Throws: Xray 无法加载配置或启动运行时状态时抛出错误。
    static func run(configURL: URL) throws {
        _ = try invoke(
            method: "runXray",
            payload: ["configPath": configURL.path]
        )
    }

    /// 通过 LibXray 的 `stopXray` 方法停止当前 Xray 实例。
    ///
    /// - Throws: 底层停止操作返回失败时抛出错误。
    static func stop() throws {
        _ = try invoke(method: "stopXray")
    }

    /// 查询 Xray 是否处于运行状态。
    ///
    /// 响应缺少 `running` 字段时按未运行处理，避免将不完整响应误判为启动成功。
    ///
    /// - Returns: `getXrayState` 返回的运行状态。
    /// - Throws: 状态查询调用失败或响应无效时抛出错误。
    static func isRunning() throws -> Bool {
        let data = try invoke(method: "getXrayState")
        return data?["running"] as? Bool ?? false
    }
}
