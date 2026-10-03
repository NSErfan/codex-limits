enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly
    case textOnly
    case iconAndText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .textOnly: "Text only"
        case .iconAndText: "Icon and text"
        }
    }
}
