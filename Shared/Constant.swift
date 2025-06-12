//
//  Constant.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import Foundation
import Network

public enum Constant {
    public static let packageName = Bundle.main.infoDictionary?["APP_ID"] as? String ?? "unknown"
}

public extension Constant {
    static let groupName = "group.\(Constant.packageName)"
    static let tunnelName = "\(Constant.packageName).PacketTunnel"
    static let socks5Port: NWEndpoint.Port = 10808
    static let trafficPort: NWEndpoint.Port = 49227

    private static func createDirectory(at url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) == false else {
            return url
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            fatalError(error.localizedDescription)
        }
        return url
    }

    static let homeDirectory: URL = {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName) else {
            fatalError("无法加载共享文件路径")
        }
        let url = containerURL.appendingPathComponent("Library/Application Support/Xray")
        return createDirectory(at: url)
    }()

    static let assetDirectory = createDirectory(at: homeDirectory.appending(component: "assets", directoryHint: .isDirectory))

    static let configDirectory = createDirectory(at: homeDirectory.appending(component: "configs", directoryHint: .isDirectory))
}
