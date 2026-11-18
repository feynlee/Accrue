import Foundation

/// A lift done on a plate-loaded lever instead of a free bar: a T-bar or chest-supported
/// lever row, a lever deadlift. The body does the free-bar lift as another group stages it;
/// in place of the bar the hands hold the crossbar of a fork whose two arms turn on an axle
/// in front of the lifter, with the plates on the arms beside the hands.
struct MachineForkLeverStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    let body: Body3D
    let inner: any BodyStaging
    /// The middle of the axle, and each arm's distance from the middle.
    let pivot: V
    let half: Double
    /// A belt squat machine's lever lies under the bar, which hangs from its end by a strap
    /// of this length.
    let strapped: Bool
    let strap: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.equipment == "machine", let name = Self.freeBar(guide) else { return nil }
        strapped = MachineStagings.words(guide).contains("belt")
        var free = guide
        free.equipment = "barbell"
        free.exerciseName = name
        guard let inner = Stagings.make(free, body) else { return nil }
        self.body = body
        self.inner = inner

        // Where the free bar goes, and how wide the hands are on it.
        var ys: [Double] = [], zs: [Double] = [], wide = 0.2
        for k in 0...24 {
            let made = inner.frame(Figure.smooth(guide.keyframes, at: Double(k) / 24))
            guard let bar = MachineSmithStaging.bar(made.props) else { return nil }
            ys.append(bar.center[1])
            zs.append(bar.center[2])
            for s in ["r", "l"] { wide = max(wide, abs(made.body.heads["f3a.\(s)"]?[0] ?? 0)) }
        }
        guard let front = ys.min(), let low = zs.min(), let high = zs.max() else { return nil }
        half = wide + 0.1
        strap = max(0.05, low - 0.12)
        var p = inner.fixed
        if strapped {
            // One lever along the floor from a low axle out in front.
            let pivot = V(0, front - 0.95, 0.24)
            self.pivot = pivot
            for x in [-0.09, 0.09] { p.append(Plan.box(V(x, pivot.y, (pivot.z + 0.05) / 2), (0.05, 0.06, pivot.z + 0.05), .metal)) }
            p.append(Plan.rod(pivot - V(0.12, 0, 0), pivot + V(0.12, 0, 0), 0.022, .metal))
            p.append(Plan.box(V(0, pivot.y, 0.02), (0.6, 0.08, 0.04), .metal))
            fixed = p
            return
        }
        // The axle is level with the middle of the bar's travel, so the arms swing evenly.
        let pivot = V(0, front - 0.95, max(0.3, (low + high) / 2))
        self.pivot = pivot
        for m in [-1.0, 1.0] {
            let x = m * (half + 0.07)
            p.append(Plan.box(V(x, pivot.y, (pivot.z + 0.05) / 2), (0.06, 0.06, pivot.z + 0.05), .metal))
            p.append(Plan.box(V(x, pivot.y + 0.2, 0.025), (0.07, 0.8, 0.05), .metal))
        }
        p.append(Plan.rod(pivot - V(half + 0.07, 0, 0), pivot + V(half + 0.07, 0, 0), 0.025, .metal))
        p.append(Plan.box(V(0, pivot.y, 0.025), (2 * half + 0.2, 0.07, 0.05), .metal))
        fixed = p
    }

    /// The free-bar lift that is the same movement, or nil for a lever lift this does not show.
    static func freeBar(_ guide: HowToGuide) -> String? {
        let words = MachineStagings.words(guide)
        // One hand on its own lever is a different machine.
        guard words.isDisjoint(with: ["single", "one", "banded", "sled"]) else { return nil }
        switch (guide.familyID, guide.subtypeID) {
        case ("row", "chest-supported"):
            guard words.isSubset(of: ["lever", "incline", "prone", "row", "neutral", "grip", "lying", "t", "bar", "bent", "over",
                                      "with", "chest", "support", "wide"]) else { return nil }
            return "barbell bent over row (chest supported)"
        case ("row", nil):
            guard words.contains("row"), !words.isDisjoint(with: ["t", "bent"]),
                  words.isSubset(of: ["lever", "t", "bar", "row", "close", "grip", "plate", "loaded", "reverse", "bent", "over",
                                      "with", "v", "wide"]) else { return nil }
            return "barbell bent over row"
        case ("deadlift", nil):
            // On a belt squat machine the lever is under the bar, which hangs from it by a strap.
            if words.contains("belt") {
                return words.isSubset(of: ["lever", "belt", "deadlift", "straight", "bar"]) ? "barbell deadlift" : nil
            }
            return words == ["lever", "deadlift"] ? "barbell deadlift" : nil
        case ("deadlift", "romanian"):
            if words.contains("belt") {
                return words.isSubset(of: ["lever", "belt", "romanian", "deadlift", "straight", "bar"]) ? "barbell romanian deadlift" : nil
            }
            if words == ["lever", "t", "bar", "romanian", "deadlift"] { return "barbell romanian deadlift" }
            return words == ["lever", "romanian", "deadlift", "plate", "loaded"] ? "barbell stiff legged deadlift" : nil
        case ("hip-thrust-bridge", nil):
            // The lever's bar lies over the hips where the free bar would, hinged beyond the feet.
            return words.isSubset(of: ["lever", "hip", "thrust", "plate", "loaded", "v", "2"]) ? "barbell hip thrust" : nil
        default: return nil
        }
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let made = inner.frame(pose)
        guard let bar = MachineSmithStaging.bar(made.props) else { return made }
        let mid = V(0, bar.center[1], bar.center[2])
        // The free bar and its plates go; the fork's crossbar is where the hands already are.
        var p = made.props.filter { abs($0.center[1] - mid.y) > 0.02 || abs($0.center[2] - mid.z) > 0.02 }
        p.append(Plan.rod(mid - V(half, 0, 0), mid + V(half, 0, 0), bar.size[0] / 2, .dark))
        if strapped {
            // The strap down from the middle of the bar to the lever's end, and the plates
            // on the lever a little way toward its axle, clear of the toes.
            let end = mid - V(0, 0, strap)
            p.append(Plan.rod(mid, end, 0.006, .cable))
            p.append(Plan.rod(pivot, end, 0.028, .metal))
            p.append(Plan.ball(end, 0.03, .metal))
            let peg = end + (pivot - end).unit * 0.27
            p.append(Plan.rod(peg - V(0.13, 0, 0), peg + V(0.13, 0, 0), 0.02, .metal))
            for x in [-0.085, 0.085] {
                p.append(Plan.disc(peg + V(x, 0, 0), axis: V(1, 0, 0), radius: min(0.15, max(0.05, peg.z - 0.01)), thickness: 0.05, .plate))
            }
            return (made.body, p)
        }
        for m in [-1.0, 1.0] {
            let end = mid + V(m * half, 0, 0), hinge = pivot + V(m * half, 0, 0)
            p.append(Plan.rod(end, hinge, 0.022, .metal))
            p.append(Plan.ball(end, 0.024, .metal))
            // A plate on a peg outside each arm, a little way up it from the hands.
            let peg = end + (hinge - end).unit * 0.24
            p.append(Plan.rod(peg, peg + V(m * 0.12, 0, 0), 0.02, .metal))
            p.append(Plan.disc(peg + V(m * 0.07, 0, 0), axis: V(1, 0, 0), radius: min(0.17, max(0.06, peg.z - 0.01)), thickness: 0.06, .plate))
        }
        return (made.body, p)
    }
}
