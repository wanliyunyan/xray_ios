//
//  QRCodeScannerView.swift
//  Xray
//
//  Created by pan on 2024/10/11.
//

@preconcurrency import AVFoundation
import SwiftUI

/// 一个 SwiftUI 视图，用于扫描二维码并将扫描结果通过 `scannedCode` 传递出去。
struct QRCodeScannerView: UIViewControllerRepresentable {
    // MARK: - 属性

    /// 绑定属性，用于存储扫描到的二维码内容。当二维码扫描成功后会更新此属性。
    @Binding var scannedCode: String?

    // MARK: - Coordinator

    /// 用于协调二维码扫描的类，负责处理元数据输出的回调。
    class Coordinator: NSObject, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
        /// 父视图，便于在回调中访问和更新 `scannedCode`。
        var parent: QRCodeScannerView

        /// 初始化函数。
        /// - Parameter parent: 父 `QRCodeScannerView` 实例。
        init(parent: QRCodeScannerView) {
            self.parent = parent
        }

        /// 当捕捉到元数据（如二维码）时被调用的回调方法。
        /// - Parameters:
        ///   - output: 元数据输出对象（此处用不到可以忽略）。
        ///   - metadataObjects: 捕捉到的元数据对象数组。
        ///   - connection: 捕捉连接对象（此处用不到可以忽略）。
        @MainActor func metadataOutput(_: AVCaptureMetadataOutput,
                                       didOutput metadataObjects: [AVMetadataObject],
                                       from _: AVCaptureConnection)
        {
            // 若检测到元数据，获取第一个有效对象
            guard let metadataObject = metadataObjects.first,
                  let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue
            else {
                return
            }

            // 扫描到二维码后，震动提示
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

            // 更新扫描结果
            DispatchQueue.main.async {
                self.parent.scannedCode = stringValue
            }
        }
    }

    // MARK: - UIViewControllerRepresentable 协议实现

    /// 创建协调器实例。
    /// - Returns: `Coordinator` 实例。
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 创建并返回用于展示二维码扫描界面的 `UIViewController`。
    /// - Parameter context: 上下文环境对象，提供 `Coordinator` 等信息。
    /// - Returns: 一个用于展示摄像头预览并进行二维码扫描的 `UIViewController` 实例。
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()

        // 1. 检查相机权限
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            // 如果尚未请求权限，则请求一次
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        // 再次初始化扫描界面
                        _ = setupScanner(on: viewController, coordinator: context.coordinator)
                    } else {
                        // 权限被拒绝，您可以在此处进行 UI 提示
                    }
                }
            }
        case .authorized:
            // 已授权，直接设置扫描功能
            setupScanner(on: viewController, coordinator: context.coordinator)
        case .denied, .restricted:
            // 权限被拒绝或受限制，您可以在此处进行 UI 提示
            break
        @unknown default:
            break
        }

        return viewController
    }

    /// 更新 `UIViewController` 时调用，此处无额外操作。
    /// - Parameters:
    ///   - uiViewController: 将要更新的 `UIViewController` 实例。
    ///   - context: 上下文环境对象。
    func updateUIViewController(_: UIViewController, context _: Context) {
        // 在这里可以根据需要对界面进行更新
    }

    // MARK: - 私有辅助方法

    /// 配置二维码扫描相关的捕捉会话和预览图层。
    /// - Parameters:
    ///   - viewController: 需要添加摄像头预览图层和进行会话配置的视图控制器。
    ///   - coordinator: 用于处理元数据输出回调的协调器。
    /// - Returns: 若成功配置则返回 `UIViewController`，否则返回空。
    @discardableResult
    private func setupScanner(on viewController: UIViewController,
                              coordinator: Coordinator) -> UIViewController?
    {
        // 创建捕捉会话
        let captureSession = AVCaptureSession()

        // 获取默认的视频捕捉设备（后置摄像头）
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            return nil
        }

        // 尝试将捕捉设备作为输入添加到会话中
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
        } catch {
            // 如果添加输入失败，可以在此处处理错误（例如提示用户或记录日志）
            return nil
        }

        // 创建元数据输出并设置代理，用于捕获二维码数据
        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(coordinator, queue: DispatchQueue.main)
            // 仅扫描二维码（如果需要支持其他条码可自行添加）
            metadataOutput.metadataObjectTypes = [.qr]
        }

        // 创建预览图层，用于显示摄像头捕捉到的内容
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = viewController.view.bounds

        // 将预览图层添加到视图控制器的视图上
        viewController.view.layer.addSublayer(previewLayer)

        // 在后台线程启动会话，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            // 启动会话
            captureSession.startRunning()
        }

        return viewController
    }
}
