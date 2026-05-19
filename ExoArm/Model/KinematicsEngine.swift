// Model/KinematicsEngine.swift
// Joint angle computation with T-pose calibration support.

import simd
import Foundation

final class KinematicsEngine {
    static let shared = KinematicsEngine()
    private init() {}

    // Calibration offsets recorded during T-pose
    private var calibRef: simd_quatf?
    private var calibUA: simd_quatf?
    private var calibFA: simd_quatf?
    private var calibHD: simd_quatf?
    private(set) var isCalibrated = false

    func calibrate(with raw: RawSensorData) {
        calibRef = raw.reference.simdQuat
        calibUA = raw.upperArm.simdQuat
        calibFA = raw.forearm.simdQuat
        calibHD = raw.hand.simdQuat
        isCalibrated = true
        print("[CALIB] Captured zero pose")
    }

    func clearCalibration() {
        calibRef = nil
        calibUA = nil
        calibFA = nil
        calibHD = nil
        isCalibrated = false
        print("[CALIB] Cleared")
    }

    func process(_ raw: RawSensorData, heartRate: Int? = nil) -> ProcessedFrame {
        var refQ = raw.reference.simdQuat
        var uaQ = raw.upperArm.simdQuat
        var faQ = raw.forearm.simdQuat
        var hdQ = raw.hand.simdQuat

        // Apply calibration offset if available
        if let cr = calibRef, let cu = calibUA, let cf = calibFA, let ch = calibHD {
            refQ = cr.conjugate * refQ
            uaQ = cu.conjugate * uaQ
            faQ = cf.conjugate * faQ
            hdQ = ch.conjugate * hdQ
        }

        let uaRel = relativeRotation(from: refQ, to: uaQ)
        let faRel = relativeRotation(from: refQ, to: faQ)
        let hdRel = relativeRotation(from: refQ, to: hdQ)

        let shoulderRot = relativeRotation(from: refQ, to: uaRel)
        let elbowRot = relativeRotation(from: uaRel, to: faRel)
        let wristRot = relativeRotation(from: faRel, to: hdRel)

        return ProcessedFrame(
            timestamp: raw.timestamp,
            raw: raw,
            upperArmRel: quatFromSimd(uaRel),
            forearmRel: quatFromSimd(faRel),
            handRel: quatFromSimd(hdRel),
            shoulderRot: quatFromSimd(shoulderRot),
            elbowRot: quatFromSimd(elbowRot),
            wristRot: quatFromSimd(wristRot),
            shoulderAngle: rotationAngle(shoulderRot),
            elbowAngle: rotationAngle(elbowRot),
            wristAngle: rotationAngle(wristRot),
            shoulderEuler: toEuler(shoulderRot),
            elbowEuler: toEuler(elbowRot),
            wristEuler: toEuler(wristRot),
            heartRate: heartRate
        )
    }

    func similarity(baseline: [ProcessedFrame], current: [ProcessedFrame], scale: Float = 30.0) -> SimilarityResult {
        let target = min(baseline.count, current.count)
        guard target > 0 else {
            return SimilarityResult(elbow: 0, wrist: 0, shoulder: 0, overall: 0,
                elbowDeviation: 0, wristDeviation: 0, shoulderDeviation: 0)
        }

        let baseR = resample(baseline, to: target)
        let currR = resample(current, to: target)

        var eDist: Float = 0
        var wDist: Float = 0
        var sDist: Float = 0
        for i in 0..<target {
            eDist += quatDistance(baseR[i].elbowRot.simdQuat, currR[i].elbowRot.simdQuat)
            wDist += quatDistance(baseR[i].wristRot.simdQuat, currR[i].wristRot.simdQuat)
            sDist += quatDistance(baseR[i].shoulderRot.simdQuat, currR[i].shoulderRot.simdQuat)
        }
        let n = Float(target)
        let avgE = eDist / n
        let avgW = wDist / n
        let avgS = sDist / n

        return SimilarityResult(
            elbow: expf(-avgE / scale) * 100,
            wrist: expf(-avgW / scale) * 100,
            shoulder: expf(-avgS / scale) * 100,
            overall: (expf(-avgE / scale) + expf(-avgW / scale) + expf(-avgS / scale)) / 3.0 * 100,
            elbowDeviation: avgE,
            wristDeviation: avgW,
            shoulderDeviation: avgS
        )
    }

    private func relativeRotation(from a: simd_quatf, to b: simd_quatf) -> simd_quatf {
        a.conjugate * b
    }

    private func rotationAngle(_ q: simd_quatf) -> Float {
        let w = min(1.0, abs(max(-1.0, q.real)))
        return 2.0 * acos(w) * (180.0 / .pi)
    }

    private func toEuler(_ q: simd_quatf) -> EulerAngles {
        let w = q.real
        let x = q.imag.x
        let y = q.imag.y
        let z = q.imag.z

        let sinr = 2.0 * (w * x + y * z)
        let cosr = 1.0 - 2.0 * (x * x + y * y)
        let roll = atan2(sinr, cosr) * (180.0 / .pi)

        var sinp = 2.0 * (w * y - z * x)
        sinp = max(-1.0, min(1.0, sinp))
        let pitch = asin(sinp) * (180.0 / .pi)

        let siny = 2.0 * (w * z + x * y)
        let cosy = 1.0 - 2.0 * (y * y + z * z)
        let yaw = atan2(siny, cosy) * (180.0 / .pi)

        return EulerAngles(roll: roll, pitch: pitch, yaw: yaw)
    }

    private func quatDistance(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        let dot = min(1.0, abs(simd_dot(a, b)))
        return 2.0 * acos(dot) * (180.0 / .pi)
    }

    private func quatFromSimd(_ q: simd_quatf) -> Quat {
        Quat(w: q.real, x: q.imag.x, y: q.imag.y, z: q.imag.z)
    }

    private func resample(_ frames: [ProcessedFrame], to count: Int) -> [ProcessedFrame] {
        guard frames.count > 1, count > 1 else { return frames }
        var result = [ProcessedFrame]()
        for i in 0..<count {
            let idx = Int(Float(i) / Float(count - 1) * Float(frames.count - 1))
            result.append(frames[min(idx, frames.count - 1)])
        }
        return result
    }
}

struct SimilarityResult {
    let elbow: Float
    let wrist: Float
    let shoulder: Float
    let overall: Float
    let elbowDeviation: Float
    let wristDeviation: Float
    let shoulderDeviation: Float
}
