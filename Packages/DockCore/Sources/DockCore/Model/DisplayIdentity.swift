public struct DisplayIdentity: Hashable, Sendable, Codable {
    public let vendorNumber: UInt32
    public let modelNumber: UInt32
    public let serialNumber: UInt32
    public let isBuiltIn: Bool
    public let ordinalFallback: Int

    public init(
        vendorNumber: UInt32,
        modelNumber: UInt32,
        serialNumber: UInt32,
        isBuiltIn: Bool,
        ordinalFallback: Int
    ) {
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.isBuiltIn = isBuiltIn
        self.ordinalFallback = ordinalFallback
    }

    public var persistenceKey: String {
        "\(vendorNumber)-\(modelNumber)-\(serialNumber)-\(isBuiltIn ? 1 : 0)-\(ordinalFallback)"
    }

    public var hasStableHardwareIdentity: Bool {
        vendorNumber != 0 && modelNumber != 0 && serialNumber != 0
    }
}
