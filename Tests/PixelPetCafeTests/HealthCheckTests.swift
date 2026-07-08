import XCTest
@testable import PixelPetCafe

final class HealthCheckTests: XCTestCase {

    // MARK: reputation

    func testReputationTierBucketsFromStrugglingToBeloved() {
        XCTAssertEqual(HealthCheck.reputationTier(5).severity, .critical)
        XCTAssertEqual(HealthCheck.reputationTier(5).label, "Struggling")
        XCTAssertEqual(HealthCheck.reputationTier(30).severity, .warning)
        XCTAssertEqual(HealthCheck.reputationTier(50).severity, .good)
        XCTAssertEqual(HealthCheck.reputationTier(90).label, "Beloved")
    }

    // MARK: cleanliness

    func testCleanlinessTierBucketsFromFilthyToSpotless() {
        XCTAssertEqual(HealthCheck.cleanlinessTier(10).severity, .critical)
        XCTAssertEqual(HealthCheck.cleanlinessTier(40).severity, .warning)
        XCTAssertEqual(HealthCheck.cleanlinessTier(60).severity, .good)
        XCTAssertEqual(HealthCheck.cleanlinessTier(100).label, "Spotless")
    }

    // MARK: throughput

    func testThroughputTierGoodWhenCapacityComfortablyExceedsDemand() {
        let tier = HealthCheck.throughputTier(capacityPerSec: 5, customerRate: 2)
        XCTAssertEqual(tier.severity, .good)
    }

    func testThroughputTierWarningWhenSlightlyBehind() {
        let tier = HealthCheck.throughputTier(capacityPerSec: 1.8, customerRate: 2)
        XCTAssertEqual(tier.severity, .warning)
    }

    func testThroughputTierCriticalWhenBadlyBottlenecked() {
        let tier = HealthCheck.throughputTier(capacityPerSec: 0.5, customerRate: 2)
        XCTAssertEqual(tier.severity, .critical)
    }

    func testThroughputTierCriticalWhenNothingServable() {
        let tier = HealthCheck.throughputTier(capacityPerSec: .infinity, customerRate: 2)
        XCTAssertEqual(tier.severity, .critical)
    }

    func testThroughputTierGoodWhenNoDemandAtAll() {
        let tier = HealthCheck.throughputTier(capacityPerSec: .infinity, customerRate: 0)
        XCTAssertEqual(tier.severity, .good)
    }

    // MARK: storage

    func testStorageFillPercentAveragesAcrossIngredients() {
        let stock = ["beans": 100, "milk": 200]
        let pct = HealthCheck.storageFillPercent(stock: stock, ingredientIds: ["beans", "milk"], cap: 200)
        XCTAssertEqual(pct, 75, accuracy: 1e-9)   // (50% + 100%) / 2
    }

    func testStorageFillPercentClampsAboveCap() {
        let stock = ["beans": 500]
        let pct = HealthCheck.storageFillPercent(stock: stock, ingredientIds: ["beans"], cap: 200)
        XCTAssertEqual(pct, 100, accuracy: 1e-9)
    }

    func testStorageFillPercentZeroCapOrEmptyIngredientsIsZeroNotCrash() {
        XCTAssertEqual(HealthCheck.storageFillPercent(stock: [:], ingredientIds: ["beans"], cap: 0), 0)
        XCTAssertEqual(HealthCheck.storageFillPercent(stock: [:], ingredientIds: [], cap: 200), 0)
    }

    func testStorageTierBuckets() {
        XCTAssertEqual(HealthCheck.storageTier(fillPercent: 5).severity, .critical)
        XCTAssertEqual(HealthCheck.storageTier(fillPercent: 25).severity, .warning)
        XCTAssertEqual(HealthCheck.storageTier(fillPercent: 80).severity, .good)
    }

    // MARK: seasonal price alerts

    func testNotableSeasonalPricePicksTheBiggestSwing() {
        // winter: berry 1.30x, cocoa 1.25x, beans 1.20x, honey 1.15x — berry should win.
        let alert = HealthCheck.notableSeasonalPrice(
            ingredientIds: ["beans", "milk", "flour", "sugar", "matcha", "cocoa", "berry", "honey"],
            season: .winter
        )
        XCTAssertEqual(alert?.ingredientId, "berry")
        XCTAssertFalse(alert?.cheaper ?? true)
    }

    func testNotableSeasonalPricePrefersCheapStandoutInSummer() {
        // summer: berry is the only listed swing (0.75x) — everything else is neutral.
        let alert = HealthCheck.notableSeasonalPrice(
            ingredientIds: ["beans", "milk", "flour", "sugar", "matcha", "cocoa", "berry", "honey"],
            season: .summer
        )
        XCTAssertEqual(alert?.ingredientId, "berry")
        XCTAssertTrue(alert?.cheaper ?? false)
    }

    func testNotableSeasonalPriceNilWhenNothingSwings() {
        // spring is the neutral baseline for every listed ingredient.
        let alert = HealthCheck.notableSeasonalPrice(
            ingredientIds: ["beans", "milk", "flour", "sugar", "matcha", "cocoa", "berry", "honey"],
            season: .spring
        )
        XCTAssertNil(alert)
    }
}
