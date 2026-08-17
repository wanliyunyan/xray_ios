//
//  PacketTunnelProvider.swift
//  PacketTunnel
//
//  Created by pan on 2024/9/14.
//

import Darwin
import Foundation
import NetworkExtension
import os

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PacketTunnelProvider")

/// Packet Tunnel 扩展入口，将 NetworkExtension 创建的 utun 交给 Xray TUN 入站处理。
final class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    /// utun 与 Xray TUN 入站共同使用的最大传输单元。
    private let tunnelMTU = 1500

    /// 串行执行 Xray 的启动和停止，避免生命周期调用交叉修改底层状态。
    private let runtimeQueue = DispatchQueue(label: "xray.packet-tunnel-runtime")

    // MARK: - 隧道生命周期

    /// 启动 Packet Tunnel，并将系统创建的 utun 文件描述符交给 Xray。
    ///
    /// 完整流程：
    /// 1. 从启动参数中读取主 App 生成的 Xray JSON 配置；
    /// 2. 先应用 IPv4、IPv6、默认路由和 DNS 等 NetworkExtension 设置；
    /// 3. 等待系统创建 utun socket，并定位对应文件描述符；
    /// 4. 将文件描述符注入 `env.xray.tun.fd`，校验配置后启动 Xray；
    /// 5. 仅在 Xray 确认进入运行状态后调用成功回调。
    ///
    /// - Parameters:
    ///   - options: `PacketTunnelManager` 通过 `startVPNTunnel(options:)` 传入的启动参数。
    ///   - completionHandler: 启动完成回调；任何配置、网络设置或 Xray 错误都会原样返回。
    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        guard
            let configurationData = options?[AppConstants.tunnelConfigurationOptionKey] as? Data,
            let configurationJSON = String(data: configurationData, encoding: .utf8),
            !configurationJSON.isEmpty
        else {
            completionHandler(
                NSError(
                    domain: "PacketTunnel",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "缺少配置"]
                )
            )
            return
        }

        // 网络设置尚未完成时保持 reasserting，避免系统把初始化过程视为稳定连接。
        reasserting = true
        setTunnelNetworkSettings(makeTunnelNetworkSettings()) { [weak self] error in
            guard let self else {
                completionHandler(
                    NSError(
                        domain: "PacketTunnel",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Packet Tunnel 已释放"]
                    )
                )
                return
            }
            if let error {
                self.reasserting = false
                completionHandler(error)
                return
            }
            self.findTunnelFileDescriptor { fileDescriptorResult in
                switch fileDescriptorResult {
                case .success(let fileDescriptor):
                    self.startXrayRuntime(
                        configurationJSON: configurationJSON,
                        tunnelFileDescriptor: fileDescriptor,
                        completionHandler: completionHandler
                    )
                case .failure(let error):
                    self.reasserting = false
                    completionHandler(error)
                }
            }
        }
    }

    /// 停止 Xray 并结束 Packet Tunnel 生命周期。
    ///
    /// 停止操作放在 `runtimeQueue` 上，与启动流程保持串行。即使底层停止失败，也必须调用
    /// `completionHandler`，让 NetworkExtension 能完成系统侧资源回收。
    ///
    /// - Parameters:
    ///   - reason: NetworkExtension 提供的停止原因，仅用于日志记录。
    ///   - completionHandler: Xray 停止尝试完成后调用的系统回调。
    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping @Sendable () -> Void
    ) {
        reasserting = false
        runtimeQueue.async {
            try? LibXrayRuntime.stop()
            logger.info("隧道停止, 原因: \(reason.rawValue)")
            completionHandler()
        }
    }

    // MARK: - Xray Runtime

    /// 注入 utun 文件描述符，校验配置并启动 Xray。
    ///
    /// 该方法在专用串行队列执行。清理可能残留的旧实例后，通过 `runXrayFromJson`
    /// 直接传入完整 JSON 启动。由于启动调用成功并不一定代表 Core 已进入运行状态，
    /// 最后还会通过 `getXrayState` 做一次确认。
    ///
    /// - Parameters:
    ///   - configurationJSON: 主 App 传入、尚未注入运行时环境变量的 JSON 字符串。
    ///   - tunnelFileDescriptor: NetworkExtension 创建的 utun socket 文件描述符。
    ///   - completionHandler: 返回最终启动结果的系统回调。
    private func startXrayRuntime(
        configurationJSON: String,
        tunnelFileDescriptor: Int32,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        runtimeQueue.async {
            do {
                // 1. 合并资源目录与 utun FD，生成扩展进程最终使用的配置。
                let runtimeConfigurationJSON = try self.makeRuntimeConfiguration(
                    configurationJSON,
                    tunnelFileDescriptor: tunnelFileDescriptor
                )

                // 2. 停止残留实例后直接传入 JSON 启动，无需写配置文件。
                try? LibXrayRuntime.stop()
                try LibXrayRuntime.start(configJSON: runtimeConfigurationJSON)

                // 3. 只有底层明确进入 running 状态，系统隧道才算启动成功。
                guard try LibXrayRuntime.isXrayRunning() else {
                    throw NSError(
                        domain: "PacketTunnel",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Xray 未进入运行状态"]
                    )
                }
                DispatchQueue.main.async {
                    self.reasserting = false
                    logger.info("Xray TUN 启动成功")
                    completionHandler(nil)
                }
            } catch {
                try? LibXrayRuntime.stop()
                DispatchQueue.main.async {
                    self.reasserting = false
                    logger.error("启动服务时发生错误: \(error.localizedDescription)")
                    completionHandler(error)
                }
            }
        }
    }

    /// 验证原始 JSON，并将扩展进程才能取得的运行时环境变量合并进配置。
    ///
    /// `xray.location.asset` 指向共享资源目录，`xray.tun.fd` 让 TUN 入站直接复用
    /// NetworkExtension 已创建的 utun，避免额外创建虚拟网卡。
    ///
    /// - Parameters:
    ///   - configurationJSON: 主 App 构建的 Xray JSON 配置。
    ///   - tunnelFileDescriptor: 当前扩展进程中的 utun 文件描述符。
    /// - Returns: 按键排序后的最终 JSON 字符串，便于稳定写盘和排查配置差异。
    /// - Throws: JSON 无效、缺少 TUN 入站、`env` 类型错误或重新序列化失败时抛出错误。
    private func makeRuntimeConfiguration(
        _ configurationJSON: String,
        tunnelFileDescriptor: Int32
    ) throws -> String {
        guard
            let configurationData = configurationJSON.data(using: .utf8),
            var configuration = try JSONSerialization.jsonObject(with: configurationData) as? [String: Any]
        else {
            throw NSError(
                domain: "PacketTunnel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Xray 配置不是有效 JSON"]
            )
        }

        let inbounds = configuration["inbounds"] as? [[String: Any]] ?? []
        guard inbounds.contains(where: {
            ($0["protocol"] as? String)?.lowercased() == "tun"
        }) else {
            throw NSError(
                domain: "PacketTunnel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Xray 配置缺少 TUN 入站"]
            )
        }

        var environment: [String: Any]
        if let existingEnvironment = configuration["env"] {
            guard let environmentDictionary = existingEnvironment as? [String: Any] else {
                throw NSError(
                    domain: "PacketTunnel",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Xray 配置 env 必须是对象"]
                )
            }
            environment = environmentDictionary
        } else {
            environment = [:]
        }
        environment["xray.location.asset"] = AppConstants.assetDirectoryURL.path
        environment["xray.tun.fd"] = String(tunnelFileDescriptor)
        configuration["env"] = environment

        let encodedConfiguration = try JSONSerialization.data(withJSONObject: configuration, options: [.sortedKeys])
        guard let runtimeConfigurationJSON = String(data: encodedConfiguration, encoding: .utf8) else {
            throw NSError(
                domain: "PacketTunnel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法序列化 Xray TUN 配置"]
            )
        }
        return runtimeConfigurationJSON
    }

    // MARK: - Tunnel File Descriptor

    /// 等待 NetworkExtension 创建 utun，并在约一秒内轮询其文件描述符。
    ///
    /// 首次立即检查；未找到时每 50 毫秒重试一次，最多重试 20 次。重试安排在主队列，
    /// 不会用同步等待阻塞 NetworkExtension 的启动回调线程。
    ///
    /// - Parameters:
    ///   - attempt: 当前重试次数，外部调用保持默认值 `0`。
    ///   - completion: 找到时返回文件描述符；超时后返回可展示的启动错误。
    private func findTunnelFileDescriptor(
        attempt: Int = 0,
        completion: @escaping @Sendable (Result<Int32, Error>) -> Void
    ) {
        if let fileDescriptor = findCurrentTunnelFileDescriptor() {
            completion(.success(fileDescriptor))
            return
        }
        guard attempt < 20 else {
            completion(
                .failure(
                    NSError(
                        domain: "PacketTunnel",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "无法取得 NetworkExtension TUN FD"]
                    )
                )
            )
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.findTunnelFileDescriptor(attempt: attempt + 1, completion: completion)
        }
    }

    /// 在当前进程已打开的描述符中查找 utun socket。
    ///
    /// 方法扫描 `0...1024`，使用 utun control socket 的 `getsockopt` 接口读取接口名，
    /// 并返回第一个名称以 `utun` 开头的描述符。无法识别任何 utun 时返回 `nil`。
    private func findCurrentTunnelFileDescriptor() -> Int32? {
        for fileDescriptor in Int32(0) ... Int32(1024) {
            var interfaceName = [CChar](repeating: 0, count: Int(IFNAMSIZ))
            var nameLength = socklen_t(interfaceName.count)
            let result = interfaceName.withUnsafeMutableBytes { buffer in
                getsockopt(
                    fileDescriptor,
                    2,
                    2,
                    buffer.baseAddress,
                    &nameLength
                )
            }
            guard result == 0 else { continue }
            let nameBytes = interfaceName.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            if String(decoding: nameBytes, as: UTF8.self).hasPrefix("utun") {
                return fileDescriptor
            }
        }
        return nil
    }

    // MARK: - 配置虚拟网卡

    /// 构建系统虚拟网卡、默认路由和 DNS 设置。
    ///
    /// IPv4 使用 `10.131.0.2/30`，IPv6 使用 `fd00:131::2/126`；两者都声明默认路由，
    /// 使系统 TCP/UDP 流量进入 utun。DNS 使用 Cloudflare 的 IPv4/IPv6 地址，空的
    /// `matchDomains` 条目表示所有域名都交给该 DNS 设置处理。
    ///
    /// - Returns: 可直接传给 `setTunnelNetworkSettings` 的完整网络设置。
    private func makeTunnelNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: tunnelMTU)

        // 将 IPv4 和 IPv6 默认路由交给 Packet Tunnel。
        settings.ipv4Settings = {
            let ipv4 = NEIPv4Settings(
                addresses: ["10.131.0.2"],
                subnetMasks: ["255.255.255.252"]
            )
            ipv4.includedRoutes = [NEIPv4Route.default()]
            return ipv4
        }()

        settings.ipv6Settings = {
            let ipv6 = NEIPv6Settings(
                addresses: ["fd00:131::2"],
                networkPrefixLengths: [126]
            )
            ipv6.includedRoutes = [NEIPv6Route.default()]
            return ipv6
        }()

        // 空匹配域表示所有域名都使用隧道 DNS。
        let dnsSettings = NEDNSSettings(servers: [
            "1.1.1.1", // Cloudflare DNS (IPv4)
            "2606:4700:4700::1111", // Cloudflare DNS (IPv6)
        ])
        dnsSettings.matchDomains = [""]

        settings.dnsSettings = dnsSettings

        return settings
    }
}
