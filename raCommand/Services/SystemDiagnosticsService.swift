//
//  SystemDiagnosticsService.swift
//  raCommand
//
//  Local, on-device system diagnostics: boot-volume free space, a size/
//  staleness breakdown of the local dev folder, and live CPU/memory
//  sampling. No network calls, no background execution — everything here
//  only runs while a view that asks for it is on screen.
//

import Foundation
#if os(macOS)
import Darwin
#endif

struct DiskSummary {
    let totalBytes: Int64
    let freeBytes: Int64

    var usedBytes: Int64 { max(totalBytes - freeBytes, 0) }
    var freeFraction: Double { totalBytes > 0 ? Double(freeBytes) / Double(totalBytes) : 0 }
}

struct LocalFolderUsage: Identifiable, Hashable {
    let path: String
    let name: String
    let sizeBytes: Int64

    var id: String { path }
}

struct SystemLoadSnapshot {
    let cpuUsagePercent: Double?
    let usedMemoryBytes: Int64
    let totalMemoryBytes: Int64

    var memoryFraction: Double {
        totalMemoryBytes > 0 ? Double(usedMemoryBytes) / Double(totalMemoryBytes) : 0
    }
}

enum SystemDiagnosticsService {
    static func diskSummary(volumePath: String = NSHomeDirectory()) -> DiskSummary? {
        let url = URL(fileURLWithPath: volumePath)
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacity else {
            return nil
        }
        return DiskSummary(totalBytes: Int64(total), freeBytes: Int64(free))
    }

    /// Scans the immediate subdirectories of `root` (each one a project
    /// folder) and computes their on-disk size. Runs off the main actor —
    /// this walks every file under repos like node_modules, so it can take
    /// a few seconds on a large local-dev tree.
    static func scanLocalDevFolders(root: String) async -> [LocalFolderUsage] {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            guard let entries = try? fm.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var results: [LocalFolderUsage] = []
            for entry in entries {
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDirectory else { continue }
                let size = directorySize(at: entry)
                results.append(LocalFolderUsage(path: entry.path, name: entry.lastPathComponent, sizeBytes: size))
            }
            return results.sorted { $0.sizeBytes > $1.sizeBytes }
        }.value
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  values.isDirectory != true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

#if os(macOS)
    /// Wraps the two Mach `host_statistics` calls needed for a CPU delta
    /// and a memory snapshot. CPU is cumulative-since-boot ticks, so two
    /// samples with `delta(from:)` are needed to get an instantaneous %.
    final class LoadSampler {
        private var previousTicks: host_cpu_load_info?

        func sample() -> SystemLoadSnapshot {
            let ticks = Self.readCPUTicks()
            let cpuPercent: Double?
            if let previousTicks, let ticks {
                cpuPercent = Self.percentBusy(from: previousTicks, to: ticks)
            } else {
                cpuPercent = nil
            }
            if let ticks {
                previousTicks = ticks
            }

            let memory = Self.readMemory()
            return SystemLoadSnapshot(
                cpuUsagePercent: cpuPercent,
                usedMemoryBytes: memory.used,
                totalMemoryBytes: memory.total
            )
        }

        private static func readCPUTicks() -> host_cpu_load_info? {
            var load = host_cpu_load_info()
            var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
            let result = withUnsafeMutablePointer(to: &load) { pointer -> kern_return_t in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
                }
            }
            return result == KERN_SUCCESS ? load : nil
        }

        private static func percentBusy(from previous: host_cpu_load_info, to current: host_cpu_load_info) -> Double? {
            func delta(_ key: KeyPath<host_cpu_load_info, UInt32>) -> Double {
                Double(current[keyPath: key]) - Double(previous[keyPath: key])
            }
            let user = delta(\.cpu_ticks.0)
            let system = delta(\.cpu_ticks.1)
            let idle = delta(\.cpu_ticks.2)
            let nice = delta(\.cpu_ticks.3)
            let total = user + system + idle + nice
            guard total > 0 else { return nil }
            return max(0, min(100, (user + system + nice) / total * 100))
        }

        private static func readMemory() -> (used: Int64, total: Int64) {
            var stats = vm_statistics64()
            var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
            let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
                }
            }

            let total = Int64(ProcessInfo.processInfo.physicalMemory)
            guard result == KERN_SUCCESS else { return (0, total) }

            let pageSize = Int64(vm_kernel_page_size)
            let active = Int64(stats.active_count) * pageSize
            let wired = Int64(stats.wire_count) * pageSize
            let compressed = Int64(stats.compressor_page_count) * pageSize
            return (active + wired + compressed, total)
        }
    }
#endif
}
