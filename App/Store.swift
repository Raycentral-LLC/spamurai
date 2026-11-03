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
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            #if DEBUG
            SharedStore.diag("store: \(products.count) products: " + products.map { "\($0.id) \($0.displayPrice) intro=\(String(describing: $0.subscription?.introductoryOffer?.paymentMode))" }.joined(separator: ", "))
            #endif
        } catch {
            products = []
            #if DEBUG
            SharedStore.diag("store: products failed: \(error)")
            #endif
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, Self.productIDs.contains(t.productID), t.revocationDate == nil {
                pro = true
            }
        }
        #if DEBUG
        pro = pro || SharedStore.debugPro
        #endif
        #if DEBUG
        SharedStore.diag("store: entitlements pro=\(pro) debugPro=\(SharedStore.debugPro)")
        #endif
        isPro = pro
        SharedStore.isPro = pro
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        #if DEBUG
        SharedStore.diag("store: purchase \(product.id) -> \(result)")
        #endif
        if case .success(.verified(let transaction)) = result {
            await transaction.finish()
            await refreshEntitlements()
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}
