/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog
import Foundation
import SwiftUI
import Charts

// https://github.com/beltex/SystemKit/blob/master/SystemKit/System.swift

struct StatsView: View {

    @Environment(\.presentationMode) var presentationMode

    @ObservedObject var memoryUsageProvider: MemoryUsageProvider
    @ObservedObject var cpuUsageProvider: CPUUsageProvider
    @ObservedObject var diskUsageProvider: DiskUsageProvider

    var config: Datadog.Configuration

    var body: some View {
        TabView {
            NavigationView {
                VStack(alignment: .leading) {
                    ScrollView {
                        if #available(iOS 16.0, *) {
                            Text(String(format: "Memory Consumption %.2f MB", memoryUsageProvider.history.last ?? 0))
                                .foregroundColor(.secondary)

                            Chart {
                                ForEach(Array(memoryUsageProvider.history.enumerated()), id: \.offset) { index, element in
                                    AreaMark(
                                        x: .value("Time", index),
                                        y: .value("MB", element)
                                    )
                                }
                                .interpolationMethod(.cardinal)
                            }
                            .animation(.easeInOut, value: memoryUsageProvider.history)
                            .foregroundColor(.teal.opacity(0.8))
                            .frame(height: 200)

                            Spacer()

                            Text(String(format: "CPU Usage %.2f%%", cpuUsageProvider.history.last ?? 0))
                                .foregroundColor(.secondary)

                            Chart {
                                ForEach(Array(cpuUsageProvider.history.enumerated()), id: \.offset) { index, element in
                                    AreaMark(
                                        x: .value("Time", index),
                                        y: .value("%", element),
                                        stacking: .unstacked
                                    )
                                }
                                .interpolationMethod(.cardinal)
                                .foregroundStyle(.yellow.opacity(0.8))

                            }
                            .animation(.easeInOut, value: cpuUsageProvider.history)
                            .frame(height: 200)
                        }
                    }
                }
                .padding()
                .navigationBarTitleDisplayMode(.large)
                .navigationTitle("App Performance")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .tabItem {
                Label("App", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationView {
                VStack(alignment: .leading) {
                    ScrollView {
                        if #available(iOS 16.0, *) {
                            Text("Session Replay files in Caches")
                                .foregroundColor(.secondary)

                            Chart {
                                ForEach(Array(diskUsageProvider.history.enumerated()), id: \.offset) { index, element in
                                    PointMark(
                                        x: .value("Time", index),
                                        y: .value("Count", element)
                                    )
                                }
                                .interpolationMethod(.cardinal)
                            }
                            .animation(.easeInOut, value: diskUsageProvider.history)
                            .foregroundColor(.teal.opacity(0.8))
                            .frame(height: 200)

                            Spacer()
                        }
                    }
                }
                .padding()
                .navigationBarTitleDisplayMode(.large)
                .navigationTitle("Core Performance")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .tabItem {
                Label("Core", systemImage: "externaldrive")
            }

            InfoView(config: config)
                .tabItem {
                    Label("Config Info", systemImage: "info.circle")
                }
        }
        .tint(.purple)
    }
}

import Combine

class MemoryUsageProvider: ObservableObject {
    private var assignCancellable: AnyCancellable? = nil

    @Published var history = CappedCollection<Float>(maxCount: 120)

    init() {
        assignCancellable = Timer.publish(every: 1.0, on: .main, in: .default)
            .autoconnect()
            .map { [unowned self] _ in
                self.reportMemory()
            }
            .sink(receiveValue: { [unowned self] in
                self.history.append($0)
            })
    }

    func reportMemory() -> Float {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let result: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        var used: UInt64 = 0
        if result == KERN_SUCCESS {
            used = UInt64(taskInfo.phys_footprint)
        }
        return  Float(used) / 1048576.0
    }
}

class CPUUsageProvider: ObservableObject {
    private var assignCancellable: AnyCancellable? = nil

    @Published var history = CappedCollection<Double>(maxCount: 120)

    init() {
        assignCancellable = Timer.publish(every: 1.0, on: .main, in: .default)
            .autoconnect()
            .compactMap { [unowned self] _ in
                self.cpuUsage()
            }
            .sink(receiveValue: { [unowned self] in
                self.history.append($0)
            })
    }

    fileprivate func cpuUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsList) {
            return $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }

        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }

                guard infoResult == KERN_SUCCESS else {
                    break
                }

                let threadBasicInfo = threadInfo as thread_basic_info
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU = (totalUsageOfCPU + (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0))
                }
            }
        }

        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        return totalUsageOfCPU
    }
}

class DiskUsageProvider: ObservableObject {
    private var assignCancellable: AnyCancellable? = nil

    @Published var history = CappedCollection<Int>(maxCount: 120)

    init() {
        assignCancellable = Timer.publish(every: 1.0, on: .main, in: .default)
            .autoconnect()
            .map { [unowned self] _ in
                self.reportSessionReplayFilesInCaches()
            }
            .sink(receiveValue: { [unowned self] in
                self.history.append($0)
            })
    }

    func reportSessionReplayFilesInCaches() -> Int {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

        var files = [URL]()
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                do {
                    let fileAttributes = try fileURL.resourceValues(forKeys:[.isRegularFileKey])
                    if fileAttributes.isRegularFile == true
                        && !fileURL.absoluteString.contains("apple")
                        && !fileURL.absoluteString.contains("fsCachedData")
                        && !fileURL.absoluteString.contains(".db")
                        && fileURL.absoluteString.contains("session-replay") {
                        files.append(fileURL)
                    }
                } catch { print(error, fileURL) }
            }
        }
        return files.count
    }
}


