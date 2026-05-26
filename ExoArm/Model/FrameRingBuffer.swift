// Model/FrameRingBuffer.swift
// Lock free ring buffer for passing frames from BLE queue to UI.

import Foundation

final class FrameRingBuffer {
    private let capacity: Int
    private var buffer: [ProcessedFrame?]
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private let lock = NSLock()
    private(set) var totalWritten: UInt64 = 0
    private(set) var totalDropped: UInt64 = 0

    init(capacity: Int = 512) {
        self.capacity = capacity
        self.buffer = [ProcessedFrame?](repeating: nil, count: capacity)
    }

    // called from BLE background queue
    func write(_ frame: ProcessedFrame) {
        lock.lock()
        buffer[writeIndex % capacity] = frame
        writeIndex += 1
        totalWritten += 1
        if writeIndex - readIndex > capacity {
            totalDropped += 1
            readIndex = writeIndex - capacity
        }
        lock.unlock()
    }

    // called from main thread, returns latest frame, skips intermediate
    func readLatest() -> ProcessedFrame? {
        lock.lock()
        defer { lock.unlock() }
        if writeIndex == readIndex { return nil }
        readIndex = writeIndex
        return buffer[(writeIndex - 1) % capacity]
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return writeIndex - readIndex
    }
}
