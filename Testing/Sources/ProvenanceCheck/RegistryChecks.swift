import Foundation

@testable import WorkbenchCore

/// What is wrong with a manifest and a registry for a set of tables. Pure, so the check can feed it a bad input.
func registryFailures(
    schema: Set<String>, words: [String: NodeKind], noWords: Set<String>, redactors: [Redactor]
) -> [String] {
    var failures: [String] = []
    for table in schema.subtracting(words.keys).subtracting(noWords).sorted() {
        failures.append("table \(table) is not classified")
    }
    for table in Set(words.keys).union(noWords).subtracting(schema).sorted() {
        failures.append("the manifest names \(table), which the schema does not have")
    }
    for table in Set(words.keys).intersection(noWords).sorted() {
        failures.append("table \(table) is both a words table and a no-words table")
    }
    for (table, kind) in words.sorted(by: { $0.key < $1.key }) {
        guard let redactor = redactors.first(where: { $0.kind == kind }) else {
            failures.append("words table \(table) has no redactor of kind \(kind)")
            continue
        }
        if !redactor.tables.contains(table) { failures.append("the redactor of \(kind) does not list \(table)") }
    }
    for redactor in redactors {
        for table in redactor.tables where words[table] != redactor.kind {
            failures.append("the redactor of \(redactor.kind) lists \(table), which the manifest does not give it")
        }
    }
    return failures
}

func runRegistryChecks() throws {
    let store = try Store(directory: scratchFolder("registry"))
    let schema = Set(try store.tableNames())
    let redactors = Redactors.all
    let real = registryFailures(
        schema: schema, words: TableManifest.words, noWords: TableManifest.noWords, redactors: redactors)
    check(
        real.isEmpty, "registry: every table of the schema is classified and every words table has its redactor \(real)"
    )
    check(
        schema.count == TableManifest.words.count + TableManifest.noWords.count,
        "registry: \(schema.count) tables = \(TableManifest.words.count) words + \(TableManifest.noWords.count) no words"
    )

    let unclassified = registryFailures(
        schema: schema.union(["leaky_table"]), words: TableManifest.words, noWords: TableManifest.noWords,
        redactors: redactors)
    check(
        unclassified == ["table leaky_table is not classified"], "registry: a new table that nothing classifies fails")
    var withoutRedactor = TableManifest.words
    withoutRedactor["ghost_words"] = .newsArticle
    let noRedactor = registryFailures(
        schema: schema.union(["ghost_words"]), words: withoutRedactor, noWords: TableManifest.noWords,
        redactors: redactors)
    check(
        noRedactor == ["the redactor of newsArticle does not list ghost_words"],
        "registry: a words table that its redactor does not list fails")
    let missing = registryFailures(
        schema: schema, words: TableManifest.words, noWords: TableManifest.noWords,
        redactors: redactors.filter { $0.kind != .summary })
    check(
        missing.contains("words table summary has no redactor of kind summary"),
        "registry: a words table with no redactor fails")
}
