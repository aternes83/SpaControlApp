import SwiftUI

/// Nest-style temperature dial: a 270° arc showing current water temp (fill +
/// dot) with a draggable target knob. Drag anywhere on the ring to set the
/// target; the value is sent to the board on release.
struct TemperatureDialView: View {
    @EnvironmentObject var vm: SpaViewModel

    // Geometry — matches the design mockup.
    private let startDeg = 225.0        // clockwise from 12 o'clock
    private let sweepDeg = 270.0
    private let minF = 60.0             // dial range (sensor can swing wide)
    private let maxF = 110.0
    private let spMin = 60.0            // target clamp (app setpoint limits)
    private let spMax = 104.0
    private let lineWidth: CGFloat = 16

    @State private var dragging = false
    /// Optimistic target held from a drag until the board echoes it back, so the
    /// knob doesn't snap to the old setpoint between release and confirmation.
    @State private var localTarget: Double?

    private var target: Double { localTarget ?? vm.status?.setpoint ?? 102 }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("WATER TEMP")
                    .font(.caption).fontWeight(.bold).tracking(1.2)
                    .foregroundColor(Theme.muted)
                Spacer()
                Text("Drag ring to set target")
                    .font(.caption2).foregroundColor(Theme.muted.opacity(0.7))
            }

            GeometryReader { geo in
                ZStack {
                    Canvas { ctx, size in draw(&ctx, size: size) }
                    readout
                }
                .contentShape(Rectangle())
                .gesture(drag(in: geo.size))
            }
            .frame(height: 208)

            HStack {
                Text("\(Int(minF))°")
                Spacer()
                Text("\(Int(maxF))°")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(Theme.muted.opacity(0.7))
            .padding(.horizontal, 26)
        }
        .padding()
        .background(Theme.card)
        .cornerRadius(16)
        .onChange(of: vm.status?.setpoint) { newValue in
            // Clear the optimistic target once the board confirms it.
            if let lt = localTarget, let sp = newValue,
               Int(sp.rounded()) == Int(lt.rounded()) {
                localTarget = nil
            }
        }
    }

    // MARK: Center readout

    private var readout: some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(vm.status.map { String(Int($0.tempF.rounded())) } ?? "--")
                    .font(.system(size: 62, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text("°F")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.muted)
            }
            Text("Target \(Int(target.rounded()))°")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(Theme.heat)
                .opacity(dragging ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: dragging)
        }
        .offset(y: -4)
    }

    // MARK: Canvas drawing

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let c = center(size), r = radius(size)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

        // Track
        ctx.stroke(arc(size, startDeg, startDeg + sweepDeg), with: .color(Theme.track), style: style)

        // Current-temperature fill + dot
        if let cur = vm.status?.tempF {
            let heating = vm.status?.heater == true
            let prog = arc(size, startDeg, angle(of: cur))
            if heating {
                var g = ctx
                g.addFilter(.shadow(color: Theme.heat.opacity(0.6), radius: 6))
                g.stroke(prog, with: .color(Theme.heat), style: style)
            } else {
                ctx.stroke(prog, with: .color(Theme.water), style: style)
            }
            let cp = point(angle(of: cur), r, c)
            ctx.fill(Path(ellipseIn: CGRect(x: cp.x - 4.5, y: cp.y - 4.5, width: 9, height: 9)),
                     with: .color(.white))
        }

        // Draggable target knob (amber, dark rim, white core)
        let k = point(angle(of: target), r, c)
        let knob = CGRect(x: k.x - 11, y: k.y - 11, width: 22, height: 22)
        ctx.fill(Path(ellipseIn: knob), with: .color(Theme.heat))
        ctx.stroke(Path(ellipseIn: knob), with: .color(Theme.screenBg), lineWidth: 2.5)
        ctx.fill(Path(ellipseIn: CGRect(x: k.x - 3.6, y: k.y - 3.6, width: 7.2, height: 7.2)),
                 with: .color(.white))
    }

    private func arc(_ size: CGSize, _ a0: Double, _ a1: Double) -> Path {
        var p = Path()
        let c = center(size), r = radius(size)
        let steps = 90
        for i in 0...steps {
            let a = a0 + (a1 - a0) * Double(i) / Double(steps)
            let pt = point(a, r, c)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }

    // MARK: Geometry helpers

    private func center(_ s: CGSize) -> CGPoint { CGPoint(x: s.width / 2, y: s.height / 2) }
    private func radius(_ s: CGSize) -> CGFloat { min(s.width, s.height) / 2 - 15 }

    /// Point on the ring for an angle in degrees measured clockwise from top.
    private func point(_ deg: Double, _ r: CGFloat, _ c: CGPoint) -> CGPoint {
        let rad = deg * .pi / 180
        return CGPoint(x: c.x + r * CGFloat(sin(rad)), y: c.y - r * CGFloat(cos(rad)))
    }

    private func angle(of tempF: Double) -> Double {
        let t = min(1, max(0, (tempF - minF) / (maxF - minF)))
        return startDeg + sweepDeg * t
    }

    // MARK: Drag → target

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard vm.connectionState == .connected else { return }
                dragging = true
                localTarget = temp(at: g.location, center: center(size))
            }
            .onEnded { _ in
                guard dragging else { return }
                dragging = false
                if let lt = localTarget { vm.sendCommand(SpaCommand(setTemp: lt.rounded())) }
            }
    }

    private func temp(at p: CGPoint, center c: CGPoint) -> Double {
        var a = atan2(Double(p.x - c.x), Double(-(p.y - c.y))) * 180 / .pi  // clockwise from top
        if a < 0 { a += 360 }
        let endA = startDeg + sweepDeg - 360                                // 135°
        let aCont: Double
        if a >= startDeg { aCont = a }                                      // 225–360
        else if a <= endA { aCont = a + 360 }                              // 0–135 → 360–495
        else { aCont = (a < 180) ? endA + 360 : startDeg }                 // bottom dead-zone
        let t = (aCont - startDeg) / sweepDeg
        let value = minF + t * (maxF - minF)
        return min(spMax, max(spMin, value))
    }
}

#if DEBUG
#Preview("Dial — heating") {
    ZStack {
        Color(red: 0.10, green: 0.15, blue: 0.22).ignoresSafeArea()
        TemperatureDialView()
            .environmentObject(SpaViewModel.preview(.sample(tempF: 96, setpoint: 102, heater: true)))
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Dial — idle at 62°") {
    ZStack {
        Color(red: 0.10, green: 0.15, blue: 0.22).ignoresSafeArea()
        TemperatureDialView()
            .environmentObject(SpaViewModel.preview(.sample(tempF: 62, setpoint: 62, heater: false)))
            .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
