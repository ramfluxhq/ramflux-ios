// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(macOS)
import SwiftUI
// Generated phone fields use this iOS modifier. Desktop has no software keyboard.
enum DesktopTextCapitalization { case never }
extension View {
    func textInputAutocapitalization(_ mode: DesktopTextCapitalization) -> some View { self }
}
#endif
