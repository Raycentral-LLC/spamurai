import StoreKit

/// StoreKit 2, on-device verification only — no backend.
@MainActor
final class Store: ObservableObject {
    static let productIDs = [
        "com.raycentral.spamurai.pro.monthly",
        "com.raycentral.spamurai.pro.yearly",
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = SharedStore.isPro

    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
    }

    deinit { updates?.cancel() }

    func load() async {
        products = (try? await Product.products(for: Self.productIDs))?.sorted { $0.price < $1.price } ?? []
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, Self.productIDs.contains(t.productID), t.revocationDate == nil {
                pro = true
            }
        }
        isPro = pro
        SharedStore.isPro = pro
    }

    func purchase(_ product: Product) async throws {
        if case .success(.verified(let transaction)) = try await product.purchase() {
            await transaction.finish()
            await refreshEntitlements()
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}
