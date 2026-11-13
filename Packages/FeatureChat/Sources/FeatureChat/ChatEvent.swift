// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ChatEvent: Equatable, Sendable { case messageSubmitted(String), navigate(AppRoute) }
