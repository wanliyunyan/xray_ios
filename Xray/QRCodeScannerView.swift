//
//  QRCodeScannerView.swift
//  Xray
//
//  Created by pan on 2024/10/11.
//

@preconcurrency import AVFoundation
import SwiftUI

/// 将 AVFoundation 二维码扫描器桥接为 SwiftUI 视图。
///
/// 视图负责检查或请求相机权限、建立捕捉会话、显示后置摄像头预览，并把首个识别到的
/// 二维码字符串写入 `scannedCode`。父视图监听绑定变化后保存配置并关闭 Sheet。
struct QRCodeScannerView: UIViewControllerRepresentable {
    /// 扫描结果绑定；识别成功后写入二维码的原始字符串。
    @Binding var scannedCode: String?

    // MARK: - Coordinator

    /// 将 AVFoundation 元数据回调桥接回 SwiftUI 绑定。
    ///
    /// `AVCaptureMetadataOutputObjectsDelegate` 由 UIKit/AVFoundation 持有，Coordinator
    /// 保存父 Representable 值，以便回调时更新 `scannedCode`。
    class Coordinator: NSObject, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
        /// 当前 SwiftUI Representable 值，包含扫描结果绑定。
        var parent: QRCodeScannerView

        /// 创建回调协调器。
        /// - Parameter parent: 创建 Coordinator 的二维码扫描视图。
        init(parent: QRCodeScannerView) {
            self.parent = parent
        }

        /// 处理捕捉会话输出的二维码元数据。
        ///
        /// 方法只读取数组中的第一个对象，并要求它可转换为
        /// `AVMetadataMachineReadableCodeObject` 且包含字符串。成功后触发系统振动，并在主队列
        /// 更新 SwiftUI 绑定；无有效内容时直接忽略本次回调。
        ///
        /// - Parameters:
        ///   - output: AVFoundation 元数据输出，本实现不需要读取。
        ///   - metadataObjects: 当前帧识别出的元数据对象。
        ///   - connection: 产生回调的捕捉连接，本实现不需要读取。
        @MainActor func metadataOutput(_: AVCaptureMetadataOutput,
                                       didOutput metadataObjects: [AVMetadataObject],
                                       from _: AVCaptureConnection)
        {
            guard let metadataObject = metadataObjects.first,
                  let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue
            else {
                return
            }

            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

            DispatchQueue.main.async {
                self.parent.scannedCode = stringValue
            }
        }
    }

    // MARK: - UIViewControllerRepresentable

    /// 创建 AVFoundation 代理使用的 Coordinator。
    /// - Returns: 持有当前扫描结果绑定的协调器。
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 创建摄像头预览控制器，并根据当前授权状态初始化扫描器。
    ///
    /// 授权状态处理：
    /// - `.notDetermined`：请求相机权限，允许后在主队列配置捕捉会话；
    /// - `.authorized`：立即配置扫描器；
    /// - `.denied/.restricted`：保持空白控制器，不启动摄像头；
    /// - 未知新状态：同样保持空白，避免错误访问硬件。
    ///
    /// - Parameter context: SwiftUI 提供的上下文，用于取得 Coordinator。
    /// - Returns: 承载摄像头预览层的 `UIViewController`。
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        _ = setupScanner(on: viewController, coordinator: context.coordinator)
                    } else {
                        // 未授权时保留空白预览，不尝试创建 AVCaptureDeviceInput。
                    }
                }
            }
        case .authorized:
            setupScanner(on: viewController, coordinator: context.coordinator)
        case .denied, .restricted:
            break
        @unknown default:
            break
        }

        return viewController
    }

    /// SwiftUI 状态更新不需要修改底层控制器；捕捉会话由创建阶段持续运行。
    func updateUIViewController(_: UIViewController, context _: Context) {
    }

    // MARK: - Scanner Setup

    /// 配置二维码捕捉会话和摄像头预览层。
    ///
    /// 完整流程：
    /// 1. 创建 `AVCaptureSession` 并取得默认视频设备；
    /// 2. 创建摄像头输入，在 Session 支持时加入；
    /// 3. 创建元数据输出，把代理设为 Coordinator，并限定只识别 `.qr`；
    /// 4. 创建填充控制器边界的 `AVCaptureVideoPreviewLayer`；
    /// 5. 在后台队列启动会话，避免阻塞主线程。
    ///
    /// - Parameters:
    ///   - viewController: 需要承载摄像头预览层的控制器。
    ///   - coordinator: 接收二维码元数据并回写 SwiftUI 绑定的协调器。
    /// - Returns: 配置成功时返回传入控制器；摄像头不可用或输入创建失败时返回 `nil`。
    @discardableResult
    private func setupScanner(on viewController: UIViewController,
                              coordinator: Coordinator) -> UIViewController?
    {
        let captureSession = AVCaptureSession()

        // 使用系统默认视频设备，通常对应后置摄像头。
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            return nil
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
        } catch {
            return nil
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            // 元数据回调在主队列执行，保证可以直接协调 SwiftUI 状态。
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(coordinator, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        // 裁剪填充整个控制器，避免预览出现黑边。
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = viewController.view.bounds

        viewController.view.layer.addSublayer(previewLayer)

        // 启动会话可能阻塞，放到用户交互优先级的后台队列。
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }

        return viewController
    }
}
