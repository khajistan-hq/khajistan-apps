import SwiftUI

enum Brand {
    static let yellow = Color(red: 243 / 255, green: 251 / 255, blue: 4 / 255)
    static let green = Color(red: 0, green: 111 / 255, blue: 0)
}

struct ArchiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(configuration.isPressed ? Brand.yellow : Color.black)
            .background(configuration.isPressed ? Color.black : Brand.yellow)
            .overlay { Rectangle().stroke(.black, lineWidth: 1) }
    }
}

struct SectionBand: View {
    let title: String
    var body: some View {
        Text(title.uppercased()).font(.caption.weight(.bold)).tracking(1.5)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 12)
            .foregroundStyle(Brand.yellow).background(Brand.green)
    }
}
