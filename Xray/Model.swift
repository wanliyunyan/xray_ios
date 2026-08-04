//
//  Model.swift
//  Xray
//
//  Created by pan on 2025/9/19.
//

/// 旧版 LibXray Ping 接口使用的可选参数结构。
///
/// 当前统一 JSON 接口直接使用字典构造相同字段，该结构保留用于兼容旧数据或后续迁移。
struct PingRequest: Codable {
    /// Xray geo 资源目录路径。
    var datDir: String?

    /// Ping 使用的 Xray JSON 配置文件路径。
    var configPath: String?

    /// 请求超时时间，单位为秒。
    var timeout: Int?

    /// 实际执行连通性检测的目标 URL。
    var url: String?

    /// 测试请求经过的本地代理地址，例如 `socks5://127.0.0.1:10808`。
    var proxy: String?
}

/// 旧版版本查询接口的响应结构。
///
/// 当前统一 JSON 接口从字典读取 `version` 字段，该结构保留用于兼容旧响应格式。
struct VersionResponse: Codable {
    /// 底层版本查询是否成功。
    let success: Bool

    /// 成功时返回的 Xray Core 版本字符串。
    let data: String
}
