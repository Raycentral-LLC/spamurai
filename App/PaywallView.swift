import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Block ads in every app", systemImage: "shield.lefthalf.filled")
                    Label("Live activity: see what every app connects to", systemImage: "waveform.path.ecg")
                    Label("Your own allow & block lists", systemImage: "list.bullet")
                    Label("Home & Lock Screen widgets", systemImage: "square.grid.2x2")
                }
                Section {
                    ForEach(store.products) { product in
                        Button {
                            Task {
                                do {
                                    try await store.purchase(product)
                                    if store.isPro { dismiss() }
                                } catch {
                                    self.error = error.localizedDescription
                                }
                            }
                        } label: {
                            LabeledContent(product.displayName, value: product.displayPrice)
                        }
                    }
                    if store.products.isEmpty { ProgressView() }
                }
                Section {
                    Button("Restore purchases") { Task { await store.restore() } }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Spamurai Pro")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}
