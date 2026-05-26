import SwiftUI

// shoop control and biometrics panel.
// two stacked sections, Account (REST) and Band (BLE).

struct WhoopPanel: View {
    
    @ObservedObject var vm: WhoopViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHOOP")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.cyan)
                .tracking(1.5)
            
            accountSection
            
            Divider().opacity(0.3)
            
            bandSection
            
            Divider().opacity(0.3)
            
            metricsGrid
            
            if let err = vm.lastError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    //account section (REST / OAuth)
    
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusDot(active: vm.isAuthorized, activeColor: .green)
                Text(vm.isAuthorized ? "Account linked" : "Not authorized")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if let last = vm.lastSyncTime {
                    Text(relativeTime(last))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 6) {
                if !vm.isAuthorized {
                    Button {
                        Task { await vm.authorize() }
                    } label: {
                        Label("Authorize", systemImage: "link")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button {
                        Task { await vm.fetchContext() }
                    } label: {
                        if vm.isFetchingContext {
                            ProgressView().controlSize(.mini)
                        } else {
                            Label("Sync", systemImage: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(vm.isFetchingContext)
                    
                    Button {
                        vm.logout()
                    } label: {
                        Text("Logout")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
    
    //Band section (BLE)
    
    private var bandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusDot(active: vm.isHRConnected, activeColor: .pink)
                Text(vm.isHRConnected ? (vm.hrDeviceName ?? "Connected") : "Band offline")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if vm.isHRConnected {
                    Text("\(vm.currentHR) bpm")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.pink)
                }
            }
            
            HStack(spacing: 6) {
                if !vm.isHRConnected {
                    Button {
                        vm.scanForHR()
                    } label: {
                        Label("Scan", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        vm.disconnectHR()
                    } label: {
                        Text("Disconnect")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
    
    //metrics grid (2x2)
    
    private var metricsGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                metricTile(
                    label: "HEART RATE",
                    value: vm.isHRConnected ? "\(vm.currentHR)" : "--",
                    unit: "bpm",
                    accent: .pink,
                    active: vm.isHRConnected
                )
                metricTile(
                    label: "LOAD",
                    value: vm.sessionLoad > 0 ? String(format: "%.1f", vm.sessionLoad) : "--",
                    unit: zoneLabel,
                    accent: .orange,
                    active: vm.sessionLoad > 0
                )
            }
            HStack(spacing: 8) {
                metricTile(
                    label: "RECOVERY",
                    value: vm.hasContext ? String(format: "%.0f", vm.sessionContext.recoveryScore) : "--",
                    unit: "%",
                    accent: recoveryColor,
                    active: vm.hasContext
                )
                metricTile(
                    label: "HRV",
                    value: vm.hasContext ? String(format: "%.0f", vm.sessionContext.hrvRmssd) : "--",
                    unit: "ms",
                    accent: .purple,
                    active: vm.hasContext
                )
            }
        }
    }
    
    //comps
    
    private func metricTile(label: String, value: String, unit: String, accent: Color, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(active ? accent : .secondary.opacity(0.4))
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.02))
        )
    }
    
    private func statusDot(active: Bool, activeColor: Color) -> some View {
        Circle()
            .fill(active ? activeColor : Color.secondary.opacity(0.4))
            .frame(width: 6, height: 6)
            .shadow(color: active ? activeColor.opacity(0.8) : .clear, radius: 3)
    }
    
    // derived values
    
    private var zoneLabel: String {
        guard vm.currentZone > 0 else { return "trimp" }
        return "Z\(vm.currentZone)"
    }
    
    private var recoveryColor: Color {
        let r = vm.sessionContext.recoveryScore
        switch r {
        case 67...: return .green
        case 34..<67: return .yellow
        default: return .red
        }
    }
    
    private func relativeTime(_ date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(elapsed / 60)m ago" }
        return "\(elapsed / 3600)h ago"
    }
}
