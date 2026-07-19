import SwiftUI
import Charts

/// Rolling line chart of recent water temperature vs. setpoint, built from the
/// in-memory sample window in SpaViewModel.
struct TempHistoryView: View {
    let samples: [TempSample]

    private let waterColor = Color.cyan
    private let setpointColor = Color.orange

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TEMPERATURE HISTORY")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                legend
            }

            if samples.count < 2 {
                emptyState
            } else {
                chart
            }
        }
        .padding()
        .background(Color(red: 0.14, green: 0.20, blue: 0.28))
        .cornerRadius(16)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            swatch(waterColor, "Water")
            swatch(setpointColor, "Target")
        }
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 12, height: 3)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2).foregroundColor(.secondary)
                Text("Collecting data…")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(height: 120)
    }

    private var chart: some View {
        Chart(samples) { sample in
            LineMark(
                x: .value("Time", sample.date),
                y: .value("Temperature", sample.tempF),
                series: .value("Series", "Water")
            )
            .foregroundStyle(waterColor)
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Time", sample.date),
                y: .value("Setpoint", sample.setpoint),
                series: .value("Series", "Target")
            )
            .foregroundStyle(setpointColor)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let t = value.as(Double.self) {
                        Text("\(Int(t))°")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .frame(height: 180)
    }

    /// Y range spanning both series with a couple degrees of padding.
    private var yDomain: ClosedRange<Double> {
        let values = samples.map(\.tempF) + samples.map(\.setpoint)
        let lo = (values.min() ?? 60) - 2
        let hi = (values.max() ?? 105) + 2
        return lo...hi
    }
}
