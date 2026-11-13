// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public protocol MicrophoneRepository: Sendable { func status() async -> MicrophoneStatus }
