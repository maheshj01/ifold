import Foundation
import Combine

/// User-tunable parameters, persisted to UserDefaults.
final class Settings: ObservableObject {
    enum Style: String, CaseIterable, Identifiable {
        case silk, shade, frost
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    /// Lid angle (degrees) at or above which the desktop is flat and the overlay is gone.
    @Published var clearAngle: Double { didSet { save() } }
    /// Multiplier from "degrees the lid has dropped" to "degrees the picture leans".
    @Published var perspective: Double { didSet { save() } }
    /// How much the sheet curls (0 rigid plank … 1 flat at hinge, curling at the top).
    @Published var bend: Double { didSet { save() } }
    /// Motion-blur strength while the lid is moving (0 off … 2 heavy).
    @Published var motion: Double { didSet { save() } }
    /// Static gaussian blur (px) reached when the lid is well down.
    @Published var frost: Double { didSet { save() } }
    /// Lighting falloff strength (0–1).
    @Published var shade: Double { didSet { save() } }
    /// Track the real hinge, or drive the angle by hand with a slider.
    @Published var followLid: Bool { didSet { save() } }
    @Published var manualAngle: Double { didSet { save() } }
    @Published var sound: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        clearAngle = d.object(forKey: "clearAngle") as? Double ?? 100
        perspective = d.object(forKey: "perspective") as? Double ?? 1.0
        bend = d.object(forKey: "bend") as? Double ?? 0.55
        motion = d.object(forKey: "motion") as? Double ?? 1.0
        frost = d.object(forKey: "frost") as? Double ?? 0
        shade = d.object(forKey: "shade") as? Double ?? 0.6
        followLid = d.object(forKey: "followLid") as? Bool ?? true
        manualAngle = d.object(forKey: "manualAngle") as? Double ?? 70
        sound = d.object(forKey: "sound") as? Bool ?? true
    }

    func apply(_ style: Style) {
        switch style {
        case .silk:  perspective = 1.0; bend = 0.6; motion = 1.0; frost = 0;  shade = 0.5
        case .shade: perspective = 1.1; bend = 0.3; motion = 0.8; frost = 0;  shade = 1.0
        case .frost: perspective = 1.0; bend = 0.5; motion = 1.2; frost = 14; shade = 0.5
        }
    }

    private func save() {
        defaults.set(clearAngle, forKey: "clearAngle")
        defaults.set(perspective, forKey: "perspective")
        defaults.set(bend, forKey: "bend")
        defaults.set(motion, forKey: "motion")
        defaults.set(frost, forKey: "frost")
        defaults.set(shade, forKey: "shade")
        defaults.set(followLid, forKey: "followLid")
        defaults.set(manualAngle, forKey: "manualAngle")
        defaults.set(sound, forKey: "sound")
    }
}
