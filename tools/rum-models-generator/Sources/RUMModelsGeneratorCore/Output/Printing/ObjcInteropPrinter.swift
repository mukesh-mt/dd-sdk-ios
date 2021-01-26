/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Generates Swift code for Obj-c interoperability for given `ObjcInteropType` schemas.
///
/// E.g. given `ObjcInteropType` describing Swift struc:
///
///     public struct Foo {
///         public var string = "foo"
///         public let integer = 123
///     }
///
/// it prints it's Obj-c interoperability wrapper:
///
///     @objc
///     public class DDFoo: NSObject {
///         internal var foo: Foo
///
///         internal init(foo: Foo) {
///             self.foo = foo
///         }
///
///         @objc
///         public var string: String {
///             set { foo.string = newValue }
///             get { foo.string }
///         }
///
///         @objc
///         public var integer: NSNumber { foo.integer as NSNumber }
///     }
///
internal class ObjcInteropPrinter: BasePrinter {
    /// The prefix used for types exposed to Obj-c.
    private let objcTypeNamesPrefix: String

    init(objcTypeNamesPrefix: String) {
        self.objcTypeNamesPrefix = objcTypeNamesPrefix
    }

    func print(objcInteropTypes: [ObjcInteropType]) throws -> String {
        reset()
        try objcInteropTypes.forEach { try print(objcInteropType: $0) }
        return output
    }

    // MARK: - Printing Objc Classes and Enums

    private func print(objcInteropType: ObjcInteropType) throws {
        switch objcInteropType {
        case let rootClass as ObjcInteropRootClass:
            try print(objcInteropRootClass: rootClass)
        case let nestedClass as ObjcInteropTransitiveClass:
            try print(objcInteropNestedClass: nestedClass)
        case let enumeration as ObjcInteropEnum:
            try print(objcInteropEnum: enumeration)
        default:
            throw Exception.unimplemented("Cannot print `ObjcInteropType`: \(type(of: objcInteropType))")
        }
    }

    private func print(objcInteropRootClass: ObjcInteropRootClass) throws {
        let className = objcTypeNamesPrefix + objcInteropRootClass.objcTypeName
        writeEmptyLine()
        writeLine("@objc")
        writeLine("public class \(className): NSObject {")
        indentRight()
            writeLine("internal var swiftModel: \(objcInteropRootClass.swiftTypeName)")
            writeLine("internal var root: \(className) { self }")
            writeEmptyLine()
            writeLine("internal init(swiftModel: \(objcInteropRootClass.swiftTypeName)) {")
            indentRight()
                writeLine("self.swiftModel = swiftModel")
            indentLeft()
            writeLine("}")
            try objcInteropRootClass.objcPropertyWrappers.forEach { propertyWrapper in
                try print(objcInteropPropertyWrapper: propertyWrapper)
            }
        indentLeft()
        writeLine("}")
    }

    private func print(objcInteropNestedClass: ObjcInteropTransitiveClass) throws {
        let className = objcTypeNamesPrefix + objcInteropNestedClass.objcTypeName
        let rootClassName = objcTypeNamesPrefix + objcInteropNestedClass.objcRootClass.objcTypeName
        writeEmptyLine()
        writeLine("@objc")
        writeLine("public class \(className): NSObject {")
        indentRight()
            writeLine("internal let root: \(rootClassName)")
            writeEmptyLine()
            writeLine("internal init(root: \(rootClassName)) {")
            indentRight()
                writeLine("self.root = root")
            indentLeft()
            writeLine("}")
            try objcInteropNestedClass.objcPropertyWrappers.forEach { propertyWrapper in
                try print(objcInteropPropertyWrapper: propertyWrapper)
            }
        indentLeft()
        writeLine("}")
    }

    private func print(objcInteropEnum: ObjcInteropEnum) throws {
        let enumName = objcTypeNamesPrefix + objcInteropEnum.objcTypeName
        let swiftEnum = objcInteropEnum.bridgedSwiftEnum
        let managesOptionalEnum = objcInteropEnum.parentProperty.bridgedSwiftProperty.isOptional
        let objcEnumOptionality = managesOptionalEnum ? "?" : ""
        writeEmptyLine()
        writeLine("@objc")
        writeLine("public enum \(enumName): Int {")
        indentRight()
            writeLine("internal init(swift: \(objcInteropEnum.swiftTypeName)\(objcEnumOptionality)) {")
            indentRight()
                writeLine("switch swift {")
                if managesOptionalEnum {
                    writeLine("case nil: self = .none")
                }
                swiftEnum.cases.forEach { enumCase in
                    writeLine("case .\(enumCase.label)\(objcEnumOptionality): self = .\(enumCase.label)")
                }
                writeLine("}")
            indentLeft()
            writeLine("}")
            writeEmptyLine()
            writeLine("internal var toSwift: \(objcInteropEnum.swiftTypeName)\(objcEnumOptionality) {")
            indentRight()
                writeLine("switch self {")
                if managesOptionalEnum {
                    writeLine("case .none: return nil")
                }
                swiftEnum.cases.forEach { enumCase in
                    writeLine("case .\(enumCase.label): return .\(enumCase.label)")
                }
                writeLine("}")
            indentLeft()
            writeLine("}")
            writeEmptyLine()
            if managesOptionalEnum {
                writeLine("case none")
            }
            swiftEnum.cases.forEach { enumCase in
                writeLine("case \(enumCase.label)")
            }
        indentLeft()
        writeLine("}")
    }

    // MARK: - Printing Property Wrappers

    private func print(objcInteropPropertyWrapper: ObjcInteropPropertyWrapper) throws {
        writeEmptyLine()

        switch objcInteropPropertyWrapper {
        case let wrapper as ObjcInteropPropertyWrapperAccessingNestedStruct:
            try printPropertyAccessingNestedClass(wrapper)
        case let wrapper as ObjcInteropPropertyWrapperAccessingNestedEnum:
            try printPropertyAccessingNestedEnum(wrapper)
        case let wrapper as ObjcInteropPropertyWrapperAccessingNestedEnumsArray:
            try printPropertyAccessingNestedEnumArray(wrapper)
        case let wrapper as ObjcInteropPropertyWrapperManagingSwiftStructProperty:
            try printPrimitivePropertyWrapper(wrapper)
        default:
            throw Exception.illegal("Unrecognized property wrapper: \(type(of: objcInteropPropertyWrapper))")
        }
    }

    private func printPropertyAccessingNestedClass(_ propertyWrapper: ObjcInteropPropertyWrapperAccessingNestedStruct) throws {
        let nestedObjcClass = propertyWrapper.objcNestedClass! // swiftlint:disable:this force_unwrapping

        // Generate accessor to the referenced wrapper, e.g.:
        // ```
        // @objc public var bar: DDFooBar? {
        //     root.swiftModel.bar != nil ? DDFooBar(root: root) : nil
        // }
        // ```
        let swiftProperty = propertyWrapper.bridgedSwiftProperty
        let objcPropertyName = swiftProperty.name
        let objcPropertyOptionality = swiftProperty.isOptional ? "?" : ""
        let objcClassName = objcTypeNamesPrefix + nestedObjcClass.objcTypeName
        writeLine("@objc public var \(objcPropertyName): \(objcClassName)\(objcPropertyOptionality) {")
        indentRight()
            if swiftProperty.isOptional {
                // The property is optional, so the accessor must be returned only if the wrapped value is `!= nil`, e.g.:
                // ```
                // root.swiftModel.bar != nil ? DDFooBar(root: root) : nil
                // ```
                writeLine("root.swiftModel.\(propertyWrapper.keyPath) != nil ? \(objcClassName)(root: root) : nil")
            } else {
                // The property is non-optional, so accessor can be provided without considering `nil` value:
                // ```
                // DDFooBar(root: root)
                // ```
                writeLine("\(objcClassName)(root: root)")
            }
        indentLeft()
        writeLine("}")
    }

    private func printPropertyAccessingNestedEnum(_ propertyWrapper: ObjcInteropPropertyWrapperAccessingNestedEnum) throws {
        let nestedObjcEnum = propertyWrapper.objcNestedEnum! // swiftlint:disable:this force_unwrapping

        // Generate getter and setter for managed enum, e.g.:
        // ```
        // @objc public var enumeration: DDFooEnumeration {
        //    set { root.swiftModel.enumeration = newValue.toSwift }
        //    get { .init(swift: root.swiftModel.enumeration) }
        // }
        // ```
        let swiftProperty = propertyWrapper.bridgedSwiftProperty
        let objcPropertyName = swiftProperty.name
        let objcEnumName = objcTypeNamesPrefix + nestedObjcEnum.objcTypeName

        if swiftProperty.isMutable {
            writeLine("@objc public var \(objcPropertyName): \(objcEnumName) {")
            indentRight()
                writeLine("set { root.swiftModel.\(propertyWrapper.keyPath) = newValue.toSwift }")
                writeLine("get { .init(swift: root.swiftModel.\(propertyWrapper.keyPath)) }")
            indentLeft()
            writeLine("}")
        } else {
            writeLine("@objc public var \(objcPropertyName): \(objcEnumName) {")
            indentRight()
                writeLine(".init(swift: root.swiftModel.\(propertyWrapper.keyPath))")
            indentLeft()
            writeLine("}")
        }
    }

    private func printPropertyAccessingNestedEnumArray(_ propertyWrapper: ObjcInteropPropertyWrapperAccessingNestedEnumsArray) throws {
        let nestedObjcEnumArray = propertyWrapper.objcNestedEnumsArray! // swiftlint:disable:this force_unwrapping

        // Generate getter for managed enum array.
        // Because `[Enum]` cannot be exposed to Objc directly, we map each value to its `.rawValue`
        // representation (which is `Int` for all `@objc` enums), e.g.:
        // ```
        // @objc public var options: [Int] {
        //     root.swiftModel.bar.options.map { DDFooOptions(swift: $0).rawValue }
        // }
        // ```
        let swiftProperty = propertyWrapper.bridgedSwiftProperty
        let objcPropertyName = swiftProperty.name
        let objcPropertyOptionality = swiftProperty.isOptional ? "?" : ""
        let objcEnumName = objcTypeNamesPrefix + nestedObjcEnumArray.objcTypeName

        guard swiftProperty.isMutable == false else {
            throw Exception.unimplemented("Cannot print setter for `ObjcInteropEnumArray`: \(swiftProperty.type).")
        }

        writeLine("@objc public var \(objcPropertyName): [Int]\(objcPropertyOptionality) {")
        indentRight()
            writeLine("root.swiftModel.\(propertyWrapper.keyPath)\(objcPropertyOptionality).map { \(objcEnumName)(swift: $0).rawValue }")
        indentLeft()
        writeLine("}")
    }

    private func printPrimitivePropertyWrapper(_ propertyWrapper: ObjcInteropPropertyWrapperManagingSwiftStructProperty) throws {
        let swiftProperty = propertyWrapper.bridgedSwiftProperty
        let objcPropertyName = swiftProperty.name
        let objcPropertyOptionality = swiftProperty.isOptional ? "?" : ""
        let objcTypeName = try objcInteropTypeName(for: propertyWrapper.objcInteropType)
        let asObjcCast = try swiftToObjcCast(for: propertyWrapper.objcInteropType).ifNotNil { asObjcCast in
            asObjcCast + objcPropertyOptionality
        } ?? ""

        if swiftProperty.isMutable {
            // Generate getter and setter for the managed value, e.g.:
            // ```
            // @objc public var propertyX: String? {
            //     set { root.swiftModel.bar.propertyX = newValue }
            //     get { root.swiftModel.bar.propertyX }
            // }
            // ```
            let toSwiftCast = try objcToSwiftCast(for: swiftProperty.type).ifNotNil { toSwiftCast in
                objcPropertyOptionality + toSwiftCast
            } ?? ""
            writeLine("@objc public var \(objcPropertyName): \(objcTypeName)\(objcPropertyOptionality) {")
            indentRight()
                writeLine("set { root.swiftModel.\(propertyWrapper.keyPath) = newValue\(toSwiftCast) }")
                writeLine("get { root.swiftModel.\(propertyWrapper.keyPath)\(asObjcCast) }")
            indentLeft()
            writeLine("}")
        } else {
            // Generate getter for the managed value, e.g.:
            // ```
            // @objc public var propertyX: String? {
            //     root.swiftModel.bar.propertyX
            // }
            // ```
            writeLine("@objc public var \(objcPropertyName): \(objcTypeName)\(objcPropertyOptionality) {")
            indentRight()
                writeLine("root.swiftModel.\(propertyWrapper.keyPath)\(asObjcCast)")
            indentLeft()
            writeLine("}")
        }
    }

    // MARK: - Generating names

    private func objcInteropTypeName(for objcType: ObjcInteropType) throws -> String {
        switch objcType {
        case _ as ObjcInteropNSNumber:
            return "NSNumber"
        case _ as ObjcInteropNSString:
            return "String"
        case let objcArray as ObjcInteropNSArray:
            return "[\(try objcInteropTypeName(for: objcArray.element))]"
        default:
            throw Exception.unimplemented(
                "Cannot print `ObjcInteropType` name for \(type(of: objcType))."
            )
        }
    }

    private func swiftToObjcCast(for objcType: ObjcInteropType) throws -> String? {
        switch objcType {
        case _ as ObjcInteropNSNumber:
            return " as NSNumber"
        case let nsArray as ObjcInteropNSArray where nsArray.element is ObjcInteropNSNumber:
            return " as [NSNumber]"
        case _ as ObjcInteropNSString:
            return nil // `String` <> `NSString` interoperability doesn't require casting
        case let nsArray as ObjcInteropNSArray where nsArray.element is ObjcInteropNSString:
            return nil // `[String]` <> `[NSString]` interoperability doesn't require casting
        default:
            throw Exception.unimplemented("Cannot print `swiftToObjcCast()` for \(type(of: objcType)).")
        }
    }

    private func objcToSwiftCast(for swiftType: SwiftType) throws -> String? {
        switch swiftType {
        case _ as SwiftPrimitive<Bool>:
            return ".boolValue"
        case _ as SwiftPrimitive<Double>:
            return ".doubleValue"
        case _ as SwiftPrimitive<Int>:
            return ".intValue"
        case _ as SwiftPrimitive<Int64>:
            return ".int64Value"
        case let swiftArray as SwiftArray where swiftArray.element is SwiftPrimitive<String>:
            return nil // `[String]` <> `[NSString]` interoperability doesn't require casting
        case let swiftArray as SwiftArray:
            let elementCast = try objcToSwiftCast(for: swiftArray.element)
                .unwrapOrThrow(.illegal("Cannot print `objcToSwiftCast()` for `SwiftArray` with elements of type: \(type(of: swiftArray.element))"))
            return ".map { $0\(elementCast) }"
        case _ as SwiftPrimitive<String>:
            return nil // `String` <> `NSString` interoperability doesn't require casting
        default:
            throw Exception.unimplemented("Cannot print `objcToSwiftCast()` for \(type(of: swiftType)).")
        }
    }
}
