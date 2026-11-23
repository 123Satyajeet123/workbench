import AgentCLI
import CryptoKit
import Evals
import Foundation
import WorkbenchCore

// Probe P-J1 (ADR-020 §8): which grounding verifier, in which language, against a lexical control. Dev data only; every
// number is dev. The prediction and the decision rule are written in GATES.md before the first run.
//
//   grounding-probe export-pairs <dev folder> <pairs.json>
//   grounding-probe translate <dev folder> <translations.json>
//   grounding-probe run <dev folder> <models folder> <translations.json> <reference folder> <report.txt>
setvbuf(stdout, nil, _IOLBF, 0)
let arguments = CommandLine.arguments.dropFirst().map { $0 }
guard let command = arguments.first else { fatalError("usage: see the header of main.swift") }

let devFolder = URL(filePath: arguments[1])
let claims = try JSONDecoder().decode([DevClaim].self, from: Data(contentsOf: devFolder.appending(path: "claims.json")))
let quotePairs = GroundingPairs.make(from: claims)

switch command {
case "export-pairs":
    let rows = quotePairs.map { ["premise": $0.premise, "claim": $0.claim] }
    try JSONEncoder().encode(rows).write(to: URL(filePath: arguments[2]))
    print("wrote \(rows.count) pairs")
case "translate":
    try await Translation.write(pairs: quotePairs, to: URL(filePath: arguments[2]))
case "run":
    let probe = try Probe(claims: claims, devFolder: devFolder, pairs: quotePairs, arguments: arguments)
    try await probe.run()
default:
    fatalError("unknown command \(command)")
}
