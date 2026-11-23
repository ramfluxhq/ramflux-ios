// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
enum TasksReadResult: Sendable { case conversations(RepositoryResult<RowWindow<ConversationRecord>>), tasks(RepositoryResult<RowWindow<TaskRecord>>), detail(RepositoryResult<TaskRecord>), permissions(RepositoryResult<RowWindow<PermissionRecord>>) }
