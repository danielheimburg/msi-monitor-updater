import Foundation
import IOKit.hid

/// Passive discovery only. Opening a session and sending reports are explicit operations.
struct MonitorDevice: Identifiable, Sendable {
    let id: UInt64
    let location: Int
    let serial: String
    let product: String

    static let reportDescriptor = "05010900a1018501150026ff0019012908953f750881021901290891028502150026ff0019012908953f750881021901290891028504150026ff0019012908953f750881021901290891020600ff0901a10185820901150026ff007508957ab10285530901150026ff00750896d402b102c0c0"

    static func discover() throws -> [MonitorDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x1462, kIOHIDProductIDKey: 0x3FA4] as CFDictionary)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        return try devices.map { device in
            func number(_ key: String) -> Int? {
                (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
            }
            let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data
            guard descriptor?.map({ String(format: "%02x", $0) }).joined() == reportDescriptor,
                  number(kIOHIDMaxInputReportSizeKey) == 64,
                  number(kIOHIDMaxOutputReportSizeKey) == 64,
                  let location = number(kIOHIDLocationIDKey),
                  let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String,
                  !serial.isEmpty else {
                throw UpdaterError("An MSI controller has an unsupported HID identity.")
            }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID) == KERN_SUCCESS else {
                throw UpdaterError("Cannot bind the MSI controller to its current USB service.")
            }
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "MSI controller"
            return MonitorDevice(id: registryID, location: location, serial: serial, product: product)
        }.sorted { $0.id < $1.id }
    }
}
