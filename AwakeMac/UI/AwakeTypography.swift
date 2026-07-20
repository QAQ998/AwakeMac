import SwiftUI

/// Raises every semantic SwiftUI text style by one Dynamic Type step while
/// preserving the user's accessibility text-size preference.
private struct AwakeTextSizeModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var currentSize

    func body(content: Content) -> some View {
        content.dynamicTypeSize(nextSize(after: currentSize))
    }

    private func nextSize(after size: DynamicTypeSize) -> DynamicTypeSize {
        switch size {
        case .xSmall: .small
        case .small: .medium
        case .medium: .large
        case .large: .xLarge
        case .xLarge: .xxLarge
        case .xxLarge: .xxxLarge
        case .xxxLarge: .accessibility1
        case .accessibility1: .accessibility2
        case .accessibility2: .accessibility3
        case .accessibility3: .accessibility4
        case .accessibility4: .accessibility5
        case .accessibility5: .accessibility5
        @unknown default: size
        }
    }
}

extension View {
    func awakeTextOneStepLarger() -> some View {
        modifier(AwakeTextSizeModifier())
    }
}
