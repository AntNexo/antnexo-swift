#if canImport(WebKit)
import Foundation
import WebKit
import CryptoKit
import AntNexoCore

/// Where the sheet's web data lives (the widget session, What's new state of the page).
///
/// iOS 17+ / macOS 14+: a store of its own per board host, so `logout()` clears exactly that. Older systems: the
/// default store, and `logout()` removes the records of the host's site (for `<slug>.antnexo.com`: `antnexo.com`).
enum DataStore {
    @available(iOS 17, macOS 14, *)
    static func identifier(for host: BoardHost) -> UUID {
        // a name-based UUID (v5 layout) from the origin: stable across launches, different per host
        var b = Array(Insecure.SHA1.hash(data: Data("antnexo:\(host.origin)".utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13],
                           b[14], b[15]))
    }

    @MainActor
    static func store(for host: BoardHost) -> WKWebsiteDataStore {
        if #available(iOS 17, macOS 14, *) {
            return WKWebsiteDataStore(forIdentifier: identifier(for: host))
        }
        return .default()
    }

    @MainActor
    static func clear(for host: BoardHost) async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        if #available(iOS 17, macOS 14, *) {
            await store(for: host).removeData(ofTypes: types, modifiedSince: .distantPast)
            return
        }
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: types)
        let mine = records.filter { r in host.host == r.displayName || host.host.hasSuffix("." + r.displayName) }
        await store.removeData(ofTypes: types, for: mine)
    }
}
#endif
