import Testing
import WorkbenchCore

@testable import Evals

/// Simulation on synthetic answers: 4,000 runs, a fixed seed, the certificate read after every answer.
@Suite struct TrustSimulationTests {
    private let simulation = TrustSimulation()
    private var onePerReading: TrustSimulation {
        var simulation = simulation
        simulation.policy = .onePerReading
        return simulation
    }

    @Test func theOldCertificateEarnsFalselyOnAboutAThirdOfRunsAndTheNewOneOnAtMostTenPercent() {
        let results = simulation.run(.equal(size: 10, wrongRate: RunSettings.standard.allowedWrong))
        #expect((0.25...0.40).contains(results[.fixedBound]!.everEarned))
        #expect(results[.betting]!.everEarned <= 1 - RunSettings.standard.confidence)
    }

    @Test(arguments: [
        AuditPopulation.mixed(itemWrongRate: 0.1), .bigReadingsWorse(itemWrongRate: 0.1),
        .bigReadingsWorse(itemWrongRate: 0.1, sizes: AuditPopulation.largeSizes),
    ])
    func eachItemAtOneChanceKeepsTheErrorRateWhateverTheSizeOfTheReadings(population: AuditPopulation) {
        #expect(abs(population.itemWrongRate - RunSettings.standard.allowedWrong) < 1e-9)
        #expect(simulation.run(population)[.betting]!.everEarned <= 1 - RunSettings.standard.confidence)
    }

    @Test func onePickPerReadingStaysWithinTheBoundUpToTheHeaviestWeight() {
        let population = AuditPopulation.bigReadingsWorse(itemWrongRate: 0.1, sizes: [(1, 0.5), (3, 0.3), (6, 0.2)])
        #expect(onePerReading.run(population)[.betting]!.everEarned <= 1 - RunSettings.standard.confidence)
    }

    @Test func onePickPerReadingEarnsFalselyWhenReadingsAreBiggerThanTheHeaviestWeightAndBigOnesAreWorse() {
        let population = AuditPopulation.bigReadingsWorse(itemWrongRate: 0.1, sizes: AuditPopulation.largeSizes)
        #expect(onePerReading.run(population)[.betting]!.everEarned > 1 - RunSettings.standard.confidence)
    }

    @Test func withoutWeightsTheCertificateEarnsFalselyWhenBigReadingsAreWorse() {
        let results = onePerReading.run(.bigReadingsWorse(itemWrongRate: RunSettings.standard.allowedWrong))
        #expect(results[.bettingWithoutWeights]!.everEarned > 1 - RunSettings.standard.confidence)
    }

    @Test func aHelperWithNoWrongAnswersEarnsAfterThirtySixAtTheHeaviestWeight() {
        let results = simulation.run(.equal(size: 10, wrongRate: 0))
        #expect(results[.betting]!.median == 36 && results[.fixedBound]!.median == 22)
    }
}
