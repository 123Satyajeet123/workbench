import AppKit

/// Takes a window out of every Space, so a Space change moves nothing.
protocol SpaceHolding {
    func hold(_ window: NSWindow)
}

/// A WindowServer space of its own, shown on every display above every Space, that holds the island's window. A
/// window in it belongs to no Space, so a Space change or a full-screen change moves nothing. It uses private
/// SkyLight calls that are looked up at run time. When one is missing, `init` returns nil and the island uses its
/// public behaviour alone.
final class IslandSpace: SpaceHolding {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CreateSpace = @convention(c) (Int32, Int32, CFDictionary?) -> Int
    private typealias SetLevel = @convention(c) (Int32, Int, Int32) -> Int32
    private typealias Show = @convention(c) (Int32, CFArray) -> Void
    private typealias DestroySpace = @convention(c) (Int32, Int) -> Void
    private typealias Move = @convention(c) (Int32, CFArray, CFArray) -> Void

    static let absoluteLevel: Int32 = 2_147_483_647

    private let connection: Int32
    private let space: Int
    private let move: Move
    private let destroy: DestroySpace

    init?() {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
            let mainConnection: MainConnection = Self.symbol("CGSMainConnectionID", in: skyLight),
            let create: CreateSpace = Self.symbol("CGSSpaceCreate", in: skyLight),
            let setLevel: SetLevel = Self.symbol("CGSSpaceSetAbsoluteLevel", in: skyLight),
            let show: Show = Self.symbol("CGSShowSpaces", in: skyLight),
            let move: Move = Self.symbol("CGSAddWindowsToSpaces", in: skyLight),
            let destroy: DestroySpace = Self.symbol("CGSSpaceDestroy", in: skyLight)
        else { return nil }
        let connection = mainConnection()
        let space = create(connection, 1, nil)
        guard space != 0 else { return nil }
        _ = setLevel(connection, space, Self.absoluteLevel)
        show(connection, [space] as CFArray)
        self.connection = connection
        self.space = space
        self.move = move
        self.destroy = destroy
    }

    deinit { destroy(connection, space) }

    func hold(_ window: NSWindow) {
        move(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    private static func symbol<Function>(_ name: String, in library: UnsafeMutableRawPointer) -> Function? {
        dlsym(library, name).map { unsafeBitCast($0, to: Function.self) }
    }
}
