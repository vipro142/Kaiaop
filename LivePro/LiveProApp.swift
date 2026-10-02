import SwiftUI

@main
struct LiveProApp: App {
    @StateObject private var model = IntercomModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            LiveProView(model: model)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { model.activeChanged($0 == .active) }
        }
    }
}
import CoreLocation
import UIKit

// GPS stays independent of the voice engine; no audio-session changes here.
final class GPSTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let labels = ["None — Tắt GPS", "42km Nam", "42km Nữ", "21km Nam", "21km Nữ", "10km Nam", "10km Nữ", "5km Nam", "5km Nữ"]
    static let ids = ["", "42424242", "24242424", "21212121", "12121212", "10101010", "01010101", "05050505", "50505050"]
    @Published var choice = UserDefaults.standard.integer(forKey: "gpsChoice")
    @Published var status = "GPS đang tắt"
    @Published var fixStatus = "Chưa có vị trí"
    @Published var lastSent = "Chưa gửi thành công"
    private let manager = CLLocationManager()
    private var timer: Timer?
    private var latest: CLLocation?
    private var sentFix = Date.distantPast
    private var camera = false
    private var running = false
    private var task: URLSessionDataTask?
    private var generation = 0
    private var lastAttempt = Date.distantPast
    override init() {
        super.init()
        choice = min(8, max(0, choice))
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }
    func configure(camera: Bool) {
        self.camera = camera
        UserDefaults.standard.set(choice, forKey: "gpsChoice")
        generation += 1; task?.cancel(); task = nil
        latest = nil; sentFix = .distantPast; lastSent = "Chưa gửi thành công"; fixStatus = "Chưa có vị trí"
        reconcile()
    }
    private func reconcile() {
        guard camera && choice > 0 else { stop(); status = "GPS đang tắt"; return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if !running {
                running = true; manager.startUpdatingLocation()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sendLatest() }
            }
            status = "Đang tìm GPS • gửi tối đa mỗi giây"
            if manager.accuracyAuthorization == .reducedAccuracy {
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "Tracking")
            }
        default: stop(); status = "Hãy bật quyền Vị trí chính xác trong Cài đặt"
        }
    }
    func requestBackgroundPermission() { manager.requestAlwaysAuthorization() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { reconcile() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running && camera && choice > 0 else { return }
        for fix in locations where fix.horizontalAccuracy >= 0 && CLLocationCoordinate2DIsValid(fix.coordinate) {
            guard abs(fix.timestamp.timeIntervalSinceNow) <= 10 else { continue }
            if let old = latest, fix.timestamp <= old.timestamp { continue }
            latest = fix
            fixStatus = "GPS ±\(Int(fix.horizontalAccuracy)) m • chu kỳ gửi 1 giây"
        }
        sendLatest()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS: \(error.localizedDescription)"
    }
    private func sendLatest() {
        guard Date().timeIntervalSince(lastAttempt) >= 1 else { return }
        guard running, camera, task == nil, let fix = latest, fix.timestamp > sentFix,
              abs(fix.timestamp.timeIntervalSinceNow) <= 10, choice > 0 else { return }
        var url = URLComponents(string: "http://kailive1.ddns.net:5055/")!
        let fields: [(String, String)] = [
            ("id", Self.ids[choice]), ("timestamp", String(Int64(fix.timestamp.timeIntervalSince1970 * 1000))),
            ("lat", String(fix.coordinate.latitude)), ("lon", String(fix.coordinate.longitude)),
            ("accuracy", String(fix.horizontalAccuracy)), ("altitude", String(fix.altitude)),
            ("speed", String(max(0, fix.speed) * 1.94384449)), ("bearing", String(max(0, fix.course))), ("valid", "true")]
        url.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let endpoint = url.url else { return }
        status = "Đang gửi tới Traccar…"
        lastAttempt = Date()
        let token = generation
        var request = URLRequest(url: endpoint); request.timeoutInterval = 8
        task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self = self, self.generation == token else { return }
                self.task = nil
                if error == nil, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    self.sentFix = fix.timestamp
                    self.lastSent = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                    self.status = "Traccar đã nhận"
                } else if let error = error as NSError? {
                    self.status = "Lỗi mạng \(error.code): \(error.localizedDescription)"
                } else if let http = response as? HTTPURLResponse {
                    self.status = "Traccar HTTP \(http.statusCode) • kiểm tra Device ID/cổng 5055"
                } else { self.status = "Không nhận được phản hồi Traccar" }
            }
        }
        task?.resume()
    }
    private func stop() {
        running = false; manager.stopUpdatingLocation(); timer?.invalidate(); timer = nil
        generation += 1; task?.cancel(); task = nil
    }
}
