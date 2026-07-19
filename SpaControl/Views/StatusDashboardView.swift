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

                TemperatureControlView()

                if vm.status?.fault == true {
                    FaultBannerView(code: vm.status?.faultCode ?? 0)
                }

                PumpControlView()
                LightEcoControlView()
            }
            .padding()
        }
    }
}

struct FaultBannerView: View {
    let code: Int

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("FAULT — Code \(code)").bold()
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.85))
        .foregroundColor(.white)
        .cornerRadius(12)
    }
}
