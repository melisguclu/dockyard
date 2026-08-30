#!/usr/bin/env swift

import Darwin
import Foundation

let duration = Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
let label = CommandLine.arguments.dropFirst(2).first ?? "sample"

func dockyardPID() -> Int32? {
    var count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard count > 0 else { return nil }
    var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size)
    count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, count)
    var name = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    for pid in pids where pid > 0 {
        guard proc_name(pid, &name, UInt32(MAXPATHLEN)) > 0 else { continue }
        if String(cString: name) == "Dockyard" { return pid }
    }
    return nil
}

func rusage(_ pid: pid_t) -> rusage_info_v6? {
    var info = rusage_info_v6()
    let code = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
        }
    }
    return code == 0 ? info : nil
}

func taskInfo(_ pid: pid_t) -> proc_taskinfo? {
    var info = proc_taskinfo()
    let size = MemoryLayout<proc_taskinfo>.size
    let read = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
    return read == Int32(size) ? info : nil
}

func megabytes(_ bytes: UInt64) -> String {
    String(format: "%.1f MB", Double(bytes) / 1_048_576)
}

guard let pid = dockyardPID() else {
    FileHandle.standardError.write(Data("Dockyard is not running. Launch it first.\n".utf8))
    exit(1)
}
guard let first = rusage(pid) else {
    FileHandle.standardError.write(Data("Could not read rusage for pid \(pid).\n".utf8))
    exit(1)
}

let startedAt = Date()
Thread.sleep(forTimeInterval: duration)

guard let second = rusage(pid), let task = taskInfo(pid) else {
    FileHandle.standardError.write(Data("Dockyard exited during the window.\n".utf8))
    exit(1)
}

let wall = Date().timeIntervalSince(startedAt)
let cpuSeconds = Double((second.ri_user_time + second.ri_system_time)
    - (first.ri_user_time + first.ri_system_time)) / 1e9
let cycles = second.ri_cycles - first.ri_cycles
let instructions = second.ri_instructions - first.ri_instructions
let idleWakeups = second.ri_pkg_idle_wkups - first.ri_pkg_idle_wkups
let interruptWakeups = second.ri_interrupt_wkups - first.ri_interrupt_wkups
let read = second.ri_diskio_bytesread - first.ri_diskio_bytesread
let written = second.ri_diskio_byteswritten - first.ri_diskio_byteswritten
let energy = second.ri_billed_energy - first.ri_billed_energy

print("Dockyard pid \(pid), \(label), \(String(format: "%.1f", wall)) s window")
print("")
print(String(format: "  CPU, share of one core      %.4f %%", cpuSeconds / wall * 100))
print(String(format: "  CPU time in the window      %.1f ms", cpuSeconds * 1000))
print(String(format: "  Cycles per second           %@", cycles == 0 ? "0" : "\(cycles / UInt64(wall))"))
print(String(format: "  Instructions per second     %@", instructions == 0 ? "0" : "\(instructions / UInt64(wall))"))
if cycles > 0 {
    print(String(format: "  Instructions per cycle      %.2f", Double(instructions) / Double(cycles)))
}
print(String(format: "  Idle wakeups per second     %.3f", Double(idleWakeups) / wall))
print(String(format: "  Interrupt wakeups /second   %.3f", Double(interruptWakeups) / wall))
print(String(format: "  Energy attributed           %.1f mJ  (%.2f mW average)",
             Double(energy) / 1e6, Double(energy) / 1e6 / wall))
print("")
print("  Memory footprint            \(megabytes(second.ri_phys_footprint))")
print("  Peak footprint, lifetime    \(megabytes(second.ri_lifetime_max_phys_footprint))")
print("  Resident size               \(megabytes(second.ri_resident_size))")
print("  Footprint change in window  \(String(format: "%+.2f MB", (Double(second.ri_phys_footprint) - Double(first.ri_phys_footprint)) / 1_048_576))")
print("")
print("  Threads                     \(task.pti_threadnum)")
print("  Disk read in window         \(megabytes(read))")
print("  Disk written in window      \(megabytes(written))")
print("  Page-ins in window          \(second.ri_pageins - first.ri_pageins)")
