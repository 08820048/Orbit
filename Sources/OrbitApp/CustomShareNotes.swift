import OrbitCore
import SwiftUI

/// Lets the editor preview of the card open a note popover on an app. Never set for exports.
struct NoteEditing {
    var editingKey: String?
    var select: (String?) -> Void
    var text: (String) -> Binding<String>
}

/// The popover shown when an app on the card is clicked: one line, up to `ShareNote.maxLength` characters.
struct NoteEditorView: View {
    let name: String
    @Binding var text: String
    let done: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(name) 的短评").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(text.count) / \(ShareNote.maxLength)").font(.system(size: 11)).foregroundStyle(Theme.text2).monospacedDigit()
            }
            TextField("一句话", text: $text)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($focused)
                .padding(.horizontal, 10).frame(height: 32)
                .background(Theme.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1))
                .onSubmit(done)
            FlowLayout(spacing: 6) {
                ForEach(ShareNote.suggestions, id: \.self) { s in
                    Text(s).font(.system(size: 11)).foregroundStyle(Theme.text2)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Theme.control, in: Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { text = s; done() }
                }
            }
            Text("回车确认 · 留空则不显示短评").font(.system(size: 11)).foregroundStyle(Theme.text2)
        }
        .padding(14).frame(width: 240)
        .onAppear { focused = true }
    }
}
