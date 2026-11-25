import Foundation

/// Hardware and system facts for the "my equipment" card.
///
/// Deliberately has no serial number and no hardware UUID: nothing that identifies the device can leak into a share card.
public struct MacProfile: Sendable, Equatable {
    /// Marketing family, e.g. "MacBook Air".
    public var modelName: String
    /// e.g. "Mac15,12".
    public var modelIdentifier: String
    /// e.g. "Apple M3", or the Intel processor name.
    public var chip: String
    public var memoryGB: Int?
    /// Bytes of the startup volume, as the system reports them.
    public var storageBytes: Int64?
    /// e.g. "macOS 27.3".
    public var system: String

    public init(modelName: String, modelIdentifier: String, chip: String, memoryGB: Int?, storageBytes: Int64?, system: String) {
        self.modelName = modelName
        self.modelIdentifier = modelIdentifier
        self.chip = chip
        self.memoryGB = memoryGB
        self.storageBytes = storageBytes
        self.system = system
    }

    public var memoryLabel: String? { memoryGB.map { "\($0) GB" } }
    public var storageLabel: String? { storageBytes.map(Self.storageLabel(forBytes:)) }

    /// The size printed on the box: the smallest standard capacity that holds what the system reports
    /// (a "512 GB" disk reports ~494 GB because the system counts in decimal units and reserves space).
    public static func storageLabel(forBytes bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        let standard: [Double] = [64, 128, 256, 512, 1000, 2000, 4000, 8000, 16000]
        guard let size = standard.first(where: { $0 >= gb }) else { return String(format: "%.0f GB", gb) }
        return size >= 1000 ? "\(Int(size / 1000)) TB" : "\(Int(size)) GB"
    }

    // MARK: Reading

    /// Reads this Mac's profile. Runs `system_profiler` (about a second): call it off the main thread.
    public static func current() -> MacProfile {
        let parsed = runSystemProfiler().flatMap(parse(systemProfilerJSON:))
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let system = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        let memoryBytes = sysctlInt64("hw.memsize")
        return MacProfile(
            modelName: parsed?.modelName ?? "Mac",
            modelIdentifier: parsed?.modelIdentifier ?? sysctlString("hw.model") ?? "",
            chip: parsed?.chip ?? sysctlString("machdep.cpu.brand_string") ?? "",
            memoryGB: parsed?.memoryGB ?? memoryBytes.map { Int((Double($0) / 1_073_741_824).rounded()) },
            storageBytes: startupVolumeBytes(),
            system: system)
    }

    struct Parsed: Equatable {
        var modelName: String
        var modelIdentifier: String
        var chip: String
        var memoryGB: Int?
    }

    /// Picks the fields we need from `system_profiler SPHardwareDataType -json`; ignores everything else.
    static func parse(systemProfilerJSON data: Data) -> Parsed? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = (root["SPHardwareDataType"] as? [[String: Any]])?.first else { return nil }
        let chip = (entry["chip_type"] as? String) ?? (entry["cpu_type"] as? String) ?? (entry["processor_name"] as? String) ?? ""
        let memory = (entry["physical_memory"] as? String).flatMap { text -> Int? in
            Int(text.prefix { $0.isNumber })
        }
        return Parsed(modelName: entry["machine_name"] as? String ?? "Mac",
                      modelIdentifier: entry["machine_model"] as? String ?? "",
                      chip: chip, memoryGB: memory)
    }

    private static func runSystemProfiler() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private static func startupVolumeBytes() -> Int64? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey])
        return values?.volumeTotalCapacity.map(Int64.init)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }
}
