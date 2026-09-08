import Foundation
import Observation
import StoreKit

/// Loads the monthly Plus subscription, handles purchases, and reflects active entitlements (StoreKit 2).
@Observable
@MainActor
final class SubscriptionManager {
    /// Must match the product id in App Store Connect and the local StoreKit configuration file (if used).
    static let plusMonthlyProductID = SubscriptionProducts.plusMonthlyID

    private(set) var product: Product?

    private static let priceLocaleGB = Locale(identifier: "en_GB")

    /// Always shown in GBP (£); `displayPrice` alone follows the device storefront (often $ in the US simulator).
    var plusMonthlyDisplayPrice: String? {
        guard let product else { return nil }
        let formatted = product.price.formatted(
            .currency(code: "GBP")
                .locale(Self.priceLocaleGB)
        )
        return "\(formatted) / month"
    }

    /// Shown only when this Apple ID can still redeem the App Store introductory offer.
    /// StoreKit applies that offer automatically on `purchase()`; this is for disclosure only.
    private(set) var eligibleIntroOffer: PlusIntroOffer?

    private(set) var isSubscribed = false
    private(set) var hasActiveAppleSubscription = false
    private(set) var hasActiveDatabaseSubscription = false
    private(set) var appleOriginalTransactionID: String?
    private(set) var appleSubscriptionRenewalDate: Date?
    /// True while the current Apple entitlement is still in the introductory free period.
    private(set) var isInIntroductoryPeriod = false

    var appleSubscriptionStatusLine: String? {
        guard let renewalDate = appleSubscriptionRenewalDate else { return nil }
        let formatted = renewalDate.formatted(date: .long, time: .omitted)
        if isInIntroductoryPeriod {
            if let thenPrice = plusMonthlyDisplayPrice {
                return "Free until \(formatted). Then \(thenPrice)."
            }
            return "Free until \(formatted)."
        }
        return "Renews on \(formatted)."
    }
    private(set) var loadInFlight = false
    private(set) var purchaseInFlight = false
    private(set) var lastErrorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(transactionResult: result)
            }
        }
        // `refreshEntitlements()` runs from `ContentView` (.task / scene active) and upgrade modal — avoid duplicate work at launch.
    }

    func loadProduct() async {
        loadInFlight = true
        lastErrorMessage = nil
        defer { loadInFlight = false }
        do {
            // StoreKit sometimes returns an empty array on first query; retry briefly.
            var loaded: Product?
            for attempt in 0 ..< 4 {
                let products = try await Product.products(for: [Self.plusMonthlyProductID])
                loaded = products.first
                if loaded != nil { break }
                if attempt < 3 {
                    try await Task.sleep(for: .milliseconds(400))
                }
            }
            product = loaded
            if product == nil {
                lastErrorMessage = Self.productUnavailableMessage
                eligibleIntroOffer = nil
            } else {
                await refreshIntroOffer()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            eligibleIntroOffer = nil
        }
    }

    /// Introductory offers are applied by StoreKit at purchase time for eligible Apple IDs.
    /// Creating an app account does not start the free month by itself.
    private func refreshIntroOffer() async {
        guard let product, let subscription = product.subscription,
              let offer = subscription.introductoryOffer,
              offer.paymentMode == .freeTrial else {
            eligibleIntroOffer = nil
            return
        }
        let eligible = await subscription.isEligibleForIntroOffer
        guard eligible else {
            eligibleIntroOffer = nil
            return
        }
        eligibleIntroOffer = PlusIntroOffer(
            durationText: Self.offerDurationText(period: offer.period, periodCount: offer.periodCount),
            thenPriceLine: plusMonthlyDisplayPrice
        )
    }

    private static var productUnavailableMessage: String {
        #if DEBUG
        """
        Couldn’t load the subscription from the App Store.

        • Run from Xcode with the shared **bespokeDua** scheme (it uses `BespokePlus.storekit`), or
        • In **Edit Scheme → Run → Options**, set **StoreKit Configuration** to `BespokePlus.storekit`, or
        • Create product `\(Self.plusMonthlyProductID)` in App Store Connect for device/TestFlight builds.
        """
        #else
        "We couldn’t load subscription options. Check your connection, try again shortly, or create an auto-renewable subscription in App Store Connect for this app."
        #endif
    }

    func refreshEntitlements() async {
        var active = false
        var linkedOriginalID: String?
        var renewalDate: Date?
        var inIntroPeriod = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.plusMonthlyProductID else { continue }
            if transaction.revocationDate == nil {
                active = true
                linkedOriginalID = String(transaction.originalID)
                renewalDate = transaction.expirationDate
                inIntroPeriod = transaction.offer?.type == .introductory
            }
        }
        hasActiveAppleSubscription = active
        isInIntroductoryPeriod = inIntroPeriod
        // Only set when StoreKit reports an ID — avoid clearing `appleOriginalTransactionID` when
        // `currentEntitlements` is briefly empty (common right after a successful purchase).
        if let linkedOriginalID {
            appleOriginalTransactionID = linkedOriginalID
        } else if !active {
            appleOriginalTransactionID = nil
        }
        appleSubscriptionRenewalDate = renewalDate
        if !active {
            isInIntroductoryPeriod = false
        }
        recomputeEffectiveSubscription()
    }

    func updateDatabaseSubscriptionStatus(plan: String?) {
        let normalized = plan?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        hasActiveDatabaseSubscription = normalized == "subscribed" || normalized == "bespoke plus"
        recomputeEffectiveSubscription()
    }

    func clearDatabaseSubscriptionStatus() {
        hasActiveDatabaseSubscription = false
        recomputeEffectiveSubscription()
    }

    func purchase() async {
        guard let product else {
            lastErrorMessage = "Still loading subscription options…"
            return
        }
        purchaseInFlight = true
        lastErrorMessage = nil
        defer { purchaseInFlight = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await refreshEntitlements()
                // `Transaction.currentEntitlements` can lag immediately after purchase; trust the
                // verified transaction we just received so sync gets a stable originalTransactionId.
                if transaction.revocationDate == nil {
                    appleOriginalTransactionID = String(transaction.originalID)
                    hasActiveAppleSubscription = true
                    isInIntroductoryPeriod = transaction.offer?.type == .introductory
                }
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                lastErrorMessage = "Purchase is waiting for approval."
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        lastErrorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !hasActiveAppleSubscription {
                lastErrorMessage =
                    "No active subscription for this Apple ID. Subscribe to get Bespoke Plus access."
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func setSyncErrorMessage(_ message: String) {
        lastErrorMessage = message
    }

    private func recomputeEffectiveSubscription() {
        // Access is account-scoped: the signed-in account's backend plan decides Plus access.
        // Apple entitlement is still tracked for purchase/restore flows, but it should not
        // automatically unlock other accounts on the same device.
        isSubscribed = hasActiveDatabaseSubscription
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        do {
            let transaction = try Self.checkVerified(transactionResult)
            if transaction.productID == Self.plusMonthlyProductID {
                await refreshEntitlements()
                if transaction.revocationDate == nil {
                    appleOriginalTransactionID = String(transaction.originalID)
                    hasActiveAppleSubscription = true
                    isInIntroductoryPeriod = transaction.offer?.type == .introductory
                }
            }
            await transaction.finish()
        } catch {
            lastErrorMessage = "Could not verify the purchase."
        }
    }

    private nonisolated static func checkVerified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .unverified:
            throw SubscriptionManagerError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

private enum SubscriptionManagerError: Error {
    case failedVerification
}

struct PlusIntroOffer: Equatable, Sendable {
    let durationText: String
    let thenPriceLine: String?

    var headline: String { "\(durationText) free" }

    var purchaseButtonTitle: String {
        durationText == "1 month" ? "Start free month" : "Start free trial"
    }

    var disclosure: String {
        let thenPrice = thenPriceLine ?? "the monthly price"
        return "Start with \(durationText) free. After that, \(thenPrice) is charged to your Apple ID. The subscription renews monthly until you cancel in Settings at least 24 hours before the period ends."
    }
}

private extension SubscriptionManager {
    static func offerDurationText(period: Product.SubscriptionPeriod, periodCount: Int) -> String {
        let total = max(period.value, 1) * max(periodCount, 1)
        switch period.unit {
        case .day:
            return total == 1 ? "1 day" : "\(total) days"
        case .week:
            return total == 1 ? "1 week" : "\(total) weeks"
        case .month:
            return total == 1 ? "1 month" : "\(total) months"
        case .year:
            return total == 1 ? "1 year" : "\(total) years"
        @unknown default:
            return "a free trial"
        }
    }
}
