// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum TasksAction: Equatable, Sendable { case appeared, disappeared, refresh, mode(TasksMode), loadMore, prepare(TaskDecisionKind), confirm(UUID), cancelConfirmation, reconcile(String), unavailable }
