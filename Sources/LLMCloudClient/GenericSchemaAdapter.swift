import Foundation
import LLMClient

/// Which JSON Schema keywords a provider's structured-output endpoint actually honors.
///
/// The schema a caller writes with `@Structured` is full JSON Schema, but no provider accepts
/// all of it: each supports a different subset and rejects the request outright when an
/// unsupported keyword appears. A provider contributes only this table of differences, and
/// ``GenericSchemaAdapter`` does the recursive walk and the stripping.
package struct SchemaCapabilities: Sendable {
    /// How `minItems` on an array survives the trip to the provider.
    package enum MinItemsPolicy: Sendable {
        /// Always strip it. OpenAI structured outputs reject it.
        case remove
        /// Keep 0 and 1, strip anything larger. Anthropic accepts no other value.
        case keepIfAtMostOne
        /// Send it through untouched. Gemini honors arbitrary values.
        case keep
    }

    /// How the `format` annotation on a string survives.
    package enum FormatPolicy: Sendable {
        /// Send every format through. Anthropic.
        case keepAll
        /// Strip every format. OpenAI strict mode rejects the keyword.
        case removeAll
        /// Keep only the listed formats and strip the rest. Gemini recognizes a fixed few.
        case whitelist(Set<String>)
    }

    /// How `additionalProperties` is set on the schema sent to the provider.
    package enum AdditionalPropertiesPolicy: Sendable {
        /// Send whatever the source schema said. Anthropic.
        case passthrough
        /// Drop the keyword entirely. Gemini does not accept it.
        case removeToNil
        /// Force false on every object. OpenAI strict mode requires it on all of them.
        case forceFalseOnObjects
    }

    /// How the `required` list of an object is rewritten.
    package enum RequiredPolicy: Sendable {
        /// Send the caller's list unchanged.
        case passthrough
        /// List every property as required. OpenAI strict mode admits no optional property, so
        /// optionality has to be expressed as nullability instead.
        case allPropertiesOnObjects
    }

    package var minItems: MinItemsPolicy

    /// Whether `maxItems` is kept. False strips it.
    package var maxItems: Bool

    /// Whether `minimum` and `maximum` are kept. False strips both.
    package var numericRange: Bool

    /// Whether `exclusiveMinimum` and `exclusiveMaximum` are kept. False strips both.
    package var exclusiveRange: Bool

    /// Whether `minLength` and `maxLength` are kept. False strips both.
    package var stringLength: Bool

    /// Whether a `pattern` regex is kept. False strips it.
    package var pattern: Bool

    package var format: FormatPolicy
    package var additionalProperties: AdditionalPropertiesPolicy
    package var required: RequiredPolicy

    package init(
        minItems: MinItemsPolicy,
        maxItems: Bool,
        numericRange: Bool,
        exclusiveRange: Bool,
        stringLength: Bool,
        pattern: Bool,
        format: FormatPolicy,
        additionalProperties: AdditionalPropertiesPolicy,
        required: RequiredPolicy
    ) {
        self.minItems = minItems
        self.maxItems = maxItems
        self.numericRange = numericRange
        self.exclusiveRange = exclusiveRange
        self.stringLength = stringLength
        self.pattern = pattern
        self.format = format
        self.additionalProperties = additionalProperties
        self.required = required
    }

    /// Anthropic Messages API with constrained decoding.
    ///
    /// Keeps `pattern` and every `format`, allows `minItems` of 0 or 1, passes
    /// `additionalProperties` and `required` through untouched, and drops the numeric and
    /// string-length bounds.
    package static let anthropic = SchemaCapabilities(
        minItems: .keepIfAtMostOne, maxItems: false, numericRange: false, exclusiveRange: false,
        stringLength: false, pattern: true, format: .keepAll,
        additionalProperties: .passthrough, required: .passthrough
    )

    /// OpenAI structured outputs in strict mode, also used by the OpenAI-compatible vendors.
    ///
    /// The most restrictive of the three: every validation keyword is stripped, every object
    /// gets `additionalProperties: false`, and every property is listed as required with the
    /// originally optional ones turned nullable.
    package static let openAI = SchemaCapabilities(
        minItems: .remove, maxItems: false, numericRange: false, exclusiveRange: false,
        stringLength: false, pattern: false, format: .removeAll,
        additionalProperties: .forceFalseOnObjects, required: .allPropertiesOnObjects
    )

    /// Google Gemini structured responses.
    ///
    /// The only one that keeps array and numeric bounds, but it drops `additionalProperties`
    /// entirely, rejects `pattern`, and recognizes only the three date and time formats.
    package static let gemini = SchemaCapabilities(
        minItems: .keep, maxItems: true, numericRange: true, exclusiveRange: false,
        stringLength: false, pattern: false, format: .whitelist(["date-time", "date", "time"]),
        additionalProperties: .removeToNil, required: .passthrough
    )
}

/// Downgrades a JSON Schema to the subset one provider accepts, and records what it took out.
///
/// Walks the schema depth first, applying the provider's ``SchemaCapabilities`` at every node
/// and collecting a ``RemovedConstraint`` for each keyword it had to drop, tagged with a dotted
/// field path (`user.tags[]` for the element type of an array property). Each provider's own
/// adapter is a one-line delegation to this type with its own capability table.
///
/// A dropped constraint is not silently lost: providers turn the recorded set into a
/// natural-language block appended to the system prompt, so a `pattern` OpenAI will not enforce
/// still reaches the model as an instruction. It becomes a request rather than a guarantee —
/// the decoder no longer rejects output that violates it.
///
/// Only the order in which removals are recorded is normalized; the schema that goes on the
/// wire and the set of removals match what the hand-written per-provider adapters produced.
package struct GenericSchemaAdapter: ProviderSchemaAdapter {
    package let capabilities: SchemaCapabilities

    package init(capabilities: SchemaCapabilities) {
        self.capabilities = capabilities
    }

    /// Adapts a schema and throws away the record of what was dropped.
    ///
    /// Use ``adaptWithConstraints(_:fieldPath:)`` instead when the dropped constraints should be
    /// restated to the model in the system prompt.
    package func adapt(_ schema: JSONSchema) -> JSONSchema {
        adaptWithConstraints(schema, fieldPath: "").schema
    }

    /// Adapts a schema and reports every constraint that had to be dropped.
    ///
    /// - Parameters:
    ///   - schema: The schema as the caller declared it.
    ///   - fieldPath: Path prefix for the paths reported on removed constraints. Pass an empty
    ///     string at the root; nested calls extend it with `.property` and `[]`.
    package func adaptWithConstraints(_ schema: JSONSchema, fieldPath: String) -> SchemaAdaptationResult {
        adaptWithConstraints(schema, fieldPath: fieldPath, forceNullable: false)
    }

    /// - Parameter forceNullable: Marks the node nullable regardless of what the source schema
    ///   said. Set for properties the parent treated as optional under a strict provider, where
    ///   optionality can only be expressed as "required, but may be null".
    private func adaptWithConstraints(_ schema: JSONSchema, fieldPath: String, forceNullable: Bool) -> SchemaAdaptationResult {
        var removed: [RemovedConstraint] = []

        // Under strict mode every property is required, so optional ones are turned nullable.
        let strictObjects: Bool
        if case .allPropertiesOnObjects = capabilities.required { strictObjects = true } else { strictObjects = false }

        let (adaptedProperties, propertyConstraints) = adaptProperties(
            schema.properties, parentPath: fieldPath,
            originalRequired: Set(schema.required ?? []), optionalAsNullable: strictObjects
        )
        removed.append(contentsOf: propertyConstraints)
        let (adaptedItems, itemsConstraints) = adaptItems(schema.items, parentPath: fieldPath)
        removed.append(contentsOf: itemsConstraints)

        // minItems
        var adaptedMinItems: Int?
        switch capabilities.minItems {
        case .keep:
            adaptedMinItems = schema.minItems
        case .keepIfAtMostOne:
            if let value = schema.minItems {
                if value <= 1 { adaptedMinItems = value }
                else { removed.append(.init(type: .minItems, fieldPath: fieldPath, value: .int(value))) }
            }
        case .remove:
            if let value = schema.minItems { removed.append(.init(type: .minItems, fieldPath: fieldPath, value: .int(value))) }
        }

        // maxItems / numericRange / exclusiveRange / stringLength / pattern
        let adaptedMaxItems = keepOrRemoveInt(schema.maxItems, kept: capabilities.maxItems, type: .maxItems, fieldPath: fieldPath, into: &removed)
        let adaptedMinimum = keepOrRemoveDouble(schema.minimum, kept: capabilities.numericRange, type: .minimum, fieldPath: fieldPath, into: &removed)
        let adaptedMaximum = keepOrRemoveDouble(schema.maximum, kept: capabilities.numericRange, type: .maximum, fieldPath: fieldPath, into: &removed)
        let adaptedExclMin = keepOrRemoveDouble(schema.exclusiveMinimum, kept: capabilities.exclusiveRange, type: .exclusiveMinimum, fieldPath: fieldPath, into: &removed)
        let adaptedExclMax = keepOrRemoveDouble(schema.exclusiveMaximum, kept: capabilities.exclusiveRange, type: .exclusiveMaximum, fieldPath: fieldPath, into: &removed)
        let adaptedMinLength = keepOrRemoveInt(schema.minLength, kept: capabilities.stringLength, type: .minLength, fieldPath: fieldPath, into: &removed)
        let adaptedMaxLength = keepOrRemoveInt(schema.maxLength, kept: capabilities.stringLength, type: .maxLength, fieldPath: fieldPath, into: &removed)
        var adaptedPattern: String?
        if let pattern = schema.pattern {
            if capabilities.pattern { adaptedPattern = pattern }
            else { removed.append(.init(type: .pattern, fieldPath: fieldPath, value: .string(pattern))) }
        }

        // format
        var adaptedFormat: String?
        if let format = schema.format {
            let keep: Bool
            switch capabilities.format {
            case .keepAll: keep = true
            case .removeAll: keep = false
            case .whitelist(let set): keep = set.contains(format)
            }
            if keep { adaptedFormat = format }
            else { removed.append(.init(type: .format, fieldPath: fieldPath, value: .string(format))) }
        }

        // additionalProperties
        let adaptedAdditional: Bool?
        switch capabilities.additionalProperties {
        case .passthrough: adaptedAdditional = schema.additionalProperties
        case .removeToNil: adaptedAdditional = nil
        case .forceFalseOnObjects: adaptedAdditional = schema.type == .object ? false : schema.additionalProperties
        }

        // required
        let adaptedRequired: [String]?
        switch capabilities.required {
        case .passthrough:
            adaptedRequired = schema.required
        case .allPropertiesOnObjects:
            adaptedRequired = adaptedProperties.map { Array($0.keys).sorted() } ?? schema.required
        }

        // An object under strict mode (OpenAI, Groq) must carry `properties` even when empty:
        // omitting it is rejected with "'required' present but 'properties' is missing", or by
        // the consistency check on additionalProperties:false. Hit by no-argument tools.
        var finalProperties = adaptedProperties
        if schema.type == .object, finalProperties == nil, strictObjects || adaptedRequired != nil {
            finalProperties = [:]
        }

        let adaptedSchema = JSONSchema(
            type: schema.type,
            nullable: schema.nullable || forceNullable,
            description: schema.description,
            properties: finalProperties,
            required: adaptedRequired,
            items: adaptedItems,
            additionalProperties: adaptedAdditional,
            minItems: adaptedMinItems,
            maxItems: adaptedMaxItems,
            minimum: adaptedMinimum,
            maximum: adaptedMaximum,
            exclusiveMinimum: adaptedExclMin,
            exclusiveMaximum: adaptedExclMax,
            minLength: adaptedMinLength,
            maxLength: adaptedMaxLength,
            pattern: adaptedPattern,
            enum: schema.enum,
            format: adaptedFormat
        )
        return SchemaAdaptationResult(schema: adaptedSchema, removedConstraints: removed)
    }

    // MARK: - Helpers

    private func adaptProperties(
        _ properties: [String: JSONSchema]?, parentPath: String,
        originalRequired: Set<String>, optionalAsNullable: Bool
    ) -> ([String: JSONSchema]?, [RemovedConstraint]) {
        guard let properties else { return (nil, []) }
        var adapted: [String: JSONSchema] = [:]
        var constraints: [RemovedConstraint] = []
        for (key, value) in properties {
            let path = parentPath.isEmpty ? key : "\(parentPath).\(key)"
            // Under strict mode a property left out of `required` becomes nullable and required.
            let forceNullable = optionalAsNullable && !originalRequired.contains(key)
            let result = adaptWithConstraints(value, fieldPath: path, forceNullable: forceNullable)
            adapted[key] = result.schema
            constraints.append(contentsOf: result.removedConstraints)
        }
        return (adapted, constraints)
    }

    private func adaptItems(_ items: Box<JSONSchema>?, parentPath: String) -> (JSONSchema?, [RemovedConstraint]) {
        guard let items else { return (nil, []) }
        let result = adaptWithConstraints(items.value, fieldPath: "\(parentPath)[]")
        return (result.schema, result.removedConstraints)
    }

    private func keepOrRemoveInt(_ value: Int?, kept: Bool, type: ConstraintType, fieldPath: String, into removed: inout [RemovedConstraint]) -> Int? {
        guard let value else { return nil }
        if kept { return value }
        removed.append(.init(type: type, fieldPath: fieldPath, value: .int(value)))
        return nil
    }

    private func keepOrRemoveDouble(_ value: Double?, kept: Bool, type: ConstraintType, fieldPath: String, into removed: inout [RemovedConstraint]) -> Double? {
        guard let value else { return nil }
        if kept { return value }
        removed.append(.init(type: type, fieldPath: fieldPath, value: .double(value)))
        return nil
    }
}
