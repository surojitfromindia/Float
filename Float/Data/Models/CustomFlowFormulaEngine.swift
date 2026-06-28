import Foundation

indirect enum CustomFlowFormulaNode: Codable, Equatable {
    case number(Double)
    case text(String)
    case bool(Bool)
    case field(UUID)
    case arithmetic(CustomFlowFormulaArithmeticOperator, CustomFlowFormulaNode, CustomFlowFormulaNode)
    case comparison(CustomFlowFormulaComparisonOperator, CustomFlowFormulaNode, CustomFlowFormulaNode)
    case condition(condition: CustomFlowFormulaNode, then: CustomFlowFormulaNode, else: CustomFlowFormulaNode)
    case today
    case addDays(date: CustomFlowFormulaNode, days: CustomFlowFormulaNode)
    case daysBetween(start: CustomFlowFormulaNode, end: CustomFlowFormulaNode)
    case relationLookup(relationFieldID: UUID, targetFieldID: UUID)
    case childSum(relationID: UUID, fieldID: UUID)
}

struct CustomFlowFormulaDefinition: Codable, Equatable {
    var root: CustomFlowFormulaNode

    static let empty = CustomFlowFormulaDefinition(root: .number(0))

    init(root: CustomFlowFormulaNode) {
        self.root = root
    }

    init?(rawValue: String?) {
        guard let data = rawValue?.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = decoded
    }

    var rawValue: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

}

enum CustomFlowFormulaArithmeticOperator: String, Codable, CaseIterable, Identifiable {
    case add
    case subtract
    case multiply
    case divide

    var id: String { rawValue }
}

enum CustomFlowFormulaComparisonOperator: String, Codable, CaseIterable, Identifiable {
    case equal
    case notEqual
    case greaterThan
    case greaterThanOrEqual
    case lessThan
    case lessThanOrEqual

    var id: String { rawValue }
}

enum CustomFlowFormulaValue: Equatable {
    case number(Double)
    case moneyMinor(Int64)
    case text(String)
    case bool(Bool)
    case date(Date)
    case record(CustomFlowRecordItem)
    case empty

    static func == (lhs: CustomFlowFormulaValue, rhs: CustomFlowFormulaValue) -> Bool {
        switch (lhs, rhs) {
        case let (.number(lhs), .number(rhs)): lhs == rhs
        case let (.moneyMinor(lhs), .moneyMinor(rhs)): lhs == rhs
        case let (.text(lhs), .text(rhs)): lhs == rhs
        case let (.bool(lhs), .bool(rhs)): lhs == rhs
        case let (.date(lhs), .date(rhs)): lhs == rhs
        case let (.record(lhs), .record(rhs)): lhs.id == rhs.id
        case (.empty, .empty): true
        default: false
        }
    }

    var numberLikeValue: Double? {
        switch self {
        case .number(let value): value
        case .moneyMinor(let value): Double(value)
        default: nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }

    var dateValue: Date? {
        if case .date(let value) = self { value } else { nil }
    }

    var amountMinor: Int64? {
        if case .moneyMinor(let value) = self { value } else { nil }
    }
}

struct CustomFlowFormulaEvaluationContext {
    var record: CustomFlowRecordItem
    var objectType: CustomFlowObjectTypeItem
    var records: [CustomFlowRecordItem]
    var draftValues: [UUID: CustomFlowFormulaValue]
    var calendar: Calendar = .current

    init(
        record: CustomFlowRecordItem,
        objectType: CustomFlowObjectTypeItem? = nil,
        records: [CustomFlowRecordItem],
        draftValues: [UUID: CustomFlowFormulaValue] = [:],
        calendar: Calendar = .current
    ) {
        self.record = record
        self.objectType = objectType ?? record.objectType ?? CustomFlowObjectTypeItem(name: "")
        self.records = records
        self.draftValues = draftValues
        self.calendar = calendar
    }
}

struct CustomFlowFormulaValidationIssue: Identifiable, Equatable {
    let id = UUID()
    var message: String
}

enum CustomFlowFormulaEvaluationError: LocalizedError {
    case missingDefinition
    case missingField(String)
    case wrongFieldType(String)
    case brokenRelation(String)
    case invalidOperation(String)
    case circularReference(String)

    var errorDescription: String? {
        switch self {
        case .missingDefinition:
            String(localized: "Formula is not configured.")
        case .missingField(let name):
            String(localized: "Formula references a missing field: \(name)")
        case .wrongFieldType(let name):
            String(localized: "Formula uses the wrong field type: \(name)")
        case .brokenRelation(let name):
            String(localized: "Formula references a broken relation: \(name)")
        case .invalidOperation(let name):
            String(localized: "Formula has an invalid operation: \(name)")
        case .circularReference(let name):
            String(localized: "Formula has a circular reference: \(name)")
        }
    }
}

enum CustomFlowFormulaEngine {
    static func validate(
        field: CustomFlowFieldItem,
        in objectType: CustomFlowObjectTypeItem
    ) -> [CustomFlowFormulaValidationIssue] {
        guard let definition = CustomFlowFormulaDefinition(rawValue: field.formulaDefinitionRaw) else {
            return [CustomFlowFormulaValidationIssue(message: String(localized: "Formula is not configured."))]
        }
        return validate(definition: definition, rootField: field, in: objectType)
    }

    static func validate(
        definition: CustomFlowFormulaDefinition,
        rootField: CustomFlowFieldItem,
        in objectType: CustomFlowObjectTypeItem
    ) -> [CustomFlowFormulaValidationIssue] {
        var validator = Validator(rootField: rootField, objectType: objectType)
        _ = validator.infer(definition.root, objectType: objectType, path: [])
        return validator.issues
    }

    static func evaluate(
        field: CustomFlowFieldItem,
        context: CustomFlowFormulaEvaluationContext
    ) throws -> CustomFlowFormulaValue {
        guard let definition = CustomFlowFormulaDefinition(rawValue: field.formulaDefinitionRaw) else {
            throw CustomFlowFormulaEvaluationError.missingDefinition
        }
        var evaluator = Evaluator(context: context)
        return try evaluator.evaluate(definition.root, objectType: context.objectType, visitedFieldIDs: [field.id])
    }

    static func value(
        for field: CustomFlowFieldItem,
        record: CustomFlowRecordItem,
        records: [CustomFlowRecordItem],
        draftValues: [UUID: CustomFlowFormulaValue] = [:]
    ) throws -> CustomFlowFormulaValue {
        if field.kind == .formula {
            return try evaluate(
                field: field,
                context: CustomFlowFormulaEvaluationContext(
                    record: record,
                    objectType: record.objectType,
                    records: records,
                    draftValues: draftValues
                )
            )
        }
        if let draftValue = draftValues[field.id] {
            return draftValue
        }
        return record.value(for: field).formulaValue(for: field)
    }
}

private enum FormulaValueKind: Equatable {
    case number
    case money
    case text
    case bool
    case date
    case record
    case empty
    case unknown

    var isNumeric: Bool {
        self == .number || self == .money || self == .unknown
    }
}

private extension CustomFlowFormulaEngine {
    struct Validator {
        let rootField: CustomFlowFieldItem
        let objectType: CustomFlowObjectTypeItem
        var issues: [CustomFlowFormulaValidationIssue] = []

        mutating func infer(
            _ node: CustomFlowFormulaNode,
            objectType currentObjectType: CustomFlowObjectTypeItem,
            path: Set<UUID>
        ) -> FormulaValueKind {
            switch node {
            case .number:
                return .number
            case .text:
                return .text
            case .bool:
                return .bool
            case .today:
                return .date
            case .field(let fieldID):
                guard let field = currentObjectType.activeFormulaFields.first(where: { $0.id == fieldID }) else {
                    append(String(localized: "Formula references a missing field."))
                    return .unknown
                }
                guard field.id != rootField.id else {
                    append(String(localized: "Formula cannot reference itself."))
                    return .unknown
                }
                return valueKind(for: field, objectType: currentObjectType, path: path)
            case .arithmetic(let op, let lhs, let rhs):
                let lhsKind = infer(lhs, objectType: currentObjectType, path: path)
                let rhsKind = infer(rhs, objectType: currentObjectType, path: path)
                guard lhsKind.isNumeric, rhsKind.isNumeric else {
                    append(String(localized: "Arithmetic formulas need number or money fields."))
                    return .unknown
                }
                if op == .multiply || op == .divide {
                    return lhsKind == .money || rhsKind == .money ? .money : .number
                }
                return lhsKind == .money || rhsKind == .money ? .money : .number
            case .comparison(_, let lhs, let rhs):
                _ = infer(lhs, objectType: currentObjectType, path: path)
                _ = infer(rhs, objectType: currentObjectType, path: path)
                return .bool
            case .condition(let condition, let thenNode, let elseNode):
                let conditionKind = infer(condition, objectType: currentObjectType, path: path)
                if conditionKind != .bool && conditionKind != .unknown {
                    append(String(localized: "Condition formulas need a true or false test."))
                }
                let thenKind = infer(thenNode, objectType: currentObjectType, path: path)
                let elseKind = infer(elseNode, objectType: currentObjectType, path: path)
                return thenKind == elseKind ? thenKind : .unknown
            case .addDays(let date, let days):
                let dateKind = infer(date, objectType: currentObjectType, path: path)
                let daysKind = infer(days, objectType: currentObjectType, path: path)
                if dateKind != .date && dateKind != .unknown {
                    append(String(localized: "Add days needs a date field."))
                }
                if !daysKind.isNumeric {
                    append(String(localized: "Add days needs a number of days."))
                }
                return .date
            case .daysBetween(let start, let end):
                let startKind = infer(start, objectType: currentObjectType, path: path)
                let endKind = infer(end, objectType: currentObjectType, path: path)
                if startKind != .date && startKind != .unknown {
                    append(String(localized: "Days between needs date fields."))
                }
                if endKind != .date && endKind != .unknown {
                    append(String(localized: "Days between needs date fields."))
                }
                return .number
            case .relationLookup(let relationFieldID, let targetFieldID):
                guard let relationField = currentObjectType.activeFormulaFields.first(where: { $0.id == relationFieldID }),
                      relationField.kind == .relation,
                      let relation = relationField.relation
                else {
                    append(String(localized: "Relation lookup needs a valid relation field."))
                    return .unknown
                }
                guard let targetObjectType = relation.targetObjectType?.id == currentObjectType.id
                    ? relation.sourceObjectType
                    : relation.targetObjectType
                else {
                    append(String(localized: "Relation lookup references a broken relation."))
                    return .unknown
                }
                guard let targetField = targetObjectType.activeFormulaFields.first(where: { $0.id == targetFieldID }) else {
                    append(String(localized: "Relation lookup references a missing target field."))
                    return .unknown
                }
                return valueKind(for: targetField, objectType: targetObjectType, path: path)
            case .childSum(let relationID, let fieldID):
                guard let flow = currentObjectType.flow,
                      let relation = flow.relations.first(where: { $0.id == relationID && !$0.archived })
                else {
                    append(String(localized: "Child sum references a broken relation."))
                    return .unknown
                }
                guard let childObjectType = childObjectType(for: relation, parent: currentObjectType) else {
                    append(String(localized: "Child sum relation is not connected to this object."))
                    return .unknown
                }
                guard let field = childObjectType.activeFormulaFields.first(where: { $0.id == fieldID }) else {
                    append(String(localized: "Child sum references a missing child field."))
                    return .unknown
                }
                let kind = valueKind(for: field, objectType: childObjectType, path: path)
                if !kind.isNumeric {
                    append(String(localized: "Child sum needs number or money fields."))
                }
                return kind == .money ? .money : .number
            }
        }

        private mutating func valueKind(
            for field: CustomFlowFieldItem,
            objectType fieldObjectType: CustomFlowObjectTypeItem,
            path: Set<UUID>
        ) -> FormulaValueKind {
            switch field.kind {
            case .number:
                return .number
            case .money:
                return .money
            case .text, .notes, .choice:
                return .text
            case .checkbox:
                return .bool
            case .dateTime:
                return .date
            case .relation:
                return .record
            case .category, .account, .person:
                return .text
            case .formula:
                guard !path.contains(field.id) else {
                    append(String(localized: "Formula has a circular reference."))
                    return .unknown
                }
                guard let definition = CustomFlowFormulaDefinition(rawValue: field.formulaDefinitionRaw) else {
                    append(String(localized: "Formula is not configured."))
                    return .unknown
                }
                return infer(definition.root, objectType: fieldObjectType, path: path.union([field.id]))
            }
        }

        private func childObjectType(
            for relation: CustomFlowRelationItem,
            parent: CustomFlowObjectTypeItem
        ) -> CustomFlowObjectTypeItem? {
            if relation.targetObjectType?.id == parent.id {
                return relation.sourceObjectType
            }
            if relation.sourceObjectType?.id == parent.id {
                return relation.targetObjectType
            }
            return nil
        }

        private mutating func append(_ message: String) {
            guard !issues.contains(where: { $0.message == message }) else { return }
            issues.append(CustomFlowFormulaValidationIssue(message: message))
        }
    }

    struct Evaluator {
        let context: CustomFlowFormulaEvaluationContext

        mutating func evaluate(
            _ node: CustomFlowFormulaNode,
            objectType currentObjectType: CustomFlowObjectTypeItem,
            record currentRecord: CustomFlowRecordItem? = nil,
            visitedFieldIDs: Set<UUID>
        ) throws -> CustomFlowFormulaValue {
            let record = currentRecord ?? context.record
            switch node {
            case .number(let value):
                return .number(value)
            case .text(let value):
                return .text(value)
            case .bool(let value):
                return .bool(value)
            case .today:
                return .date(context.calendar.startOfDay(for: Date()))
            case .field(let fieldID):
                guard let field = currentObjectType.activeFormulaFields.first(where: { $0.id == fieldID }) else {
                    throw CustomFlowFormulaEvaluationError.missingField(fieldID.uuidString)
                }
                return try value(
                    for: field,
                    record: record,
                    objectType: currentObjectType,
                    visitedFieldIDs: visitedFieldIDs
                )
            case .arithmetic(let op, let lhs, let rhs):
                let lhsValue = try evaluate(lhs, objectType: currentObjectType, record: record, visitedFieldIDs: visitedFieldIDs)
                let rhsValue = try evaluate(rhs, objectType: currentObjectType, record: record, visitedFieldIDs: visitedFieldIDs)
                return try arithmetic(op, lhs: lhsValue, rhs: rhsValue)
            case .comparison(let op, let lhs, let rhs):
                let lhsValue = try evaluate(lhs, objectType: currentObjectType, record: record, visitedFieldIDs: visitedFieldIDs)
                let rhsValue = try evaluate(rhs, objectType: currentObjectType, record: record, visitedFieldIDs: visitedFieldIDs)
                return .bool(try compare(op, lhs: lhsValue, rhs: rhsValue))
            case .condition(let condition, let thenNode, let elseNode):
                let conditionValue = try evaluate(condition, objectType: currentObjectType, record: record, visitedFieldIDs: visitedFieldIDs)
                guard let boolValue = conditionValue.boolValue else {
                    throw CustomFlowFormulaEvaluationError.invalidOperation(String(localized: "Condition"))
                }
                return try evaluate(boolValue ? thenNode : elseNode, objectType: currentObjectType, record: record, visitedFieldIDs: visitedFieldIDs)
            case .addDays(let date, let days):
                let dateValue = try evaluate(date, objectType: currentObjectType, record: record, visitedFieldIDs: visitedFieldIDs)
                let daysValue = try evaluate(days, objectType: currentObjectType, record: record, visitedFieldIDs: visitedFieldIDs)
                guard let date = dateValue.dateValue,
                      let days = daysValue.numberLikeValue
                else {
                    throw CustomFlowFormulaEvaluationError.invalidOperation(String(localized: "Add days"))
                }
                return .date(context.calendar.date(byAdding: .day, value: Int(days.rounded()), to: date) ?? date)
            case .daysBetween(let start, let end):
                let startValue = try evaluate(start, objectType: currentObjectType, record: record, visitedFieldIDs: visitedFieldIDs)
                let endValue = try evaluate(end, objectType: currentObjectType, record: record, visitedFieldIDs: visitedFieldIDs)
                guard let start = startValue.dateValue,
                      let end = endValue.dateValue
                else {
                    throw CustomFlowFormulaEvaluationError.invalidOperation(String(localized: "Days between"))
                }
                let components = context.calendar.dateComponents([.day], from: start, to: end)
                return .number(Double(components.day ?? 0))
            case .relationLookup(let relationFieldID, let targetFieldID):
                guard let relationField = currentObjectType.activeFormulaFields.first(where: { $0.id == relationFieldID }),
                      relationField.kind == .relation
                else {
                    throw CustomFlowFormulaEvaluationError.brokenRelation(relationFieldID.uuidString)
                }
                let relationValue = try value(
                    for: relationField,
                    record: record,
                    objectType: currentObjectType,
                    visitedFieldIDs: visitedFieldIDs
                )
                guard case .record(let relatedRecord) = relationValue,
                      let relatedObjectType = relatedRecord.objectType,
                      let targetField = relatedObjectType.activeFormulaFields.first(where: { $0.id == targetFieldID })
                else {
                    throw CustomFlowFormulaEvaluationError.brokenRelation(relationField.name)
                }
                return try value(
                    for: targetField,
                    record: relatedRecord,
                    objectType: relatedObjectType,
                    visitedFieldIDs: visitedFieldIDs
                )
            case .childSum(let relationID, let fieldID):
                guard let relation = currentObjectType.flow?.relations.first(where: { $0.id == relationID && !$0.archived }),
                      let childObjectType = childObjectType(for: relation, parent: currentObjectType),
                      let sumField = childObjectType.activeFormulaFields.first(where: { $0.id == fieldID })
                else {
                    throw CustomFlowFormulaEvaluationError.brokenRelation(relationID.uuidString)
                }
                var numberTotal = 0.0
                var moneyTotal: Int64 = 0
                var usesMoney = false
                for childRecord in childRecords(for: relation, parentRecord: record, childObjectType: childObjectType) {
                    let value = try value(
                        for: sumField,
                        record: childRecord,
                        objectType: childObjectType,
                        visitedFieldIDs: visitedFieldIDs
                    )
                    switch value {
                    case .moneyMinor(let minor):
                        usesMoney = true
                        moneyTotal += minor
                    case .number(let number):
                        numberTotal += number
                    case .empty:
                        continue
                    default:
                        throw CustomFlowFormulaEvaluationError.wrongFieldType(sumField.name)
                    }
                }
                return usesMoney ? .moneyMinor(moneyTotal + Int64(numberTotal.rounded())) : .number(numberTotal)
            }
        }

        private mutating func value(
            for field: CustomFlowFieldItem,
            record: CustomFlowRecordItem,
            objectType: CustomFlowObjectTypeItem,
            visitedFieldIDs: Set<UUID>
        ) throws -> CustomFlowFormulaValue {
            if field.kind == .formula {
                guard !visitedFieldIDs.contains(field.id) else {
                    throw CustomFlowFormulaEvaluationError.circularReference(field.name)
                }
                guard let definition = CustomFlowFormulaDefinition(rawValue: field.formulaDefinitionRaw) else {
                    throw CustomFlowFormulaEvaluationError.missingDefinition
                }
                return try evaluate(
                    definition.root,
                    objectType: objectType,
                    record: record,
                    visitedFieldIDs: visitedFieldIDs.union([field.id])
                )
            }
            if record.id == context.record.id,
               let draftValue = context.draftValues[field.id] {
                return draftValue
            }
            return record.value(for: field).formulaValue(for: field)
        }

        private func arithmetic(
            _ op: CustomFlowFormulaArithmeticOperator,
            lhs: CustomFlowFormulaValue,
            rhs: CustomFlowFormulaValue
        ) throws -> CustomFlowFormulaValue {
            switch op {
            case .add:
                if case .moneyMinor(let lhsMinor) = lhs,
                   case .moneyMinor(let rhsMinor) = rhs {
                    return .moneyMinor(lhsMinor + rhsMinor)
                }
                return try numeric(op) { $0 + $1 }(lhs, rhs)
            case .subtract:
                if case .moneyMinor(let lhsMinor) = lhs,
                   case .moneyMinor(let rhsMinor) = rhs {
                    return .moneyMinor(lhsMinor - rhsMinor)
                }
                return try numeric(op) { $0 - $1 }(lhs, rhs)
            case .multiply:
                if case .moneyMinor(let minor) = lhs,
                   let multiplier = rhs.numberLikeValue {
                    return .moneyMinor(Int64((Double(minor) * multiplier).rounded()))
                }
                if case .moneyMinor(let minor) = rhs,
                   let multiplier = lhs.numberLikeValue {
                    return .moneyMinor(Int64((Double(minor) * multiplier).rounded()))
                }
                return try numeric(op) { $0 * $1 }(lhs, rhs)
            case .divide:
                if case .moneyMinor(let minor) = lhs,
                   let divisor = rhs.numberLikeValue,
                   divisor != 0 {
                    return .moneyMinor(Int64((Double(minor) / divisor).rounded()))
                }
                return try numeric(op) { rhsValue, lhsValue in
                    guard lhsValue != 0 else { return 0 }
                    return rhsValue / lhsValue
                }(lhs, rhs)
            }
        }

        private func numeric(
            _ op: CustomFlowFormulaArithmeticOperator,
            operation: @escaping (Double, Double) -> Double
        ) throws -> (CustomFlowFormulaValue, CustomFlowFormulaValue) throws -> CustomFlowFormulaValue {
            { lhs, rhs in
                guard let lhsValue = lhs.numberLikeValue,
                      let rhsValue = rhs.numberLikeValue
                else {
                    throw CustomFlowFormulaEvaluationError.invalidOperation(op.rawValue)
                }
                return .number(operation(lhsValue, rhsValue))
            }
        }

        private func compare(
            _ op: CustomFlowFormulaComparisonOperator,
            lhs: CustomFlowFormulaValue,
            rhs: CustomFlowFormulaValue
        ) throws -> Bool {
            if let lhsValue = lhs.numberLikeValue,
               let rhsValue = rhs.numberLikeValue {
                return compareValues(op, lhs: lhsValue, rhs: rhsValue)
            }
            if case .text(let lhsText) = lhs,
               case .text(let rhsText) = rhs {
                return compareValues(op, lhs: lhsText, rhs: rhsText)
            }
            if case .date(let lhsDate) = lhs,
               case .date(let rhsDate) = rhs {
                return compareValues(op, lhs: lhsDate, rhs: rhsDate)
            }
            if case .bool(let lhsBool) = lhs,
               case .bool(let rhsBool) = rhs {
                switch op {
                case .equal: return lhsBool == rhsBool
                case .notEqual: return lhsBool != rhsBool
                default: throw CustomFlowFormulaEvaluationError.invalidOperation(op.rawValue)
                }
            }
            throw CustomFlowFormulaEvaluationError.invalidOperation(op.rawValue)
        }

        private func compareValues<T: Comparable>(
            _ op: CustomFlowFormulaComparisonOperator,
            lhs: T,
            rhs: T
        ) -> Bool {
            switch op {
            case .equal: lhs == rhs
            case .notEqual: lhs != rhs
            case .greaterThan: lhs > rhs
            case .greaterThanOrEqual: lhs >= rhs
            case .lessThan: lhs < rhs
            case .lessThanOrEqual: lhs <= rhs
            }
        }

        private func childObjectType(
            for relation: CustomFlowRelationItem,
            parent: CustomFlowObjectTypeItem
        ) -> CustomFlowObjectTypeItem? {
            if relation.targetObjectType?.id == parent.id {
                return relation.sourceObjectType
            }
            if relation.sourceObjectType?.id == parent.id {
                return relation.targetObjectType
            }
            return nil
        }

        private func childRecords(
            for relation: CustomFlowRelationItem,
            parentRecord: CustomFlowRecordItem,
            childObjectType: CustomFlowObjectTypeItem
        ) -> [CustomFlowRecordItem] {
            let relationFields = childObjectType.activeFormulaFields.filter {
                $0.kind == .relation && $0.relation?.id == relation.id
            }
            return context.records.filter { candidate in
                candidate.objectType?.id == childObjectType.id
                    && candidate.status != .archived
                    && relationFields.contains { field in
                        candidate.value(for: field)?.relatedRecord?.id == parentRecord.id
                    }
            }
        }
    }
}

extension CustomFlowFieldItem {
    var parsedFormulaDefinition: CustomFlowFormulaDefinition? {
        CustomFlowFormulaDefinition(rawValue: formulaDefinitionRaw)
    }
}

extension CustomFlowRecordItem {
    func value(for field: CustomFlowFieldItem) -> CustomFlowFieldValueItem? {
        values.first { $0.field?.id == field.id }
    }
}

private extension Optional where Wrapped == CustomFlowFieldValueItem {
    func formulaValue(for field: CustomFlowFieldItem) -> CustomFlowFormulaValue {
        guard let value = self else { return .empty }
        switch field.kind {
        case .number:
            return value.numberValue.map(CustomFlowFormulaValue.number) ?? .empty
        case .money:
            return value.amountMinor.map(CustomFlowFormulaValue.moneyMinor) ?? .empty
        case .text, .notes, .choice:
            return value.valueRaw.map(CustomFlowFormulaValue.text) ?? .empty
        case .checkbox:
            return value.boolValue.map(CustomFlowFormulaValue.bool) ?? .empty
        case .dateTime:
            return value.dateValue.map(CustomFlowFormulaValue.date) ?? .empty
        case .relation:
            return value.relatedRecord.map(CustomFlowFormulaValue.record) ?? .empty
        case .category:
            return value.category.map { .text($0.name) } ?? .empty
        case .account:
            return value.account.map { .text($0.name) } ?? .empty
        case .person:
            return value.person.map { .text($0.name) } ?? .empty
        case .formula:
            return .empty
        }
    }
}

private extension CustomFlowObjectTypeItem {
    var activeFormulaFields: [CustomFlowFieldItem] {
        fields
            .filter { !$0.archived }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }
}
