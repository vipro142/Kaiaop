import SwiftUI

struct BluetoothTallyView: View {
    @ObservedObject var tally: BluetoothTally
    @Environment(\.dismiss) private var dismiss
    @State private var settingsPresented = false
    private let ink = Color(red: 0.043, green: 0.071, blue: 0.125)
    private let panel = Color(red: 0.078, green: 0.125, blue: 0.192)
    private let accent = Color(red: 0.39, green: 0.70, blue: 1)
    var body: some View {
        NavigationView {
            ZStack {
                ink.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text(tally.rememberedName.isEmpty ? "Chọn một Tally" : tally.rememberedName).font(.headline).foregroundColor(.white)
                    HStack(spacing: 12) {
                        control("Search") { tally.scan() }
                        control("Stop") { tally.disconnect() }
                        if tally.connectedID != nil { control("Setting") { tally.openSettings(); settingsPresented = true }.accessibilityIdentifier("bleTallySettingButton") }
                    }
                    ScrollView {
                        VStack(spacing: 8) {
                            if tally.devices.isEmpty { Text(tally.scanning ? "Đang tìm…" : "Bấm Search để tìm Tally").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                            ForEach(tally.devices) { device in
                                Button { tally.connect(device) } label: {
                                    HStack { Text(device.name); Spacer(); if tally.connectedID == device.id { Text("Đã kết nối").font(.caption); Image(systemName: "checkmark.circle.fill") } else if device.claimed { Text("Đã được chọn").font(.caption) } }
                                        .padding(14).frame(maxWidth: .infinity).background(panel).cornerRadius(10)
                                }.foregroundColor(accent)
                            }
                        }
                    }
                    Text(tally.status).font(.subheadline).foregroundColor(tally.connectedID != nil ? .green : tally.status.hasPrefix("Thất bại") ? .red : .secondary).accessibilityIdentifier("bleTallyStatus")
                    Spacer(minLength: 0)
                }.padding(20)
            }.navigationTitle("Tally Bluetooth")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Đóng") { dismiss() } } }
        }.sheet(isPresented: $settingsPresented) { TallyBrightnessSettingsView(tally: tally) }.onChange(of: tally.connectedID) { if $0 == nil { settingsPresented = false } }.alert(isPresented: Binding(get: { tally.selectionNotice != nil }, set: { if !$0 { tally.selectionNotice = nil } })) { Alert(title: Text("Tally đã được chọn"), message: Text(tally.selectionNotice ?? ""), primaryButton: .destructive(Text("Chuyển sang thiết bị này")) { tally.confirmTakeover() }, secondaryButton: .cancel(Text("Chọn khác")) { tally.dismissSelection() }) }.navigationViewStyle(.stack).preferredColorScheme(.dark).accentColor(accent)
    }
    private func control(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical,12).background(panel).cornerRadius(10) }.foregroundColor(accent)
    }
}

private struct TallyBrightnessSettingsView: View {
    @ObservedObject var tally: BluetoothTally
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text(tally.rememberedName).font(.headline)
                Text("Độ sáng \(tally.brightnessSelection) / 5").font(.title2)
                Slider(value: Binding(get: { Double(tally.brightnessSelection) }, set: { tally.setBrightness(Int($0.rounded())) }), in: 1...5, step: 1).disabled(!tally.canAdjustBrightness).accessibilityIdentifier("bleTallyBrightnessSlider")
                HStack { Text("1 Min"); Spacer(); Text("5 Max") }.foregroundColor(.secondary)
                HStack(spacing: 16) {
                    Button("−") { tally.setBrightness(tally.brightnessSelection-1) }.frame(maxWidth: .infinity)
                    Button("+") { tally.setBrightness(tally.brightnessSelection+1) }.frame(maxWidth: .infinity)
                }.font(.title).buttonStyle(.bordered).disabled(!tally.canAdjustBrightness)
                Text(tally.brightnessStatus).font(.subheadline).foregroundColor(tally.brightnessStatus.hasPrefix("Thất bại") ? .red : .secondary)
                Spacer()
            }.padding(20).navigationTitle("Setting Tally").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Đóng") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark)
    }
}
