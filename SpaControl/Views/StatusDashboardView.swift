import SwiftUI

struct StatusDashboardView: View {
    @EnvironmentObject var vm: SpaViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LastUpdatedLabel()

                if vm.isStale {
                    StaleStatusBanner(lastUpdate: vm.lastStatusDate)
                }

                TemperatureDialView()

                if vm.status?.fault == true {
                    FaultBannerView(code: vm.status?.faultCode ?? 0)
                }

                PumpControlView()
                LightEcoControlView()

                TempHistoryView(samples: vm.tempHistory)
            }
            .padding()
        }
    }
}

struct FaultBannerView: View {
    let code: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("FAULT — \(FaultCode.shortLabel(code))").bold()
                Text(FaultCode.description(code)).font(.caption)
            }
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.85))
        .foregroundColor(.white)
        .cornerRadius(12)
    }
}

#if DEBUG
#Preview("Dashboard") {
    ZStack {
        Color(red: 0.10, green: 0.15, blue: 0.22).ignoresSafeArea()
        StatusDashboardView()
            .environmentObject(SpaViewModel.preview())
    }
    .preferredColorScheme(.dark)
}
#endif
