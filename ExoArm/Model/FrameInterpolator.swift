// Model/FrameInterpolator.swift
// Slerp interpolation between sensor frames for fluid arm motion.

import simd
import QuartzCore

final class FrameInterpolator {
    private var previous: ProcessedFrame?
    private var target: ProcessedFrame?
    private var targetTime: TimeInterval = 0
    private var previousTime: TimeInterval = 0

    func pushTarget(_ frame: ProcessedFrame) {
        previous = target
        previousTime = targetTime
        target = frame
        targetTime = CACurrentMediaTime()
    }

    func interpolated() -> InterpolatedPose? {
        guard let tgt = target else { return nil }

        guard let prev = previous else {
            return InterpolatedPose(
                upperArm: tgt.upperArmRel.simdQuat,
                forearm: tgt.forearmRel.simdQuat,
                hand: tgt.handRel.simdQuat,
                shoulderAngle: tgt.shoulderAngle,
                elbowAngle: tgt.elbowAngle,
                wristAngle: tgt.wristAngle)
        }

        let now = CACurrentMediaTime()
        let dt = targetTime - previousTime
        var t: Float = 1.0
        if dt > 0.001 {
            t = Float(min(1.0, (now - targetTime) / dt))
        }

        return InterpolatedPose(
            upperArm: simd_slerp(prev.upperArmRel.simdQuat, tgt.upperArmRel.simdQuat, t),
            forearm: simd_slerp(prev.forearmRel.simdQuat, tgt.forearmRel.simdQuat, t),
            hand: simd_slerp(prev.handRel.simdQuat, tgt.handRel.simdQuat, t),
            shoulderAngle: prev.shoulderAngle + (tgt.shoulderAngle - prev.shoulderAngle) * t,
            elbowAngle: prev.elbowAngle + (tgt.elbowAngle - prev.elbowAngle) * t,
            wristAngle: prev.wristAngle + (tgt.wristAngle - prev.wristAngle) * t)
    }
}

struct InterpolatedPose {
    let upperArm: simd_quatf
    let forearm: simd_quatf
    let hand: simd_quatf
    let shoulderAngle: Float
    let elbowAngle: Float
    let wristAngle: Float
}
