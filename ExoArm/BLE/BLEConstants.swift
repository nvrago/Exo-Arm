// BLE/BLEConstants.swift
// UUIDs and packet format shared between firmware and app.

import CoreBluetooth

enum BLEUUID {
    // ESP32 IMU service (custom, must match firmware)
    static let imuService = CBUUID(string: "12345678-1234-1234-1234-123456789abc")
    static let imuData = CBUUID(string: "12345678-1234-1234-1234-123456789abd")
    static let imuCommand = CBUUID(string: "12345678-1234-1234-1234-123456789abe")
    static let imuStatus = CBUUID(string: "12345678-1234-1234-1234-123456789abf")

    // Standard Bluetooth heart rate (Whoop, chest straps, etc.)
    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
}

// Binary packet from ESP32:
// 64 bytes = 16 x Float32 (little-endian)
// [ref_w ref_x ref_y ref_z] bytes 0-15
// [ua_w ua_x ua_y ua_z] bytes 16-31
// [fa_w fa_x fa_y fa_z] bytes 32-47
// [hd_w hd_x hd_y hd_z] bytes 48-63
let kIMUPacketSize = 64
let kFloatsPerPacket = 16

enum ESPCommand: String {
    case start = "START"
    case stop = "STOP"
    case mark = "MARK"
    case ping = "PING"
    case status = "STATUS"

    static func rate(_ hz: Int) -> String {
        return "RATE:\(hz)"
    }
}