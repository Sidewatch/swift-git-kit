//
//  CheckoutResults.swift
//  GitKit
//
//  What git last said about each checkout, and which checkouts must be asked again.
//
//  Created by David Sherlock on 11/17/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What git last said about each checkout of a ``CheckoutSet``, and which checkouts must be asked
/// again: a folder holding ninety checkouts re-asks the one a change touched, not all ninety.
///
/// A refresh marks the checkouts a change touched (``invalidate(_:)``), takes the ones to ask
/// (``takeStale(of:)``: the invalidated and the never asked), asks git off the main thread, and
/// stores the answers (``store(_:)``). A change that lands while git is being asked invalidates its
/// checkout again, so the next refresh asks it again.
public struct CheckoutResults<Value: Sendable>: Sendable {
    /// The last answer for each checkout asked.
    public private(set) var values: [URL: Value] = [:]
    /// The checkouts whose answer a change has made stale.
    private var stale: Set<URL> = []

    public init() {}

    /// Marks `roots` to be asked again.
    public mutating func invalidate(_ roots: some Sequence<URL>) {
        stale.formUnion(roots)
    }

    /// The checkouts among `roots` to ask now, in `roots`' order: every invalidated one and every one
    /// never asked. They stop being stale; answers for checkouts no longer in `roots` are dropped.
    public mutating func takeStale(of roots: [URL]) -> [URL] {
        let current = Set(roots)
        values = values.filter { current.contains($0.key) }
        let ask = roots.filter { stale.contains($0) || values[$0] == nil }
        stale.subtract(ask)
        return ask
    }

    /// Keeps `fresh` as the answers for its checkouts.
    public mutating func store(_ fresh: [URL: Value]) {
        values.merge(fresh) { _, new in new }
    }

    /// Forgets every answer and every mark.
    public mutating func removeAll() {
        values = [:]
        stale = []
    }
}
