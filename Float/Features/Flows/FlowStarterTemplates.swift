import SwiftUI

enum FlowStarterTemplate: String, CaseIterable, Identifiable {
    case grocery
    case subscriptions
    case travel
    case borrowing
    case wishlist
    case assets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grocery: String(localized: "Grocery shopping")
        case .subscriptions: String(localized: "Subscriptions")
        case .travel: String(localized: "Travel plan")
        case .borrowing: String(localized: "Borrowing tracker")
        case .wishlist: String(localized: "Wishlist")
        case .assets: String(localized: "Assets and maintenance")
        }
    }

    var subtitle: String {
        switch self {
        case .grocery:
            String(localized: "Products, trips, and line items for grocery runs.")
        case .subscriptions:
            String(localized: "Recurring services with amount, billing, and account fields.")
        case .travel:
            String(localized: "Trips and expenses linked together for planning.")
        case .borrowing:
            String(localized: "Track who owes what, due dates, and settlement status.")
        case .wishlist:
            String(localized: "Items to buy later with price, priority, and notes.")
        case .assets:
            String(localized: "Assets, warranties, and maintenance entries.")
        }
    }

    var iconKey: String {
        switch self {
        case .grocery: "cart.fill"
        case .subscriptions: "repeat.circle.fill"
        case .travel: "airplane.circle.fill"
        case .borrowing: "person.2.fill"
        case .wishlist: "star.fill"
        case .assets: "house.and.flag.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .grocery: "#2F7D32"
        case .subscriptions: "#5B5FC7"
        case .travel: "#0D7EA2"
        case .borrowing: "#A15C1B"
        case .wishlist: "#B83A5A"
        case .assets: "#53655A"
        }
    }

    func install(using repository: CustomFlowRepository) throws -> CustomFlowItem {
        switch self {
        case .grocery: try installGrocery(using: repository)
        case .subscriptions: try installSubscriptions(using: repository)
        case .travel: try installTravel(using: repository)
        case .borrowing: try installBorrowing(using: repository)
        case .wishlist: try installWishlist(using: repository)
        case .assets: try installAssets(using: repository)
        }
    }

    private func installGrocery(using repository: CustomFlowRepository) throws -> CustomFlowItem {
        let flow = try createFlow(using: repository)
        let products = try repository.createObjectType(
            in: flow,
            name: String(localized: "Products"),
            singularName: String(localized: "Product"),
            iconKey: "carrot.fill",
            sortOrder: 0
        )
        try addField(repository, to: products, name: String(localized: "Unit"), key: "unit", kind: .text)
        try addField(repository, to: products, name: String(localized: "Shelf price"), key: "shelf_price", kind: .money)
        try addField(repository, to: products, name: String(localized: "Category"), key: "category", kind: .category)
        try addField(repository, to: products, name: String(localized: "Needed"), key: "needed", kind: .checkbox)

        let trips = try repository.createObjectType(
            in: flow,
            name: String(localized: "Shopping trips"),
            singularName: String(localized: "Shopping trip"),
            iconKey: "basket.fill",
            sortOrder: 1
        )
        try addField(repository, to: trips, name: String(localized: "Store"), key: "store", kind: .text)
        let tripDate = try addField(repository, to: trips, name: String(localized: "Date"), key: "date", kind: .dateTime)
        let tripCategory = try addField(repository, to: trips, name: String(localized: "Category"), key: "category", kind: .category)
        let tripAccount = try addField(repository, to: trips, name: String(localized: "Account"), key: "account", kind: .account)
        let tripNotes = try addField(repository, to: trips, name: String(localized: "Notes"), key: "notes", kind: .notes)

        let items = try repository.createObjectType(
            in: flow,
            name: String(localized: "Shopping items"),
            singularName: String(localized: "Shopping item"),
            iconKey: "checklist",
            sortOrder: 2
        )
        let productRelation = try repository.createRelation(
            in: flow,
            name: String(localized: "Shopping item product"),
            kind: .belongsTo,
            sourceObjectType: items,
            targetObjectType: products,
            sortOrder: 0
        )
        let tripRelation = try repository.createRelation(
            in: flow,
            name: String(localized: "Shopping trip item"),
            kind: .belongsTo,
            sourceObjectType: items,
            targetObjectType: trips,
            sortOrder: 1
        )
        try addField(repository, to: items, name: String(localized: "Product"), key: "product", kind: .relation, relation: productRelation)
        try addField(repository, to: items, name: String(localized: "Trip"), key: "trip", kind: .relation, relation: tripRelation)
        let itemQuantity = try addField(repository, to: items, name: String(localized: "Quantity"), key: "quantity", kind: .number)
        let itemPrice = try addField(repository, to: items, name: String(localized: "Price"), key: "price", kind: .money)
        let itemLineTotal = try addField(
            repository,
            to: items,
            name: String(localized: "Line total"),
            key: "line_total",
            kind: .formula,
            formula: .arithmetic(.multiply, .field(itemQuantity.id), .field(itemPrice.id))
        )
        try addField(repository, to: items, name: String(localized: "Bought"), key: "bought", kind: .checkbox)
        let tripTotal = try addField(
            repository,
            to: trips,
            name: String(localized: "Total"),
            key: "total",
            kind: .formula,
            formula: .childSum(relationID: tripRelation.id, fieldID: itemLineTotal.id)
        )
        _ = try repository.createTransactionAction(
            in: flow,
            name: String(localized: "Create grocery transaction"),
            sourceObjectType: trips,
            trigger: .finalize,
            isExpense: true,
            amountField: tripTotal,
            categoryField: tripCategory,
            accountField: tripAccount,
            dateField: tripDate,
            noteField: tripNotes,
            fixedCategory: nil,
            fixedAccount: nil,
            fixedNote: nil
        )
        return flow
    }

    private func installSubscriptions(using repository: CustomFlowRepository) throws -> CustomFlowItem {
        let flow = try createFlow(using: repository)
        let subscriptions = try repository.createObjectType(
            in: flow,
            name: String(localized: "Subscriptions"),
            singularName: String(localized: "Subscription"),
            iconKey: "repeat.circle.fill",
            sortOrder: 0
        )
        try addField(repository, to: subscriptions, name: String(localized: "Amount"), key: "amount", kind: .money, required: true)
        try addField(repository, to: subscriptions, name: String(localized: "Billing date"), key: "billing_date", kind: .dateTime)
        try addField(repository, to: subscriptions, name: String(localized: "Frequency"), key: "frequency", kind: .choice, choices: [
            String(localized: "Monthly"),
            String(localized: "Quarterly"),
            String(localized: "Yearly")
        ])
        try addField(repository, to: subscriptions, name: String(localized: "Account"), key: "account", kind: .account)
        try addField(repository, to: subscriptions, name: String(localized: "Category"), key: "category", kind: .category)
        try addField(repository, to: subscriptions, name: String(localized: "Active"), key: "active", kind: .checkbox)
        let billingDate = subscriptions.fields.first { $0.key == "billing_date" }
        if let billingDate {
            try addField(
                repository,
                to: subscriptions,
                name: String(localized: "Days until billing"),
                key: "days_until_billing",
                kind: .formula,
                formula: .daysBetween(start: .today, end: .field(billingDate.id))
            )
        }
        return flow
    }

    private func installTravel(using repository: CustomFlowRepository) throws -> CustomFlowItem {
        let flow = try createFlow(using: repository)
        let trips = try repository.createObjectType(
            in: flow,
            name: String(localized: "Trips"),
            singularName: String(localized: "Trip"),
            iconKey: "airplane.circle.fill",
            sortOrder: 0
        )
        try addField(repository, to: trips, name: String(localized: "Destination"), key: "destination", kind: .text, required: true)
        try addField(repository, to: trips, name: String(localized: "Start date"), key: "start_date", kind: .dateTime)
        let tripBudget = try addField(repository, to: trips, name: String(localized: "Budget"), key: "budget", kind: .money)
        try addField(repository, to: trips, name: String(localized: "Notes"), key: "notes", kind: .notes)

        let expenses = try repository.createObjectType(
            in: flow,
            name: String(localized: "Trip expenses"),
            singularName: String(localized: "Trip expense"),
            iconKey: "creditcard.fill",
            sortOrder: 1
        )
        let relation = try repository.createRelation(
            in: flow,
            name: String(localized: "Trip expense trip"),
            kind: .belongsTo,
            sourceObjectType: expenses,
            targetObjectType: trips,
            sortOrder: 0
        )
        try addField(repository, to: expenses, name: String(localized: "Trip"), key: "trip", kind: .relation, relation: relation)
        let expenseAmount = try addField(repository, to: expenses, name: String(localized: "Amount"), key: "amount", kind: .money, required: true)
        try addField(repository, to: expenses, name: String(localized: "Category"), key: "category", kind: .category)
        try addField(repository, to: expenses, name: String(localized: "Paid by"), key: "paid_by", kind: .person)
        try addField(repository, to: expenses, name: String(localized: "Date"), key: "date", kind: .dateTime)
        let spent = try addField(
            repository,
            to: trips,
            name: String(localized: "Spent"),
            key: "spent",
            kind: .formula,
            formula: .childSum(relationID: relation.id, fieldID: expenseAmount.id)
        )
        try addField(
            repository,
            to: trips,
            name: String(localized: "Remaining budget"),
            key: "remaining_budget",
            kind: .formula,
            formula: .arithmetic(.subtract, .field(tripBudget.id), .field(spent.id))
        )
        return flow
    }

    private func installBorrowing(using repository: CustomFlowRepository) throws -> CustomFlowItem {
        let flow = try createFlow(using: repository)
        let loans = try repository.createObjectType(
            in: flow,
            name: String(localized: "Loans"),
            singularName: String(localized: "Loan"),
            iconKey: "person.2.fill",
            sortOrder: 0
        )
        try addField(repository, to: loans, name: String(localized: "Person"), key: "person", kind: .person, required: true)
        let loanAmount = try addField(repository, to: loans, name: String(localized: "Amount"), key: "amount", kind: .money, required: true)
        let repaid = try addField(repository, to: loans, name: String(localized: "Repaid"), key: "repaid", kind: .money)
        try addField(repository, to: loans, name: String(localized: "Direction"), key: "direction", kind: .choice, choices: [
            String(localized: "I owe"),
            String(localized: "They owe")
        ])
        try addField(repository, to: loans, name: String(localized: "Due date"), key: "due_date", kind: .dateTime)
        try addField(repository, to: loans, name: String(localized: "Settled"), key: "settled", kind: .checkbox)
        let remaining = try addField(
            repository,
            to: loans,
            name: String(localized: "Remaining balance"),
            key: "remaining_balance",
            kind: .formula,
            formula: .arithmetic(.subtract, .field(loanAmount.id), .field(repaid.id))
        )
        try addField(
            repository,
            to: loans,
            name: String(localized: "Status summary"),
            key: "status_summary",
            kind: .formula,
            formula: .condition(
                condition: .comparison(.greaterThan, .field(remaining.id), .number(0)),
                then: .text(String(localized: "Open")),
                else: .text(String(localized: "Settled"))
            )
        )
        try addField(repository, to: loans, name: String(localized: "Notes"), key: "notes", kind: .notes)
        return flow
    }

    private func installWishlist(using repository: CustomFlowRepository) throws -> CustomFlowItem {
        let flow = try createFlow(using: repository)
        let items = try repository.createObjectType(
            in: flow,
            name: String(localized: "Wishlist items"),
            singularName: String(localized: "Wishlist item"),
            iconKey: "star.fill",
            sortOrder: 0
        )
        try addField(repository, to: items, name: String(localized: "Price"), key: "price", kind: .money)
        try addField(repository, to: items, name: String(localized: "Priority"), key: "priority", kind: .choice, choices: [
            String(localized: "Low"),
            String(localized: "Medium"),
            String(localized: "High")
        ])
        try addField(repository, to: items, name: String(localized: "Link"), key: "link", kind: .text)
        let bought = try addField(repository, to: items, name: String(localized: "Bought"), key: "bought", kind: .checkbox)
        try addField(
            repository,
            to: items,
            name: String(localized: "Status summary"),
            key: "status_summary",
            kind: .formula,
            formula: .condition(
                condition: .field(bought.id),
                then: .text(String(localized: "Bought")),
                else: .text(String(localized: "Planned"))
            )
        )
        try addField(repository, to: items, name: String(localized: "Notes"), key: "notes", kind: .notes)
        return flow
    }

    private func installAssets(using repository: CustomFlowRepository) throws -> CustomFlowItem {
        let flow = try createFlow(using: repository)
        let assets = try repository.createObjectType(
            in: flow,
            name: String(localized: "Assets"),
            singularName: String(localized: "Asset"),
            iconKey: "house.and.flag.fill",
            sortOrder: 0
        )
        try addField(repository, to: assets, name: String(localized: "Purchase price"), key: "purchase_price", kind: .money)
        try addField(repository, to: assets, name: String(localized: "Purchase date"), key: "purchase_date", kind: .dateTime)
        try addField(repository, to: assets, name: String(localized: "Warranty until"), key: "warranty_until", kind: .dateTime)
        try addField(repository, to: assets, name: String(localized: "Location"), key: "location", kind: .text)

        let maintenance = try repository.createObjectType(
            in: flow,
            name: String(localized: "Maintenance entries"),
            singularName: String(localized: "Maintenance entry"),
            iconKey: "wrench.adjustable.fill",
            sortOrder: 1
        )
        let relation = try repository.createRelation(
            in: flow,
            name: String(localized: "Maintenance asset"),
            kind: .belongsTo,
            sourceObjectType: maintenance,
            targetObjectType: assets,
            sortOrder: 0
        )
        try addField(repository, to: maintenance, name: String(localized: "Asset"), key: "asset", kind: .relation, relation: relation)
        let maintenanceCost = try addField(repository, to: maintenance, name: String(localized: "Cost"), key: "cost", kind: .money)
        try addField(repository, to: maintenance, name: String(localized: "Date"), key: "date", kind: .dateTime)
        try addField(repository, to: maintenance, name: String(localized: "Notes"), key: "notes", kind: .notes)
        try addField(
            repository,
            to: assets,
            name: String(localized: "Maintenance total"),
            key: "maintenance_total",
            kind: .formula,
            formula: .childSum(relationID: relation.id, fieldID: maintenanceCost.id)
        )
        return flow
    }

    private func createFlow(using repository: CustomFlowRepository) throws -> CustomFlowItem {
        try repository.createFlow(
            name: title,
            iconKey: iconKey,
            colorHex: colorHex
        )
    }

    @discardableResult
    private func addField(
        _ repository: CustomFlowRepository,
        to objectType: CustomFlowObjectTypeItem,
        name: String,
        key: String,
        kind: CustomFlowFieldKind,
        required: Bool = false,
        choices: [String] = [],
        relation: CustomFlowRelationItem? = nil,
        formula: CustomFlowFormulaNode? = nil
    ) throws -> CustomFlowFieldItem {
        try repository.createField(
            in: objectType,
            name: name,
            key: key,
            kind: kind,
            sortOrder: objectType.fields.count,
            required: required,
            choiceOptionsRaw: choices.isEmpty ? nil : choices.joined(separator: "\n"),
            formulaDefinitionRaw: formula.flatMap { CustomFlowFormulaDefinition(root: $0).rawValue },
            relation: relation
        )
    }
}
