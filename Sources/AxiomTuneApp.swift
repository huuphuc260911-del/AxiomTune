import SwiftUI
import Foundation
import UIKit

enum DeviceTier: String, Codable {
    case low, mid, high
    var label: String {
        switch self { case .low: return "Low ≤3GB"; case .mid: return "Mid 4–6GB"; case .high: return "High 8GB+" }
    }
}

struct DeviceProfile: Codable, Equatable {
    var model = "iPhone"
    var ramGB = 6
    var refreshHz = 60
    var screenInch = 6.1
    var dpi = 460
    var tier: DeviceTier { ramGB <= 3 ? .low : (ramGB <= 6 ? .mid : .high) }
}

struct SensitivityPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var general: Int
    var redDot: Int
    var scope2x: Int
    var scope4x: Int
    var sniper: Int
    var freeLook: Int
    var dpi: Int
}

struct TrainingLog: Codable, Identifiable {
    var id = UUID()
    var presetID: UUID
    var spray: Int
    var flick: Int
    var stab: Int
    var avg: Double { Double(spray + flick + stab) / 3.0 }
}

enum Engine {
    static let base: [DeviceTier: [String: Int]] = [
        .low:  ["g": 178, "rd": 172, "s2": 152, "s4": 138, "sn": 82, "fl": 128],
        .mid:  ["g": 172, "rd": 166, "s2": 148, "s4": 134, "sn": 78, "fl": 122],
        .high: ["g": 166, "rd": 160, "s2": 142, "s4": 128, "sn": 74, "fl": 116]
    ]
    static func rDelta(_ hz: Int) -> Int {
        switch hz { case ..<75: return 0; case ..<100: return -2; case ..<130: return -4; case ..<160: return -6; default: return -7 }
    }
    static func sDelta(_ i: Double) -> Int {
        if i >= 6.9 { return 4 }; if i >= 6.6 { return 3 }; if i >= 6.3 { return 2 }; if i >= 6.0 { return 1 }; return 0
    }
    static func recDPI(_ d: DeviceProfile) -> Int {
        var v = 460
        if d.refreshHz >= 120 { v -= 15 }
        if d.screenInch >= 6.7 { v += 10 }
        return max(400, min(520, v))
    }
    static func compute(_ d: DeviceProfile) -> SensitivityPreset {
        let b = base[d.tier] ?? base[.mid]!
        let dd = rDelta(d.refreshHz) + sDelta(d.screenInch)
        func t(_ k: String) -> Int {
            k == "sn" ? max(30, min(100, (b[k] ?? 76) + rDelta(d.refreshHz)/3)) : max(50, min(200, (b[k] ?? 150) + dd))
        }
        return .init(name: "Auto \(d.tier.rawValue) \(d.refreshHz)Hz", general: t("g"), redDot: t("rd"), scope2x: t("s2"), scope4x: t("s4"), sniper: t("sn"), freeLook: t("fl"), dpi: recDPI(d))
    }
    static func calibrate(_ p: SensitivityPreset, _ logs: [TrainingLog]) -> SensitivityPreset {
        guard !logs.isEmpty else { return p }
        let n = Double(logs.count)
        let sp = Double(logs.map(\.spray).reduce(0,+))/n
        let fk = Double(logs.map(\.flick).reduce(0,+))/n
        let st = Double(logs.map(\.stab ).reduce(0,+))/n
        var o = p
        if sp < 6 { o.scope2x = max(100,o.scope2x-3); o.scope4x = max(90,o.scope4x-3); o.redDot = max(80,o.redDot-2) }
        if fk < 6 { o.general = min(200,o.general+3); o.freeLook = min(200,o.freeLook+2) }
        if st < 6 { o.scope4x = max(80,o.scope4x-4); o.freeLook = min(200,o.freeLook+3) }
        return o
    }
}

@MainActor final class Store: ObservableObject {
    @Published var presets: [SensitivityPreset] = []
    @Published var logs: [TrainingLog] = []
    @Published var device = DeviceProfile() { didSet { save() } }
    init() { load() }
    func auto() { presets.insert(Engine.compute(device), at: 0); save() }
    func log(_ l: TrainingLog) { logs.insert(l, at: 0); save() }
    func calibrate(_ p: SensitivityPreset) -> SensitivityPreset { Engine.calibrate(p, logs.filter { $0.presetID == p.id }) }
    func del(_ id: UUID) { presets.removeAll { $0.id == id }; logs.removeAll { $0.presetID == id }; save() }
    private func save() {
        let e = JSONEncoder()
        UserDefaults.standard.set(try? e.encode(presets), forKey: "P")
        UserDefaults.standard.set(try? e.encode(logs), forKey: "L")
        UserDefaults.standard.set(try? e.encode(device), forKey: "D")
    }
    private func load() {
        let d = JSONDecoder()
        if let r = UserDefaults.standard.data(forKey: "P"), let v = try? d.decode([SensitivityPreset].self, from: r) { presets = v }
        if let r = UserDefaults.standard.data(forKey: "L"), let v = try? d.decode([TrainingLog].self, from: r) { logs = v }
        if let r = UserDefaults.standard.data(forKey: "D"), let v = try? d.decode(DeviceProfile.self, from: r) { device = v }
    }
}

@main
struct AxiomTuneApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store).preferredColorScheme(.dark) }
    }
}

struct ContentView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        TabView {
            PresetsView().tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
            DeviceView().tabItem { Label("Device", systemImage: "iphone") }
            LogsView().tabItem { Label("Train", systemImage: "chart.bar") }
            ExportView().tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }.accentColor(.green)
    }
}

struct PresetsView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        NavigationView {
            List {
                Section {
                    Button { s.auto() } label: { Label("Auto-generate", systemImage: "bolt.fill").foregroundColor(.green) }
                }
                Section("Presets") {
                    if s.presets.isEmpty { Text("Chưa có — bấm Auto").foregroundColor(.gray).font(.caption) }
                    ForEach(s.presets) { p in
                        NavigationLink(destination: PresetEdit(preset: p)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name).font(.headline)
                                Text("G\(p.general) RD\(p.redDot) 2x\(p.scope2x) 4x\(p.scope4x) Sn\(p.sniper) FL\(p.freeLook)").font(.caption2).foregroundColor(.gray)
                                Text("DPI \(p.dpi)").font(.caption2).foregroundColor(.green)
                            }
                        }
                    }.onDelete { i in i.map { s.presets[$0].id }.forEach(s.del) }
                }
            }.navigationTitle("AxiomTune")
        }
    }
}

struct PresetEdit: View {
    @EnvironmentObject var s: Store
    @State var preset: SensitivityPreset
    var body: some View {
        Form {
            Section("Name") { TextField("Name", text: $preset.name) }
            Section("Sensitivity") {
                Stepper("General  \(preset.general)",  value: $preset.general,  in: 50...200)
                Stepper("Red Dot  \(preset.redDot)",   value: $preset.redDot,   in: 50...200)
                Stepper("2x \(preset.scope2x)",        value: $preset.scope2x,  in: 50...200)
                Stepper("4x \(preset.scope4x)",        value: $preset.scope4x,  in: 40...200)
                Stepper("Sniper \(preset.sniper)",     value: $preset.sniper,   in: 30...120)
                Stepper("FreeLook \(preset.freeLook)", value: $preset.freeLook, in: 50...200)
                Stepper("DPI \(preset.dpi)",           value: $preset.dpi,      in: 400...520)
            }
            Section {
                Button { preset = s.calibrate(preset) } label: { Label("Calibrate", systemImage: "wand.and.stars").foregroundColor(.green) }
            }
        }.navigationTitle("Edit")
    }
}

struct DeviceView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        NavigationView {
            Form {
                Section("Device") {
                    TextField("Model", text: $s.device.model)
                    Stepper("RAM \(s.device.ramGB)GB", value: $s.device.ramGB, in: 2...16)
                    Stepper("Refresh \(s.device.refreshHz)Hz", value: $s.device.refreshHz, in: 60...144, step: 30)
                    HStack {
                        Text("Inch")
                        Slider(value: $s.device.screenInch, in: 5.0...7.5, step: 0.1)
                        Text(String(format: "%.1f", s.device.screenInch))
                    }
                    Stepper("DPI \(s.device.dpi)", value: $s.device.dpi, in: 400...520)
                }
                Section("Info") {
                    Text("Tier: \(s.device.tier.label)").foregroundColor(.green)
                    Text("Rec DPI: \(Engine.recDPI(s.device))").foregroundColor(.gray)
                }
            }.navigationTitle("Device")
        }
    }
}

struct LogsView: View {
    @EnvironmentObject var s: Store
    @State private var sel: UUID?
    @State private var sp = 5, fk = 5, st = 5
    var body: some View {
        NavigationView {
            Form {
                Section("Preset") {
                    Picker("Preset", selection: $sel) { ForEach(s.presets) { Text($0.name).tag(Optional($0.id)) } }
                }
                Section("Scores") {
                    Stepper("Spray \(sp)/10", value: $sp, in: 0...10)
                    Stepper("Flick \(fk)/10", value: $fk, in: 0...10)
                    Stepper("Stab \(st)/10", value: $st, in: 0...10)
                }
                Button {
                    if let id = sel { s.log(TrainingLog(presetID: id, spray: sp, flick: fk, stab: st)) }
                } label: { Label("Save", systemImage: "checkmark.circle").foregroundColor(.green) }
                Section("History") {
                    ForEach(s.logs) { l in Text("S\(l.spray) F\(l.flick) St\(l.stab) → \(String(format:"%.1f", l.avg))").font(.caption) }
                }
            }.navigationTitle("Train").onAppear { sel = s.presets.first?.id }
        }
    }
}

struct ExportView: View {
    @EnvironmentObject var s: Store
    @State private var url: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "doc.badge.arrow.up").font(.system(size: 48)).foregroundColor(.green)
                Text("Export .mobileconfig").font(.headline)
                Text("Chỉ chứa preset tham chiếu + Web Clip. Không đụng game.").font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
                Button { 
                    url = Exporter.export(s.presets.first, s.device) 
                    if url != nil { showShareSheet = true }
                } label: { Label("Generate", systemImage: "doc.badge.plus") }.buttonStyle(.borderedProminent).tint(.green).disabled(s.presets.isEmpty)
                
                if let u = url {
                    Text(u.lastPathComponent).font(.caption2).foregroundColor(.gray)
                }
                Spacer()
            }.padding().navigationTitle("Export")
            .sheet(isPresented: $showShareSheet) {
                if let u = url {
                    ShareSheet(activityItems: [u])
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct Exporter {
    static func export(_ p: SensitivityPreset?, _ d: DeviceProfile) -> URL? {
        guard let p else { return nil }
        let u1 = UUID().uuidString, u2 = UUID().uuidString, u3 = UUID().uuidString
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>PayloadContent</key><array>
        <dict><key>PayloadType</key><string>com.axiom.ff.sens</string>
        <key>PayloadIdentifier</key><string>com.axiom.ff.sens</string>
        <key>PayloadUUID</key><string>\(u2)</string>
        <key>PayloadVersion</key><integer>1</integer>
        <key>PayloadDisplayName</key><string>FF Sens</string>
        <key>PresetPlain</key><dict>
        <key>general</key><integer>\(p.general)</integer>
        <key>red_dot</key><integer>\(p.redDot)</integer>
        <key>scope_2x</key><integer>\(p.scope2x)</integer>
        <key>scope_4x</key><integer>\(p.scope4x)</integer>
        <key>sniper</key><integer>\(p.sniper)</integer>
        <key>free_look</key><integer>\(p.freeLook)</integer>
        </dict></dict>
        <dict><key>PayloadType</key><string>com.apple.webClip.managed</string>
        <key>PayloadIdentifier</key><string>com.axiom.ff.wc</string>
        <key>PayloadUUID</key><string>\(u3)</string>
        <key>PayloadVersion</key><integer>1</integer>
        <key>Label</key><string>FF</string>
        <key>URL</key><string>https://ff.garena.com/</string>
        <key>IsRemovable</key><true/></dict>
        </array>
        <key>PayloadType</key><string>Configuration</string>
        <key>PayloadIdentifier</key><string>com.axiom.ff.ref</string>
        <key>PayloadUUID</key><string>\(u1)</string>
        <key>PayloadVersion</key><integer>1</integer>
        <key>PayloadDisplayName</key><string>Axiom FF Ref</string>
        <key>PayloadRemovalDisallowed</key><false/>
        </dict></plist>
        """
        let name = "AxiomFF_\(Int(Date().timeIntervalSince1970)).mobileconfig"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? xml.data(using: .utf8)?.write(to: url)
        return url
    }
}
