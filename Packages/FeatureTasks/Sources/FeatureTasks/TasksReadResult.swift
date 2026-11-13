// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
enum TasksReadResult: Sendable { case conversations(RepositoryResult<[ConversationRecord]>), page(RepositoryResult<TaskPage>), detail(RepositoryResult<TaskRecord>), permissions(RepositoryResult<[PermissionRecord]>) }
