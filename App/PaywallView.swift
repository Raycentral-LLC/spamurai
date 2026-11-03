import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var purchasing = false
    @State private var error: String?
    @State private var purchased = 0
    @State private var assembled = false

    private let features: [(icon: String, title: String, detail: String)] = [
        ("apps.iphone", "Every app, not just Safari", "Games, social and news apps lose their ads and trackers."),
        ("waveform.path.ecg", "See who's watching", "Live activity shows every company an app talks to."),
        ("moon.circle.fill", "Focus Shield", "Block social, video and news on a schedule or with your iOS Focus."),
        ("wrench.and.screwdriver.fill", "One-tap fix", "Site broken? See what was just blocked and allow it in a tap."),
        ("hand.raised.fill", "Your rules", "Allow or block any domain with one swipe."),
        ("square.grid.2x2.fill", "Widgets", "Your daily score on the Home and Lock Screen."),
        ("lock.fill", "Private by design", "Filtering runs on your iPhone. No account, no servers."),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 24) {
                    hero.appear()
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: feature.icon)
                                    .font(.title3)
                                    .foregroundStyle(Theme.blade)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title).font(.headline)
                                    Text(feature.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .appear(0.15 + Double(index) * 0.06)
                        }
                    }
                    plans.appear(0.5)
                    cta.appear(0.55)
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 30)
            }
            .scrollIndicators(.hidden)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
        }
        .sensoryFeedback(.success, trigger: purchased)
        .onAppear { selectedID = selectedID ?? yearly?.id ?? store.products.first?.id }
        .onChange(of: store.products) { selectedID = selectedID ?? yearly?.id }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            ShardField(phase: assembled ? .assembled : .scattered)
                .frame(height: 230)
                .task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    assembled = true
                }
            Caps("Spamurai Pro", color: Theme.crimson)
            Text("Every app. One blade.")
                .font(.system(size: 32, weight: .light))
            Text("Ads and trackers cut out of Safari, games, social and news.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var yearly: Product? { store.products.first { $0.subscription?.subscriptionPeriod.unit == .year } }
    private var monthly: Product? { store.products.first { $0.subscription?.subscriptionPeriod.unit == .month } }

    /// Yearly saving vs. paying monthly for 12 months, e.g. "SAVE 37%".
    private var savings: String? {
        guard let yearly, let monthly, monthly.price > 0 else { return nil }
        let ratio = 1 - (yearly.price as NSDecimalNumber).doubleValue / ((monthly.price as NSDecimalNumber).doubleValue * 12)
        return ratio > 0.05 ? "SAVE \(Int((ratio * 100).rounded()))%" : nil
    }

    private var plans: some View {
        VStack(spacing: 12) {
            if store.products.isEmpty { ProgressView().padding() }
            ForEach(store.products.sorted { $0.price > $1.price }) { product in
                PlanCard(product: product,
                         badge: product.id == yearly?.id ? savings : nil,
                         selected: selectedID == product.id)
                    .onTapGesture { withAnimation(.snappy) { selectedID = product.id } }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    private var selected: Product? { store.products.first { $0.id == selectedID } }

    private var cta: some View {
        VStack(spacing: 10) {
            Button {
                guard let selected else { return }
                purchasing = true
                Task {
                    defer { purchasing = false }
                    do {
                        try await store.purchase(selected)
                        if store.isPro {
                            purchased += 1
                            dismiss()
                        }
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            } label: {
                ZStack {
                    Text(ctaTitle).opacity(purchasing ? 0 : 1)
                    if purchasing { ProgressView().tint(.white) }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selected == nil || purchasing)

            if let terms = selected.map(termsLine) {
                Text(terms).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }

    private var ctaTitle: String {
        selected?.subscription?.introductoryOffer?.paymentMode == .freeTrial ? "Start free week" : "Continue"
    }

    private func termsLine(_ product: Product) -> String {
        let period = product.subscription?.subscriptionPeriod.unit == .year ? "year" : "month"
        if product.subscription?.introductoryOffer?.paymentMode == .freeTrial {
            return "1 week free, then \(product.displayPrice)/\(period). Cancel anytime."
        }
        return "\(product.displayPrice)/\(period). Cancel anytime."
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Button("Restore") { Task { await store.restore(); if store.isPro { dismiss() } } }
            Link("Terms", destination: AppConfig.termsURL)
            Link("Privacy", destination: AppConfig.privacyURL)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct PlanCard: View {
    let product: Product
    let badge: String?
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(selected ? AnyShapeStyle(Theme.blade) : AnyShapeStyle(Color.secondary))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName).font(.headline)
                if let perMonth { Text(perMonth).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(product.displayPrice).font(.headline.monospacedDigit())
        }
        .padding(16)
        .background(Color.white.opacity(selected ? 0.06 : 0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(Theme.blade) : AnyShapeStyle(Color.white.opacity(0.08)),
                              lineWidth: selected ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.blade, in: Capsule())
                    .foregroundStyle(.white)
                    .offset(x: -12, y: -10)
            }
        }
        .scaleEffect(selected ? 1 : 0.98)
        .contentShape(Rectangle())
    }

    private var perMonth: String? {
        guard product.subscription?.subscriptionPeriod.unit == .year else { return nil }
        let monthly = product.price / 12
        return "Just \(monthly.formatted(product.priceFormatStyle.precision(.fractionLength(2))))/month"
    }
}
