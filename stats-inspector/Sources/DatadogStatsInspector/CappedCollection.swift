/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

struct CappedCollection<T: Equatable>: Equatable {

    private var elements: [T]
    var maxCount: Int

    init(elements: [T] = [], maxCount: Int) {
        self.elements = elements
        self.maxCount = maxCount
    }
}

extension CappedCollection: Collection, ExpressibleByArrayLiteral {

    typealias Index = Int
    typealias Element = T

    init(arrayLiteral elements: Element...) {
        self.elements = elements
        maxCount = elements.count
    }

    var startIndex: Index { return elements.startIndex }
    var endIndex: Index { return elements.endIndex }

    subscript(index: Index) -> Iterator.Element {
        get { return elements[index] }
    }

    func index(after i: Index) -> Index {
        return elements.index(after: i)
    }

    mutating func append(_ newElement: Element) {
        elements.append(newElement)
        removeExtraElements()
    }

    private mutating func removeExtraElements() {
        guard elements.count > maxCount else { return }
        elements.removeFirst()
    }
}
