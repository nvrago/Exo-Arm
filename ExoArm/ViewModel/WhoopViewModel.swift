import Foundation
import Combine
import SwiftUI

@MainActor
final class WhoopViewModel: ObservableObject {
    
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var isFetchingContext: Bool = false
    @Published private(set) var sessionContext: WhoopSessionContext = .empty
    @Published private(set) var hasContext: Bool = false
    @Published private(set) var lastSyncTime: Date?
    
    @Published private(set) var isHRConnected: Bool = false
    @Published private(set) var hrDeviceName: String?
    @Published private(set) var currentHR: Int = 0
    @Published private(set) var hrLastUpdate: Date?
    
    @Published private(set) var sessionLoad: Double = 0
    @Published private(set) var currentZone: Int = 0
    @Published private(set) var isCalibrating: Bool = true
    @Published private(set) var calibratedRHR: Double = 0
    
    @Published var lastError: String?
    
    let oauth: WhoopOAuthManager
    let hrPeripheral: WhoopHRPeripheral
    let trimp: TRIMPCalculator
    private let api: WhoopAPIClient
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        let oauth = WhoopOAuthManager()
        self.oauth = oauth
        self.api = WhoopAPIClient(oauth: oauth)
        self.hrPeripheral = WhoopHRPeripheral()
        self.trimp = TRIMPCalculator()
        
        wireBindings()
    }
    
    private func wireBindings() {
        oauth.$isAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthorized)
        
        hrPeripheral.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isHRConnected)
        
        hrPeripheral.$deviceName
            .receive(on: DispatchQueue.main)
            .assign(to: &$hrDeviceName)
        
        hrPeripheral.$currentHR
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentHR)
        
        hrPeripheral.$lastUpdate
            .receive(on: DispatchQueue.main)
            .assign(to: &$hrLastUpdate)
        
        trimp.$sessionLoad
            .receive(on: DispatchQueue.main)
            .assign(to: &$sessionLoad)
        
        trimp.$currentZone
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentZone)
        
        trimp.$isCalibrating
            .receive(on: DispatchQueue.main)
            .assign(to: &$isCalibrating)
        
        trimp.$calibratedRHR
            .receive(on: DispatchQueue.main)
            .assign(to: &$calibratedRHR)
        
        hrPeripheral.onHeartRateUpdate = { [weak self] hr, time in
            Task { @MainActor in
                self?.trimp.ingest(hr: hr, at: time)
            }
        }
    }
    
    func authorize() async {
        do {
            try await oauth.authorize()
            lastError = nil
            await fetchContext()
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    func logout() {
        oauth.logout()
        sessionContext = .empty
        hasContext = false
        lastSyncTime = nil
    }
    
    func fetchContext() async {
        guard isAuthorized else { return }
        isFetchingContext = true
        defer { isFetchingContext = false }
        
        do {
            let ctx = try await api.fetchSessionContext()
            sessionContext = ctx
            hasContext = true
            lastSyncTime = Date()
            lastError = nil
            
            if ctx.restingHeartRate > 0 {
                trimp.seedRestingHR(ctx.restingHeartRate)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    func scanForHR() {
        hrPeripheral.startScan()
    }
    
    func disconnectHR() {
        hrPeripheral.disconnect()
    }
    
    func startSession() {
        trimp.startSession()
    }
    
    func stopSession() {
        trimp.stopSession()
    }
}
