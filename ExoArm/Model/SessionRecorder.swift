// Model/SessionRecorder.swift
// CSV session recording and baseline management.
// Writes to iCloud Drive when available, falls back to local Documents.
//
// Xcode setup for iCloud:
// 1. Signing & Capabilities > + Capability > iCloud
// 2. Check "iCloud Documents"
// 3. Add container: iCloud.com.yourname.PitcherRehab
// 4. Entitlements file gets com.apple.developer.icloud-container-identifiers
//    and com.apple.developer.ubiquity-container-identifiers automatically

import Foundation
import Combine

final class SessionRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var frameCount: Int = 0
    @Published var useICloud = true
    @Published var iCloudAvailable = false

    private var fileHandle: FileHandle?
    private var filePath: URL?
    private var pitchNum: Int = 0
    private var runNumber: Int = 1

    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HHmmss"
        return f
    }()

    init() {
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
    }

    // Root directory: iCloud container or local Documents
    private var rootDir: URL {
        if useICloud, let cloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return cloudURL.appendingPathComponent("Documents/PitcherRehab", isDirectory: true)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("PitcherRehab", isDirectory: true)
    }

    private var sessionsDir: URL {
        rootDir.appendingPathComponent("sessions", isDirectory: true)
    }

    private var baselinesDir: URL {
        rootDir.appendingPathComponent("baselines", isDirectory: true)
    }

    // Directory for today's date (e.g. sessions/2026-04-15/)
    private func todayDir() -> URL {
        let dateStr = dateFmt.string(from: Date())
        let dir = sessionsDir.appendingPathComponent(dateStr, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Count existing runs today to auto-increment run number
    private func nextRunNumber(in dir: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let runs = files.filter { $0.hasSuffix(".csv") }
        return runs.count + 1
    }

    func startRecording(sessionName: String = "session") {
        let dir = todayDir()
        runNumber = nextRunNumber(in: dir)
        let timeStr = timeFmt.string(from: Date())
        let filename = "\(timeStr)_run\(runNumber).csv"
        let path = dir.appendingPathComponent(filename)

        FileManager.default.createFile(atPath: path.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: path)
        filePath = path

        let header = "timestamp,pitch_num,"
            + "ref_w,ref_x,ref_y,ref_z,"
            + "ua_w,ua_x,ua_y,ua_z,"
            + "fa_w,fa_x,fa_y,fa_z,"
            + "hd_w,hd_x,hd_y,hd_z,"
            + "shldr_w,shldr_x,shldr_y,shldr_z,"
            + "elb_w,elb_x,elb_y,elb_z,"
            + "wrt_w,wrt_x,wrt_y,wrt_z,"
            + "shoulder_deg,elbow_deg,wrist_deg,"
            + "heart_rate\n"
        fileHandle?.write(header.data(using: .utf8)!)

        frameCount = 0
        pitchNum = 0
        isRecording = true

        let storage = useICloud && iCloudAvailable ? "iCloud" : "local"
        print("[REC] Recording to \(filename) (\(storage))")
    }

    func stopRecording() {
        fileHandle?.closeFile()
        fileHandle = nil
        isRecording = false
        if let path = filePath {
            print("[REC] Saved \(frameCount) frames to \(path.lastPathComponent)")
        }
        filePath = nil
    }

    func markPitch(_ num: Int) {
        pitchNum = num
    }

    func record(_ frame: ProcessedFrame) {
        guard isRecording, let fh = fileHandle else { return }
        let r = frame.raw.reference
        let ua = frame.raw.upperArm
        let fa = frame.raw.forearm
        let hd = frame.raw.hand
        let sr = frame.shoulderRot
        let er = frame.elbowRot
        let wr = frame.wristRot
        let ts = String(format: "%.3f", frame.timestamp.timeIntervalSince1970)
        let hr = frame.heartRate.map { String($0) } ?? ""

        let row = "\(ts),\(pitchNum),"
            + "\(r.w),\(r.x),\(r.y),\(r.z),"
            + "\(ua.w),\(ua.x),\(ua.y),\(ua.z),"
            + "\(fa.w),\(fa.x),\(fa.y),\(fa.z),"
            + "\(hd.w),\(hd.x),\(hd.y),\(hd.z),"
            + "\(sr.w),\(sr.x),\(sr.y),\(sr.z),"
            + "\(er.w),\(er.x),\(er.y),\(er.z),"
            + "\(wr.w),\(wr.x),\(wr.y),\(wr.z),"
            + String(format: "%.2f,%.2f,%.2f", frame.shoulderAngle, frame.elbowAngle, frame.wristAngle)
            + ",\(hr)\n"

        fh.write(row.data(using: .utf8)!)
        frameCount += 1
    }

    // Baseline management

    func saveBaseline(name: String, frames: [ProcessedFrame]) {
        try? FileManager.default.createDirectory(at: baselinesDir, withIntermediateDirectories: true)
        let path = baselinesDir.appendingPathComponent("\(name).json")
        let data: [[String: Any]] = frames.map { f in
            [
                "timestamp": f.timestamp.timeIntervalSince1970,
                "shoulder": ["w": f.shoulderRot.w, "x": f.shoulderRot.x,
                    "y": f.shoulderRot.y, "z": f.shoulderRot.z],
                "elbow": ["w": f.elbowRot.w, "x": f.elbowRot.x,
                    "y": f.elbowRot.y, "z": f.elbowRot.z],
                "wrist": ["w": f.wristRot.w, "x": f.wristRot.x,
                    "y": f.wristRot.y, "z": f.wristRot.z],
                "shoulder_deg": f.shoulderAngle,
                "elbow_deg": f.elbowAngle,
                "wrist_deg": f.wristAngle
            ]
        }
        let wrapper: [String: Any] = [
            "name": name,
            "recorded": ISO8601DateFormatter().string(from: Date()),
            "num_frames": frames.count,
            "frames": data
        ]
        if let json = try? JSONSerialization.data(withJSONObject: wrapper, options: .prettyPrinted) {
            try? json.write(to: path)
            print("[BASELINE] Saved '\(name)' (\(frames.count) frames)")
        }
    }

    func listBaselines() -> [String] {
        try? FileManager.default.createDirectory(at: baselinesDir, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: baselinesDir.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.map { $0.replacingOccurrences(of: ".json", with: "") }
    }

    // Browse past sessions grouped by date
    func listSessionDates() -> [String] {
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: sessionsDir.path)) ?? []
        return dirs.sorted().reversed()
    }

    func listRuns(forDate date: String) -> [String] {
        let dir = sessionsDir.appendingPathComponent(date)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".csv") }.sorted()
    }

    func sessionFilePath(date: String, filename: String) -> URL {
        sessionsDir.appendingPathComponent(date).appendingPathComponent(filename)
    }

    // Check current storage location
    var storageLocation: String {
        if useICloud && iCloudAvailable { return "iCloud Drive" }
        return "Local"
    }
}
