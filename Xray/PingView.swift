//
//  PingvVew.swift
//  Xray
//
//  Created by pan on 2024/9/30.
//

import Foundation
import SwiftUI
import Combine
import LibXray

struct PingView: View {
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager // 引入 PacketTunnelManager
    @State private var pingSpeed: Int = 0
    @State private var isPingFetched: Bool = false // 全局变量，初始为 false

    var body: some View {
        VStack {
            // 显示 Ping 信息
            if isPingFetched  {
                HStack {
                    Text("Ping网速:")
                    Text("\(pingSpeed)").foregroundColor(pingSpeedColor(pingSpeed)).font(.headline)
                    Text("ms").foregroundColor(.black) //
                }
            } else {
                if(packetTunnelManager.status == .disconnected){
                    Text("点击获取网速")
                        .foregroundColor(.blue)
                        .onTapGesture {
                            requestPing() // 点击时调用 requestPing
                        }
                }
                
            }
        }
        .padding(.top, 10)
    }

    // Ping 请求逻辑
    private func requestPing() {
        do {
            guard let savedContent = Util.loadFromUserDefaults(key: "clipboardContent"), !savedContent.isEmpty else {
                throw NSError(domain: "ContentView", code: 0, userInfo: [NSLocalizedDescriptionKey: "没有可用的配置，且剪贴板内容为空"])
            }

            let configData = try Configuration().buildConfigurationData(config: savedContent)

            guard let mergedConfigString = String(data: configData, encoding: .utf8) else {
                throw NSError(domain: "ConfigDataError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"])
            }

            let fileUrl = try Util.createConfigFile(with: mergedConfigString)
                    
            guard let sock5PortString = Util.loadFromUserDefaults(key: "sock5Port"),
                  let sock5PortString = Int(sock5PortString) else {
                throw NSError(domain: "ConfigurationError", code: 0, userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"])
            }
            
            // 创建并发送 Ping 请求
            let pingRequest = try createPingRequest(configPath: fileUrl.path(), sock5Port: sock5PortString)
            let pingBase64String = try JSONEncoder().encode(pingRequest).base64EncodedString()
            
            // 调用 LibXrayPing 并处理响应
            let pingResponseBase64 = LibXrayPing(pingBase64String)
            if let pingResult = decodePingResponse(base64String: pingResponseBase64) {
                self.pingSpeed = pingResult
                self.isPingFetched = true
            } else {
                print("Ping 解码失败")
            }
        } catch let error as NSError {
            print("Ping 请求失败: \(error.localizedDescription)")
        } catch {
            print("发生了未知错误: \(error.localizedDescription)")
        }
    }

    // 根据 pingSpeed 值返回对应的颜色
    private func pingSpeedColor(_ pingSpeed: Int) -> Color {
        if pingSpeed == 0 {
            return .black
        }
        switch pingSpeed {
        case ..<1000:
            return .green
        case 1000..<5000:
            return .yellow
        default:
            return .red
        }
    }

    // 创建 Ping 请求
    private func createPingRequest(configPath: String, sock5Port: Int) throws -> PingRequest {
        return PingRequest(
            datDir: Constant.assetDirectory.path,
            configPath: configPath,
            timeout: 30,
            url: "https://www.google.com",
            proxy: "socks5://127.0.0.1:\(sock5Port)"
        )
    }

    // 解码 Base64 响应并提取 "data" 字段中的网速
    private func decodePingResponse(base64String: String) -> Int? {
        guard let decodedData = Data(base64Encoded: base64String),
              let decodedString = String(data: decodedData, encoding: .utf8),
              let jsonData = decodedString.data(using: .utf8) else {
            print("Base64 解码或转换为 JSON 失败")
            return nil
        }

        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
               let success = jsonObject["success"] as? Bool, success,
               let data = jsonObject["data"] as? Int {
                return data
            }
        } catch {
            print("解析 JSON 失败: \(error.localizedDescription)")
        }

        return nil
    }
}
