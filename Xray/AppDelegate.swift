//
//  AppDelegate.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 请求通知授权，不需要放在后台线程，因为方法本身是异步的
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error = error {
                print("通知授权请求失败: \(error.localizedDescription)")
            }
            // 在主线程设置代理
            DispatchQueue.main.async {
                UNUserNotificationCenter.current().delegate = self
            }
        }
        return true
    }
    
    // 当应用在前台时接收到通知时调用
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }
}
