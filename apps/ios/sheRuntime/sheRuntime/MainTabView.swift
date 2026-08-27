import SwiftUI

private enum MainSection: Int, CaseIterable {
    case today, map, insights, ask

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .map: "waveform.path.ecg"
        case .insights: "sparkles"
        case .ask: "bubble.left"
        }
    }
}

struct MainTabView: View {
    @State private var selection: MainSection = {
        let page = Int(ProcessInfo.processInfo.environment["SHOT_PAGE"] ?? "") ?? 0
        return MainSection(rawValue: min(page, 3)) ?? .today
    }()
    @State private var showsProfile = false
    @State private var isVoiceActive = false

    var body: some View {
        ZStack(alignment: .bottom) {
            page.padding(.bottom, 82)

            LinearGradient(colors: [AppPalette.background.opacity(0), AppPalette.background], startPoint: .top, endPoint: .bottom)
                .frame(height: 112)
                .allowsHitTesting(false)

            dock.padding(.horizontal, 16).padding(.bottom, 8)

            if selection != .ask && !showsProfile {
                voiceButton.offset(x: 72, y: -82)
            }
        }
        .background(AppPalette.background.ignoresSafeArea())
        .overlay {
            if showsProfile {
                ProfileView()
                    .overlay(alignment: .topLeading) {
                        Button { showsProfile = false } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 42, height: 42)
                                .background(.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 16)
                        .padding(.top, 8)
                    }
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showsProfile)
    }

    @ViewBuilder private var page: some View {
        switch selection {
        case .today: TodayView { showsProfile = true }
        case .map: MapView()
        case .insights: InsightsView()
        case .ask: AskView()
        }
    }

    private var dock: some View {
        HStack {
            ForEach(MainSection.allCases, id: \.rawValue) { item in
                Button { selection = item } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(selection == item ? .white : AppPalette.faint)
                        .frame(width: 50, height: 50)
                        .background(selection == item ? AppPalette.ink : .clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 66)
        .background(.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
    }

    private var voiceButton: some View {
        Button { isVoiceActive.toggle() } label: {
            ZStack(alignment: .leading) {
                Capsule().fill(AppPalette.ink)
                Image("MascotDance")
                    .resizable().scaledToFit()
                    .frame(width: 54, height: 60)
                    .offset(x: 7, y: -5)
                Image(systemName: isVoiceActive ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 82)
            }
            .frame(width: 116, height: 52)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice check-in")
    }
}

enum AppPalette {
    static let green = Color(red: 104 / 255, green: 195 / 255, blue: 0)
    static let blue = Color(red: 174 / 255, green: 202 / 255, blue: 251 / 255)
    static let ink = Color(red: 22 / 255, green: 21 / 255, blue: 17 / 255)
    static let muted = Color(red: 138 / 255, green: 138 / 255, blue: 132 / 255)
    static let faint = Color(red: 181 / 255, green: 181 / 255, blue: 174 / 255)
    static let background = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
}

#Preview { MainTabView() }
