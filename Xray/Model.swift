//
//  Model.swift
//  Xray
//
//  Created by pan on 2025/9/19.
//

/// 表示一次 Ping 请求的参数，用于向 Xray 或相关服务发起连通性检测。
/// - datDir: 可选，数据目录路径。
/// - configPath: 可选，配置文件路径。
/// - timeout: 可选，超时时间（单位：秒）。
/// - url: 可选，要进行 Ping 的目标 URL。
/// - proxy: 可选，代理地址（例如 socks5://127.0.0.1:10808）。
struct PingRequest: Codable {
    var datDir: String?
    var configPath: String?
    var timeout: Int?
    var url: String?
    var proxy: String?
}

/// 表示版本信息查询接口的响应结果。
/// - success: 请求是否成功。
/// - data: 返回的版本号字符串（例如 "1.0.0"）。
struct VersionResponse: Codable {
    let success: Bool
    let data: String
}
