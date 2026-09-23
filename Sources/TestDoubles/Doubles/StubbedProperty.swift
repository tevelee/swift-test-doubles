import Foundation

/// A read-write property requirement backed by stored state.
///
/// Created by `whenProperty(initialValue:get:set:)`. Reads return the stored value
/// and writes replace it, so the double behaves like a real property while
/// still recording every access. Tests can read or preset the value directly
/// and verify accesses through ``getter`` and ``setter``.
///
/// ```swift
/// let username = settings.whenProperty(
///     initialValue: nil,
///     get: { $0.username },
///     set: { $0.username = $1 }
/// )
/// let service: any Settings = settings()
/// service.username = "blob"
///
/// #expect(service.username == "blob")
/// #expect(username.value == "blob")
/// username.setter.verify()
/// ```
public final class StubbedProperty<Value>: @unchecked Sendable {
    /// Shared with the registered handlers, which must not retain the
    /// patterns and through them the recorder.
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Value

        init(_ value: Value) {
            stored = value
        }

        var value: Value {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    private let storage: Storage

    /// The pattern describing reads of the property.
    public let getter: CallPattern<Value>
    /// The pattern describing direct assignments to the property.
    public let setter: CallPattern<Void>

    init(initialValue: Value, getter: CallPattern<Value>, setter: CallPattern<Void>) {
        let storage = Storage(initialValue)
        self.storage = storage
        self.getter = getter
        self.setter = setter
        getter.then { () -> Value in storage.value }
        setter.then { (newValue: Value) in storage.value = newValue }
    }

    /// The current stored value. Setting it does not record an interaction.
    public var value: Value {
        get { storage.value }
        set { storage.value = newValue }
    }
}

extension Stub {
    /// Backs a read-write property requirement with stored state.
    ///
    /// Registers the property's getter to return the stored value and its
    /// setter to replace it. Handlers are `@Sendable`, so this avoids
    /// capturing a local variable to fake a property:
    ///
    /// ```swift
    /// let username = settings.whenProperty(
    ///     initialValue: nil,
    ///     get: { $0.username },
    ///     set: { $0.username = $1 }
    /// )
    /// ```
    ///
    /// `set` must assign the value directly; compound assignment uses the
    /// property's `_modify` accessor instead of its setter.
    @discardableResult
    public func whenProperty<Value>(
        initialValue: Value,
        get: (P) throws -> Value,
        set: (inout P, Value) throws -> Void,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> StubbedProperty<Value> {
        let getter = when(
            returning: initialValue,
            get,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
        let setter = when(
            { (value: inout P) in try set(&value, Match.any(using: initialValue)) },
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
        return StubbedProperty(initialValue: initialValue, getter: getter, setter: setter)
    }
}

extension CompiledStub {
    /// Backs a read-write property requirement of the conformer with stored
    /// state.
    ///
    /// See ``Stub/whenProperty(initialValue:get:set:fileID:filePath:line:column:)``.
    @discardableResult
    public func whenProperty<Value>(
        initialValue: Value,
        get: (T) throws -> Value,
        set: (inout T, Value) throws -> Void,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> StubbedProperty<Value> {
        let getter = when(
            returning: initialValue,
            get,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
        let setter = when(
            { (value: inout T) in try set(&value, Match.any(using: initialValue)) },
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
        return StubbedProperty(initialValue: initialValue, getter: getter, setter: setter)
    }
}
