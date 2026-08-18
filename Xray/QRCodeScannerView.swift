//
//  QRCodeScannerView.swift
//  Xray
//
//  Created by pan on 2024/10/11.
//

@preconcurrency import AVFoundation
import AudioToolbox
import SwiftUI
import UIKit

/// 根据相机权限展示二维码扫描器或可恢复的权限提示。
struct QRCodeScannerView: View {
    @Binding var scannedCode: String?

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isCameraUnavailable = false

    var body: some View {
        Group {
            switch authorizationStatus {
            case .authorized:
                if isCameraUnavailable {
                    cameraUnavailableView
                } else {
                    QRCodeCameraView(
                        scannedCode: $scannedCode,
                        isCameraUnavailable: $isCameraUnavailable
                    )
                    .ignoresSafeArea()
                }

            case .notDetermined:
                ProgressView("正在请求相机权限...")

            case .denied, .restricted:
                permissionUnavailableView

            @unknown default:
                cameraUnavailableView
            }
        }
        .task {
            await requestCameraAccessIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            refreshAuthorizationStatus()
        }
    }

    private var permissionUnavailableView: some View {
        ContentUnavailableView {
            Label("无法使用相机", systemImage: "camera.fill")
        } description: {
            Text("请在系统设置中允许 Xray 使用相机后再扫描二维码。")
        } actions: {
            Button("打开设置", systemImage: "gear") {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var cameraUnavailableView: some View {
        ContentUnavailableView(
            "相机不可用",
            systemImage: "camera.fill",
            description: Text("无法创建二维码扫描会话，请检查相机是否正在被其他应用使用。")
        )
    }

    private func requestCameraAccessIfNeeded() async {
        guard authorizationStatus == .notDetermined else {
            return
        }

        _ = await AVCaptureDevice.requestAccess(for: .video)
        guard !Task.isCancelled else {
            return
        }
        refreshAuthorizationStatus()
    }

    private func refreshAuthorizationStatus() {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authorizationStatus != currentStatus else {
            return
        }
        authorizationStatus = currentStatus
        if currentStatus == .authorized {
            isCameraUnavailable = false
        }
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(settingsURL)
    }
}

/// 将已经授权的 AVFoundation 二维码捕捉会话桥接到 SwiftUI。
private struct QRCodeCameraView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?
    @Binding var isCameraUnavailable: Bool

    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRCodeCameraView

        private let sessionQueue = DispatchQueue(
            label: "com.ymwl.xray.qr-session",
            qos: .userInitiated
        )
        private var captureSession: AVCaptureSession?

        init(parent: QRCodeCameraView) {
            self.parent = parent
        }

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection
        ) {
            guard let metadataObject = metadataObjects.first,
                  let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue,
                  parent.scannedCode == nil
            else {
                return
            }

            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            parent.scannedCode = stringValue
            stopSession()
        }

        func startSession(_ captureSession: AVCaptureSession) {
            self.captureSession = captureSession
            sessionQueue.async {
                guard !captureSession.isRunning else {
                    return
                }
                captureSession.startRunning()
            }
        }

        func stopSession() {
            guard let captureSession else {
                return
            }
            self.captureSession = nil
            sessionQueue.async {
                guard captureSession.isRunning else {
                    return
                }
                captureSession.stopRunning()
            }
        }

        func reportCameraUnavailable() {
            guard !parent.isCameraUnavailable else {
                return
            }
            parent.isCameraUnavailable = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        let viewController = QRCodeScannerViewController()
        guard let captureSession = makeCaptureSession(coordinator: context.coordinator) else {
            Task { @MainActor in
                context.coordinator.reportCameraUnavailable()
            }
            return viewController
        }

        viewController.installPreview(for: captureSession)
        context.coordinator.startSession(captureSession)
        return viewController
    }

    func updateUIViewController(_: QRCodeScannerViewController, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIViewController(
        _: QRCodeScannerViewController,
        coordinator: Coordinator
    ) {
        coordinator.stopSession()
    }

    private func makeCaptureSession(coordinator: Coordinator) -> AVCaptureSession? {
        let captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession.canAddInput(videoInput)
        else {
            return nil
        }
        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            return nil
        }
        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(coordinator, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        return captureSession
    }
}

/// 持有预览层，并在旋转或尺寸变化后同步更新画面范围。
private final class QRCodeScannerViewController: UIViewController {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func installPreview(for captureSession: AVCaptureSession) {
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}
