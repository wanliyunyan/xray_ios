//
//  TrafficStatsView.swift
//  Xray
//
//  Created by pan on 2024/9/24.
//

import Foundation
import SwiftUI
import LibXray

struct TrafficStatsView: View {
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager // 监听 PacketTunnelManager 的状态
    @State private var downlinkTraffic: String = "0"  // 下行流量
    @State private var uplinkTraffic: String = "0"    // 上行流量

    @State private var base64TrafficString: String = ""  // 用于保存初始化时的 Base64 编码的 trafficString
    
//    @State private var alloc = 0
//    @State private var totalAlloc = 0
//    @State private var sys = 0
//    @State private var lookups = 0
//    @State private var mallocs = 0
//    @State private var frees = 0
//    @State private var heapAlloc = 0
//    @State private var heapSys = 0
//    @State private var heapIdle = 0
//    @State private var heapInuse = 0
//    @State private var heapReleased = 0
//    @State private var heapObjects = 0
//    @State private var stackInuse = 0
//    @State private var stackSys = 0
//    @State private var mspanInuse = 0
//    @State private var mspanSys = 0
//    @State private var mcacheInuse = 0
//    @State private var mcacheSys = 0
//    @State private var buckHashSys = 0
//    @State private var gcSys = 0
//    @State private var otherSys = 0
//    @State private var nextGC = 0
//    @State private var lastGC = 0
//    @State private var pauseTotalNs = 0
//    @State private var numGC = 0
//    @State private var numForcedGC = 0
//    @State private var gcCpuFraction = 0.0
//    @State private var enableGC = false
//    @State private var debugGC = false
    
    // 定时器：每秒执行一次
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("流量统计:").font(.headline)
            Text("下行流量: \(formatBytes(downlinkTraffic))") // 显示下行流量
            Text("上行流量: \(formatBytes(uplinkTraffic))")    // 显示上行流量

//            Text("内存统计 Memory Stats:").font(.headline)
//            Text("分配 Alloc: \(alloc)")
//            Text("总分配 Total Alloc: \(totalAlloc)")
//            Text("系统内存 Sys: \(sys)")
//            Text("查找次数 Lookups: \(lookups)")
//            Text("内存分配次数 Mallocs: \(mallocs)")
//            Text("释放内存次数 Frees: \(frees)")
//            Text("堆内存分配 Heap Alloc: \(heapAlloc)")
//            Text("堆系统内存 Heap Sys: \(heapSys)")
//            Text("堆闲置内存 Heap Idle: \(heapIdle)")
//            Text("堆使用内存 Heap Inuse: \(heapInuse)")
//            Text("堆释放内存 Heap Released: \(heapReleased)")
//            Text("堆对象数量 Heap Objects: \(heapObjects)")
//            Text("栈使用内存 Stack Inuse: \(stackInuse)")
//            Text("栈系统内存 Stack Sys: \(stackSys)")
//            Text("MSpan 使用内存 MSpan Inuse: \(mspanInuse)")
//            Text("MSpan 系统内存 MSpan Sys: \(mspanSys)")
//            Text("MCache 使用内存 MCache Inuse: \(mcacheInuse)")
//            Text("MCache 系统内存 MCache Sys: \(mcacheSys)")
//            Text("Buck Hash 系统内存 Buck Hash Sys: \(buckHashSys)")
//            Text("GC 系统内存 GC Sys: \(gcSys)")
//            Text("其他系统内存 Other Sys: \(otherSys)")
//            Text("下次 GC Next GC: \(nextGC)")
//            Text("最后 GC Last GC: \(lastGC)")
//            Text("GC 暂停总时间 Pause Total Ns: \(pauseTotalNs)")
//            Text("GC 次数 Num GC: \(numGC)")
//            Text("强制 GC 次数 Num Forced GC: \(numForcedGC)")
//            Text("GC CPU 占比 GCCPU Fraction: \(gcCpuFraction)")
//            Text("GC 启用 Enable GC: \(enableGC ? "是 Yes" : "否 No")")
//            Text("GC 调试启用 Debug GC: \(debugGC ? "是 Yes" : "否 No")")
        }
        .onAppear {
            do {
                try initializeTrafficString()  // 处理可能抛出的错误
            } catch {
                print("初始化流量字符串失败: \(error.localizedDescription)")
            }
        }
        .onReceive(timer) { _ in
            // 仅在 VPN 连接后获取流量统计
            if packetTunnelManager.status == .connected {
                updateTrafficStats()
                
            }
        }
    }
    
    // 初始化 trafficString 并进行 Base64 编码，仅执行一次
    private func initializeTrafficString() throws {
        
        guard let trafficPortString = Util.loadFromUserDefaults(key: "trafficPort"),
              let trafficPort = Int(trafficPortString) else {
            throw NSError(domain: "ConfigurationError", code: 0, userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"])
        }
        
        if let trafficString = "http://127.0.0.1:\(trafficPort)/debug/vars".data(using: .utf8) {
            base64TrafficString = trafficString.base64EncodedString()
        } else {
            print("字符串编码为 Data 失败")
        }
    }

    // 每秒执行一次的流量统计更新
    private func updateTrafficStats() {
        // 使用已保存的 base64TrafficString
        let res = LibXrayQueryStats(base64TrafficString)  // 获取 Xray 的流量统计

        // 解码 Base64 返回的数据
        if let decodedData = Data(base64Encoded: res) {
            // 尝试将解码后的 Data 转换为字符串（假设是文本或 JSON 字符串）
            if let decodedString = String(data: decodedData, encoding: .utf8) {
                parseXrayResponse(decodedString)
            } else {
                print("无法将数据转换为 UTF-8 字符串")
            }
        } else {
            print("Base64 解码失败")
        }
    }
    
    
    private func parseXrayResponse(_ response: String) {
        // 尝试将 JSON 字符串转换为字典
        guard let jsonData = response.data(using: .utf8) else {
            print("Failed to create jsonData from response string")
            return
        }
        
        do {
            // 将 JSON 数据转换为字典对象
            guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                print("JSON Object is not a dictionary")
                return
            }
            
            // 检查 success 字段是否为 1
            guard let success = jsonObject["success"] as? Int, success == 1 else {
                print("Parsing failed: success field is not 1")
                return
            }

            // 获取 data 字段并确保其为字符串
            guard let dataValue = jsonObject["data"] else {
                print("Data not found in jsonObject")
                return
            }
            
            // 如果 data 是字符串类型，尝试将其解析为 JSON
            guard let dataString = dataValue as? String else {
                print("Data is not a string")
                return
            }

            // 将字符串转换为 Data
            guard let nestedJsonData = dataString.data(using: .utf8) else {
                print("Failed to convert data string to Data")
                return
            }

            // 尝试将字符串中的 JSON 解析为字典
            guard let dataDict = try JSONSerialization.jsonObject(with: nestedJsonData, options: []) as? [String: Any] else {
                print("Failed to parse nested JSON in data string")
                return
            }

            // 读取 stats 对象
            guard let stats = dataDict["stats"] as? [String: Any],
                  let inbound = stats["inbound"] as? [String: Any],
                  let socks = inbound["socks"] as? [String: Any] else {
                print("Stats, inbound not found in dataDict")
                return
            }

//            // 在解析 JSON 后更新这些变量的值
//            if let memstats = dataDict["memstats"] as? [String: Any] {
//                alloc = memstats["Alloc"] as? Int ?? 0
//                totalAlloc = memstats["TotalAlloc"] as? Int ?? 0
//                sys = memstats["Sys"] as? Int ?? 0
//                lookups = memstats["Lookups"] as? Int ?? 0
//                mallocs = memstats["Mallocs"] as? Int ?? 0
//                frees = memstats["Frees"] as? Int ?? 0
//                heapAlloc = memstats["HeapAlloc"] as? Int ?? 0
//                heapSys = memstats["HeapSys"] as? Int ?? 0
//                heapIdle = memstats["HeapIdle"] as? Int ?? 0
//                heapInuse = memstats["HeapInuse"] as? Int ?? 0
//                heapReleased = memstats["HeapReleased"] as? Int ?? 0
//                heapObjects = memstats["HeapObjects"] as? Int ?? 0
//                stackInuse = memstats["StackInuse"] as? Int ?? 0
//                stackSys = memstats["StackSys"] as? Int ?? 0
//                mspanInuse = memstats["MSpanInuse"] as? Int ?? 0
//                mspanSys = memstats["MSpanSys"] as? Int ?? 0
//                mcacheInuse = memstats["MCacheInuse"] as? Int ?? 0
//                mcacheSys = memstats["MCacheSys"] as? Int ?? 0
//                buckHashSys = memstats["BuckHashSys"] as? Int ?? 0
//                gcSys = memstats["GCSys"] as? Int ?? 0
//                otherSys = memstats["OtherSys"] as? Int ?? 0
//                nextGC = memstats["NextGC"] as? Int ?? 0
//                lastGC = memstats["LastGC"] as? Int ?? 0
//                pauseTotalNs = memstats["PauseTotalNs"] as? Int ?? 0
//                numGC = memstats["NumGC"] as? Int ?? 0
//                numForcedGC = memstats["NumForcedGC"] as? Int ?? 0
//                gcCpuFraction = memstats["GCCPUFraction"] as? Double ?? 0.0
//                enableGC = memstats["EnableGC"] as? Bool ?? false
//                debugGC = memstats["DebugGC"] as? Bool ?? false
//            }
            
            // 获取 socks 的下行和上行流量
            guard let socksDownlink = socks["downlink"] as? Int,
                  let socksUplink = socks["uplink"] as? Int else {
                print("Socks downlink or uplink not found")
                return
            }

            downlinkTraffic = String(socksDownlink)
            uplinkTraffic = String(socksUplink)

        } catch {
            print("Error parsing JSON: \(error)")
        }
    }
    
    // 将字节转换为 MB 或 GB
    private func formatBytes(_ bytesString: String) -> String {
        guard let bytes = Double(bytesString) else { return "0 bytes" }
        
        let kilobyte = 1024.0
        let megabyte = kilobyte * 1024
        let gigabyte = megabyte * 1024
        
        if bytes >= gigabyte {
            return String(format: "%.2f GB", bytes / gigabyte)
        } else if bytes >= megabyte {
            return String(format: "%.2f MB", bytes / megabyte)
        } else if bytes >= kilobyte {
            return String(format: "%.2f KB", bytes / kilobyte)
        } else {
            return "\(Int(bytes)) bytes"
        }
    }
}
