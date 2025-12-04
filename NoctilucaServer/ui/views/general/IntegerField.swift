import SwiftUI

/// TextField 래퍼: 숫자만 허용하면서 정수 타입 바인딩을 유지한다.
struct IntegerField<IntType: FixedWidthInteger, Label: View>: View {
    @Binding private var value: IntType
    @State private var text: String

    private let prompt: Text?
    private let label: () -> Label

    init(value: Binding<IntType>, prompt: Text? = nil, @ViewBuilder label: @escaping () -> Label) {
        self._value = value
        self._text = State(initialValue: String(value.wrappedValue))
        self.prompt = prompt
        self.label = label
    }

    var body: some View {
        TextField(text: textBinding, prompt: prompt, label: label)
            .onSubmit(commitIfNeeded)
            .onChange(of: value) { newValue in
                let newText = String(newValue)
                if newText != text {
                    text = newText
                }
            }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                text = sanitized(newValue)
                if let parsed = parsedValue(from: text) {
                    value = parsed
                }
            }
        )
    }

    private func commitIfNeeded() {
        guard let parsed = parsedValue(from: text) else {
            text = String(value)
            return
        }

        value = parsed
    }

    private func parsedValue(from raw: String) -> IntType? {
        guard let int64 = Int64(raw) else { return nil }
        return IntType(clamping: int64)
    }

    private func sanitized(_ raw: String) -> String {
        var result = ""

        for (index, character) in raw.enumerated() {
            if character.isWholeNumber {
                result.append(character)
                continue
            }

            if character == "-", index == 0, IntType.isSigned {
                result.append(character)
            }
        }

        return result
    }
}
