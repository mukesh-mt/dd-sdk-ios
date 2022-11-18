/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import SwiftUI
import Charts

// https://github.com/beltex/SystemKit/blob/master/SystemKit/System.swift

struct StatsView: View {

    @Environment(\.presentationMode) var presentationMode

    @ObservedObject var memoryUsageProvider: MemoryUsageProvider
    @ObservedObject var cpuUsageProvider: CPUUsageProvider
    @ObservedObject var diskUsageProvider: DiskUsageProvider

    var body: some View {
        TabView {
            NavigationView {
                VStack(alignment: .leading) {
                    ScrollView {
                        if #available(iOS 16.0, *) {
                            Text("Memory Consumption")
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

                            Text("CPU Usage")
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
                            Text("Files in Caches")
                                .foregroundColor(.secondary)

                            Chart {
                                ForEach(Array(diskUsageProvider.history.enumerated()), id: \.offset) { index, element in
                                    AreaMark(
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
        }
        .tint(.purple)
    }
}

import Combine

class MemoryUsageProvider: ObservableObject {
    private var assignCancellable: AnyCancellable? = nil

    @Published var history = [Float]()

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
        let usedMb = Float(taskInfo.phys_footprint) / 1048576.0
        return usedMb
        let totalMb = Float(ProcessInfo.processInfo.physicalMemory) / 1048576.0
        return result != KERN_SUCCESS ? totalMb : usedMb/totalMb
    }
}

class CPUUsageProvider: ObservableObject {
    private var assignCancellable: AnyCancellable? = nil

    @Published var history = [Double]()

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
        var kr: kern_return_t
        var task_info_count: mach_msg_type_number_t

        task_info_count = mach_msg_type_number_t(TASK_INFO_MAX)
        var tinfo = [integer_t](repeating: 0, count: Int(task_info_count))

        kr = task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), &tinfo, &task_info_count)
        if kr != KERN_SUCCESS {
            return -1
        }

        var thread_list: thread_act_array_t? = UnsafeMutablePointer(mutating: [thread_act_t]())
        var thread_count: mach_msg_type_number_t = 0
        defer {
            if let thread_list = thread_list {
                vm_deallocate(mach_task_self_, vm_address_t(UnsafePointer(thread_list).pointee), vm_size_t(thread_count))
            }
        }

        kr = task_threads(mach_task_self_, &thread_list, &thread_count)

        if kr != KERN_SUCCESS {
            return -1
        }

        var tot_cpu: Double = 0

        if let thread_list = thread_list {

            for j in 0 ..< Int(thread_count) {
                var thread_info_count = mach_msg_type_number_t(THREAD_INFO_MAX)
                var thinfo = [integer_t](repeating: 0, count: Int(thread_info_count))
                kr = thread_info(thread_list[j], thread_flavor_t(THREAD_BASIC_INFO),
                                 &thinfo, &thread_info_count)
                if kr != KERN_SUCCESS {
                    return -1
                }

                let threadBasicInfo = convertThreadInfoToThreadBasicInfo(thinfo)

                if threadBasicInfo.flags != TH_FLAGS_IDLE {
                    tot_cpu += (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            } // for each thread
        }

        return tot_cpu
    }

    fileprivate func convertThreadInfoToThreadBasicInfo(_ threadInfo: [integer_t]) -> thread_basic_info {
        var result = thread_basic_info()

        result.user_time = time_value_t(seconds: threadInfo[0], microseconds: threadInfo[1])
        result.system_time = time_value_t(seconds: threadInfo[2], microseconds: threadInfo[3])
        result.cpu_usage = threadInfo[4]
        result.policy = threadInfo[5]
        result.run_state = threadInfo[6]
        result.flags = threadInfo[7]
        result.suspend_count = threadInfo[8]
        result.sleep_time = threadInfo[9]

        return result
    }
}

class DiskUsageProvider: ObservableObject {
    private var assignCancellable: AnyCancellable? = nil

    @Published var history = [Int]()

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

    func reportMemory() -> Int {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

        var files = [URL]()
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                do {
                    let fileAttributes = try fileURL.resourceValues(forKeys:[.isRegularFileKey])
                    if fileAttributes.isRegularFile! {
                        files.append(fileURL)
                    }
                } catch { print(error, fileURL) }
            }
        }

        return files.count
    }
}


