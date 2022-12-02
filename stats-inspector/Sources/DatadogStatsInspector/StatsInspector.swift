/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog
import Foundation
import UIKit
import SwiftUI

public struct StatsInspector {
    @discardableResult
    public static func initialize(
        config: Datadog.Configuration
    ) -> StatsInspectorController {
        return StatsInspectorController(config: config)
    }
}

public class StatsInspectorController {
    let memoryUsageProvider = MemoryUsageProvider()
    let cpuUsageProvider = CPUUsageProvider()
    let diskUsageProvider = DiskUsageProvider()

    let config: Datadog.Configuration

    init(config: Datadog.Configuration) {
        self.config = config
    }

    public func enableShareGesture() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didShake),
            name: UIDevice.deviceDidShakeNotification,
            object: nil
        )
    }

    @objc public func didShake() {
        let vc = UIHostingController(
            rootView: StatsView(
                memoryUsageProvider: memoryUsageProvider,
                cpuUsageProvider: cpuUsageProvider,
                diskUsageProvider: diskUsageProvider,
                config: config
            )
        )
        let keyWindow = UIApplication
            .shared
            .connectedScenes
            .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
            .first { $0.isKeyWindow }

        if var topController = keyWindow?.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            if topController is UIHostingController<StatsView> == false {
                topController.present(vc, animated: true)
            }
        }
    }
}

extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name(rawValue: "Datadog.StatsInspector.DeviceDidShakeNotification")
}

//  Override the default behavior of shake gestures to send our notification instead.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}
