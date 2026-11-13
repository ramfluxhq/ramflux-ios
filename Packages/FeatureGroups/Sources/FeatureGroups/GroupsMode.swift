// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum GroupsMode: Equatable, Sendable { case list, create, detail(String), members(String), requests(String), invitation(String), created(String), managementUnavailable, accessChanged }
