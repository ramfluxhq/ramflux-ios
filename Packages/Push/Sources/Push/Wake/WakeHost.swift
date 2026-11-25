// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// Builds the processor both hosts use (the extension and the app's debug injector) from the shared container.
public enum WakeHost {
    public static func processor(fetcher: (any WakeFetching)? = CoreWakeFetcher(), info: [String: Any]? = Bundle.main.infoDictionary) -> WakeProcessor {
        WakeProcessor(dispatcher: WakeDispatcher(fetcher: fetcher, registry: RouteRegistry(info: info)))
    }
}
