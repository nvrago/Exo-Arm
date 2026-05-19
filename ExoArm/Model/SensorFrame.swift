// Model/SensorFrame.swift
// Quaternion data structures and BLE packet parsing.

import simd
import Foundation

struct Quat {
    let w: Float
    let x: Float
    let y: Float
    let z: Float

    var simdQuat: simd_quatf {
        simd_quatf(ix: x, iy: y, iz: z, r: w)
    }

    var magnitude: Float {
        sqrtf(w * w + x * x + y * y + z * z)
    }

    var isValid: Bool {
        let m = magnitude
        return m > 0.9 && m < 1.1
    }

    static let identity = Quat(w: 1, x: 0, y: 0, z: 0)
}

struct RawSensorData {
    let timestamp: Date
    let reference: Quat
    let upperArm: Quat
    let forearm: Quat
    let hand: Quat

    var allValid: Bool {
        reference.isValid && upperArm.isValid && forearm.isValid && hand.isValid
    }

    static func fromBLEData(_ data: Data) -> RawSensorData? {
        guard data.count >= kIMUPacketSize else { return nil }

        var floats = [Float](repeating: 0, count: kFloatsPerPacket)
        for i in 0..<kFloatsPerPacket {
            floats[i] = data.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: i * 4, as: Float.self)
            }
        }

        // Firmware packs quats in order [ref, slot1, slot2, hand]. Slot 1 is the
        // physical forearm sensor and slot 2 is the physical upper arm sensor,
        // so we swap on decode to keep the rest of the app naming-correct.
        let ref = Quat(w: floats[0], x: floats[1], y: floats[2], z: floats[3])
        let fa = Quat(w: floats[4], x: floats[5], y: floats[6], z: floats[7])
        let ua = Quat(w: floats[8], x: floats[9], y: floats[10], z: floats[11])
        let hd = Quat(w: floats[12], x: floats[13], y: floats[14], z: floats[15])

        let raw = RawSensorData(timestamp: Date(), reference: ref, upperArm: ua, forearm: fa, hand: hd)
        guard raw.allValid else { return nil }
        return raw
    }
}

struct JointAngles {
    let shoulder: Float
    let elbow: Float
    let wrist: Float
}

struct EulerAngles {
    let roll: Float
    let pitch: Float
    let yaw: Float
}

struct ProcessedFrame {
    let timestamp: Date
    let raw: RawSensorData
    let upperArmRel: Quat
    let forearmRel: Quat
    let handRel: Quat
    let shoulderRot: Quat
    let elbowRot: Quat
    let wristRot: Quat
    let shoulderAngle: Float
    let elbowAngle: Float
    let wristAngle: Float
    let shoulderEuler: EulerAngles
    let elbowEuler: EulerAngles
    let wristEuler: EulerAngles
    let heartRate: Int?
}
