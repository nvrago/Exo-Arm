// Views/DashboardView.swift
// Main app layout: left panel, center 3D + graph, right panel.

import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView()
            HStack(spacing: 0) {
                LeftPanel()
                    .frame(width: 275)
                CenterPanel()
                RightPanel()
                    .frame(width: 285)
            }
        }
        .background(Color(white: 0.07))
        .preferredColorScheme(.dark)
    }
}

struct ToolbarView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Text("ExoArm")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.cyan)
                StatusPill(label: "ESP32", connected: session.espConnected)
                StatusPill(label: "HR", connected: session.whoopConnected)
            }

            Spacer()

            HStack(spacing: 6) {
                ToolButton("Scan", color: .cyan) { session.startScanning() }
                ToolButton("Ping", color: .gray) { session.sendCommand(.ping) }
                    .disabled(!session.espConnected)

                if session.isStreaming {
                    ToolButton("Stop", color: .red) { session.sendCommand(.stop) }
                } else {
                    ToolButton("Start", color: .green) { session.sendCommand(.start) }
                        .disabled(!session.espConnected)
                }

                ToolButton("Mark", color: .orange) { session.sendCommand(.mark) }
                    .disabled(!session.isStreaming)

                if session.isRecording {
                    ToolButton("Stop Rec", color: .red) { session.stopRecording() }
                } else {
                    ToolButton("Record", color: .purple) { session.startRecording() }
                        .disabled(!session.isStreaming)
                }

                ToolButton("Status", color: .gray) { session.sendCommand(.status) }
                    .disabled(!session.espConnected)

                ToolButton("Calibrate", color: .yellow) { session.calibrate() }
                    .disabled(!session.isStreaming)

                if session.isCalibrated {
                    ToolButton("Clear Cal", color: .gray) { session.clearCalibration() }
                }

                Divider().frame(height: 16)

                Toggle(isOn: Binding(
                    get: { session.useICloud },
                    set: { session.toggleICloud($0) }
                )) {
                    HStack(spacing: 4) {
                        Image(systemName: session.useICloud ? "icloud.fill" : "internaldrive")
                            .font(.system(size: 11))
                        Text(session.storageLocation)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(session.useICloud ? .cyan : .secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!session.iCloudAvailable)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.085))
        .overlay(Divider(), alignment: .bottom)
    }
}

struct StatusPill: View {
    let label: String
    let connected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connected ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(connected ? .green : Color(white: 0.45))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

struct ToolButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    init(_ label: String, color: Color, action: @escaping () -> Void) {
        self.label = label
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct LeftPanel: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("Joint angles")
                VStack(spacing: 10) {
                    AngleGauge(label: "Shoulder", value: session.latestFrame?.shoulderAngle, color: .cyan, maxAngle: 180)
                    AngleGauge(label: "Elbow", value: session.latestFrame?.elbowAngle, color: .green, maxAngle: 180)
                    AngleGauge(label: "Wrist", value: session.latestFrame?.wristAngle, color: .orange, maxAngle: 180)
                }

                SectionHeader("Euler angles (R / P / Y)")
                VStack(spacing: 6) {
                    if let f = session.latestFrame {
                        EulerRow("Shoulder", f.shoulderEuler, .cyan)
                        EulerRow("Elbow", f.elbowEuler, .green)
                        EulerRow("Wrist", f.wristEuler, .orange)
                    } else {
                        Text("Waiting for data...")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.35))
                    }
                }

                if let cal = session.calibration {
                    SectionHeader("Sensor calibration")
                    VStack(spacing: 8) {
                        ForEach(Array(cal.keys.sorted()), id: \.self) { key in
                            if let c = cal[key] {
                                CalibRow(name: key, data: c)
                            }
                        }
                    }
                }

                SectionHeader("Session")
                VStack(spacing: 6) {
                    StatRow("FPS", "\(session.fps)", session.fps > 50 ? .green : .orange)
                    StatRow("Data rate", "\(session.dataRate) Hz", .cyan)
                    StatRow("Pitches", "\(session.pitchCount)", .cyan)
                    StatRow("Recording", session.isRecording ? "Active" : "Off",
                        session.isRecording ? .red : Color(white: 0.5))
                    StatRow("Calibrated", session.isCalibrated ? "Yes" : "No",
                        session.isCalibrated ? .yellow : Color(white: 0.5))
                }

                SectionHeader("Biometrics")
                if session.whoopConnected {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            BioGauge(label: "Heart rate", value: Float(session.heartRate ?? 0),
                                unit: "bpm", color: .red, minVal: 40, maxVal: 200)
                            BioGauge(label: "Strain", value: nil,
                                unit: "", color: .yellow, minVal: 0, maxVal: 21)
                        }
                        HStack(spacing: 10) {
                            BioGauge(label: "Recovery", value: nil,
                                unit: "%", color: .green, minVal: 0, maxVal: 100)
                            BioGauge(label: "HRV", value: nil,
                                unit: "ms", color: .purple, minVal: 0, maxVal: 200)
                        }
                    }
                    HeartMonitor(hrHistory: session.hrHistory)
                        .frame(height: 70)
                } else {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            BioGaugeOffline(label: "Heart rate")
                            BioGaugeOffline(label: "Strain")
                        }
                        HStack(spacing: 10) {
                            BioGaugeOffline(label: "Recovery")
                            BioGaugeOffline(label: "HRV")
                        }
                    }
                    HeartMonitorOffline()
                        .frame(height: 70)
                }
            }
            .padding(14)
        }
        .background(Color(white: 0.085))
        .overlay(Divider(), alignment: .trailing)
    }
}

struct CenterPanel: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            ArmSceneView(viewModel: session)
            Divider()
            JointGraph()
                .frame(height: 140)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.075))
        }
    }
}

struct JointGraph: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Joint angles over time")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: 0.45))
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                HStack(spacing: 10) {
                    LegendDot("Shoulder", .cyan)
                    LegendDot("Elbow", .green)
                    LegendDot("Wrist", .orange)
                }
            }

            Chart {
                ForEach(Array(session.shoulderHistory.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("Sample", i), y: .value("Angle", v))
                        .foregroundStyle(.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                ForEach(Array(session.elbowHistory.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("Sample", i), y: .value("Angle", v))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                ForEach(Array(session.wristHistory.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("Sample", i), y: .value("Angle", v))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 45, 90, 135, 180]) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        Text("\(val.as(Int.self) ?? 0)")
                            .font(.system(size: 9))
                            .foregroundColor(Color(white: 0.4))
                    }
                }
            }
            .chartYScale(domain: 0...180)
        }
    }
}

struct RightPanel: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("Quaternion data")
                if let f = session.latestFrame {
                    VStack(spacing: 8) {
                        QuatCard("Reference", f.raw.reference, .gray)
                        QuatCard("Upper arm", f.raw.upperArm, .cyan)
                        QuatCard("Forearm", f.raw.forearm, .green)
                        QuatCard("Hand", f.raw.hand, .orange)
                    }
                } else {
                    Text("Waiting for data...")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.35))
                }

                SectionHeader("Pitch comparison")
                VStack(spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("--")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        Text("% match")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.45))
                        Spacer()
                        Text("vs baseline")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.35))
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)

                    HStack(spacing: 8) {
                        CompactStat("Shoulder", "--", .cyan)
                        CompactStat("Elbow", "--", .green)
                        CompactStat("Wrist", "--", .orange)
                    }
                }

                SectionHeader("Event log")
                VStack(alignment: .leading, spacing: 4) {
                    if session.logMessages.isEmpty {
                        Text("No events yet")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.3))
                    } else {
                        ForEach(session.logMessages.suffix(25)) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.timestamp, style: .time)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Color(white: 0.3))
                                    .frame(width: 55, alignment: .leading)
                                Text(entry.message)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(white: 0.55))
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.03))
                .cornerRadius(6)
            }
            .padding(14)
        }
        .background(Color(white: 0.085))
        .overlay(Divider(), alignment: .leading)
    }
}

struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.cyan)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

struct AngleGauge: View {
    let label: String
    let value: Float?
    let color: Color
    let maxAngle: Float

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.08), lineWidth: 4)
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: CGFloat((value ?? 0) / maxAngle) * 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Text(value != nil ? "\(Int(value!))" : "--")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(white: 0.5))
                    .tracking(0.5)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value != nil ? String(format: "%.1f", value!) : "--")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                    Text("deg")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.4))
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }
}

struct EulerRow: View {
    let label: String
    let euler: EulerAngles
    let color: Color
    init(_ label: String, _ euler: EulerAngles, _ color: Color) {
        self.label = label
        self.euler = euler
        self.color = color
    }
    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(color).frame(width: 4, height: 4)
                .padding(.trailing, 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(white: 0.55))
                .frame(width: 55, alignment: .leading)
            Text(String(format: "%+.1f", euler.roll))
                .frame(width: 50, alignment: .trailing)
            Text(String(format: "%+.1f", euler.pitch))
                .frame(width: 50, alignment: .trailing)
            Text(String(format: "%+.1f", euler.yaw))
                .frame(width: 50, alignment: .trailing)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(Color(white: 0.5))
    }
}

struct CalibRow: View {
    let name: String
    let data: CalibrationData
    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(white: 0.65))
                .frame(width: 70, alignment: .leading)
            HStack(spacing: 6) {
                CalibDot("S", data.sys)
                CalibDot("G", data.gyro)
                CalibDot("A", data.accel)
                CalibDot("M", data.mag)
            }
        }
    }
}

struct CalibDot: View {
    let label: String
    let val: Int
    init(_ label: String, _ val: Int) {
        self.label = label
        self.val = val
    }
    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(val >= 3 ? Color.green : (val >= 1 ? Color.orange : Color.red))
                .frame(width: 6, height: 6)
            Text("\(label):\(val)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let color: Color
    init(_ label: String, _ value: String, _ color: Color = Color(white: 0.6)) {
        self.label = label
        self.value = value
        self.color = color
    }
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.45))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 4)
    }
}

struct LegendDot: View {
    let label: String
    let color: Color
    init(_ label: String, _ color: Color) {
        self.label = label
        self.color = color
    }
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 9)).foregroundColor(color)
        }
    }
}

struct QuatCard: View {
    let label: String
    let q: Quat
    let color: Color
    init(_ label: String, _ q: Quat, _ color: Color) {
        self.label = label
        self.q = q
        self.color = color
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: 0.7))
            }
            HStack(spacing: 0) {
                QuatVal("w", q.w)
                QuatVal("x", q.x)
                QuatVal("y", q.y)
                QuatVal("z", q.z)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }
}

struct QuatVal: View {
    let label: String
    let val: Float
    init(_ label: String, _ val: Float) {
        self.label = label
        self.val = val
    }
    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(Color(white: 0.35))
            Text(String(format: "%.3f", val))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(white: 0.55))
        }
        .frame(maxWidth: .infinity)
    }
}

struct CompactStat: View {
    let label: String
    let value: String
    let color: Color
    init(_ label: String, _ value: String, _ color: Color) {
        self.label = label
        self.value = value
        self.color = color
    }
    var body: some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(Color(white: 0.4))
                .tracking(0.3)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
    }
}

struct BioGauge: View {
    let label: String
    let value: Float?
    let unit: String
    let color: Color
    let minVal: Float
    let maxVal: Float

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.06), lineWidth: 3.5)
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: value != nil ? CGFloat((value! - minVal) / (maxVal - minVal)) * 0.75 : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                VStack(spacing: 0) {
                    Text(value != nil ? "\(Int(value!))" : "--")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 7))
                            .foregroundColor(Color(white: 0.4))
                    }
                }
            }
            .frame(width: 44, height: 44)
            Text(label.uppercased())
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(Color(white: 0.45))
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}

struct BioGaugeOffline: View {
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.04), lineWidth: 3.5)
                    .rotationEffect(.degrees(135))
                Text("--")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(white: 0.25))
            }
            .frame(width: 44, height: 44)
            Text(label.uppercased())
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(Color(white: 0.25))
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.02))
        .cornerRadius(8)
    }
}

struct HeartMonitor: View {
    let hrHistory: [Int]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.red)
                Text("HR MONITOR")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Color(white: 0.4))
                    .tracking(0.5)
                Spacer()
                if let last = hrHistory.last {
                    Text("\(last) bpm")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Canvas { context, size in
                let w = size.width
                let h = size.height - 4
                let maxPts = 120
                let pts = Array(hrHistory.suffix(maxPts))
                guard pts.count > 1 else { return }

                let minHR = Float(max(40, (pts.min() ?? 60) - 10))
                let maxHR = Float(min(220, (pts.max() ?? 100) + 10))
                let range = maxHR - minHR

                for i in 0..<4 {
                    let y = CGFloat(i) / 3.0 * h
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: w, y: y))
                    context.stroke(grid, with: .color(Color.red.opacity(0.08)), lineWidth: 0.5)
                }

                var path = Path()
                for (i, hr) in pts.enumerated() {
                    let x = CGFloat(i) / CGFloat(maxPts) * w
                    let normalized = (Float(hr) - minHR) / range
                    let y = h - CGFloat(normalized) * h
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(.red), lineWidth: 1.5)

                if let last = pts.last {
                    let x = CGFloat(pts.count - 1) / CGFloat(maxPts) * w
                    let normalized = (Float(last) - minHR) / range
                    let y = h - CGFloat(normalized) * h
                    let dot = Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
                    context.fill(dot, with: .color(.red))
                    let glow = Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12))
                    context.fill(glow, with: .color(.red.opacity(0.3)))
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.15), lineWidth: 0.5)
        )
    }
}

struct HeartMonitorOffline: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "heart.slash")
                    .font(.system(size: 8))
                    .foregroundColor(Color(white: 0.25))
                Text("HR MONITOR")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Color(white: 0.25))
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            ZStack {
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: h / 2))
                    line.addLine(to: CGPoint(x: w, y: h / 2))
                    context.stroke(line, with: .color(Color.red.opacity(0.15)), lineWidth: 1)
                }
                Text("OFFLINE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.red.opacity(0.35))
                    .tracking(2)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .background(Color.black.opacity(0.2))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.08), lineWidth: 0.5)
        )
    }
}
