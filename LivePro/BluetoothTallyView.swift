import SwiftUI

struct BluetoothTallyView: View {
    @ObservedObject var tally: BluetoothTally
    @Environment(\.dismiss) private var dismiss
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
        }.alert(isPresented: Binding(get: { tally.selectionNotice != nil }, set: { if !$0 { tally.selectionNotice = nil } })) { Alert(title: Text("Tally đã được chọn"), message: Text(tally.selectionNotice ?? ""), primaryButton: .destructive(Text("Chuyển sang thiết bị này")) { tally.confirmTakeover() }, secondaryButton: .cancel(Text("Chọn khác")) { tally.dismissSelection() }) }.navigationViewStyle(.stack).preferredColorScheme(.dark).accentColor(accent)
    }
    private func control(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical,12).background(panel).cornerRadius(10) }.foregroundColor(accent)
    }
}
