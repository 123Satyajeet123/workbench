import Kernel

/// A fixture value built from literals written in test code. A literal that the kernel refuses is a bug in the test,
/// so the run stops at once with the error.
func fixture<Value>(_ make: () throws -> Value) -> Value {
    do {
        return try make()
    } catch {
        fatalError("a test fixture literal was refused: \(error)")
    }
}

func person(_ name: String) -> PersonID { fixture { try PersonID(name) } }
func sourceClass(_ name: String) -> SourceClass { fixture { try SourceClass(name) } }
func source(_ owner: PersonID, _ key: String) -> Source { fixture { Source(owner: owner, key: try SourceKey(key)) } }
