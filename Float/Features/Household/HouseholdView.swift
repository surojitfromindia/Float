import SwiftData
import SwiftUI

struct HouseholdView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \HouseholdMemberItem.createdAt) private var allMembers: [HouseholdMemberItem]
    @Query(sort: \HouseholdExpenseItem.createdAt, order: .reverse) private var allExpenses: [HouseholdExpenseItem]
    @Query(sort: \HouseholdBillItem.dueDate) private var allBills: [HouseholdBillItem]
    @State private var sheet: HouseholdSheet?
    @State private var message = ""

    private var members: [HouseholdMemberItem] {
        filterActiveProfile(allMembers).filter { !$0.archived }
    }

    private var expenses: [HouseholdExpenseItem] {
        filterActiveProfile(allExpenses)
    }

    private var pendingExpenses: [HouseholdExpenseItem] {
        expenses.filter { $0.approvalStatus == .pending }
    }

    private var approvedOpenExpenses: [HouseholdExpenseItem] {
        expenses.filter {
            $0.approvalStatus == .approved
                && $0.reimbursementRequired
                && $0.settledAt == nil
        }
    }

    private var bills: [HouseholdBillItem] {
        filterActiveProfile(allBills).filter(\.active)
    }

    private var dueSoonBills: [HouseholdBillItem] {
        bills.filter(\.isDueSoon)
    }

    private var reimbursementDueMinor: Int64 {
        approvedOpenExpenses.reduce(Int64(0)) { $0 + $1.outstandingReimbursementMinor }
    }

    private var monthSpendMinor: Int64 {
        let calendar = Calendar.current
        return expenses.reduce(Int64(0)) { total, expense in
            guard expense.approvalStatus == .approved,
                  calendar.isDate(expense.expenseDate, equalTo: Date(), toGranularity: .month)
            else { return total }
            return total + expense.amountMinor
        }
    }

    private var memberSummaries: [HouseholdMemberSummary] {
        members.map { member in
            var getsBackMinor = Int64(0)
            var owesMinor = Int64(0)
            var pendingCount = 0

            for expense in approvedOpenExpenses {
                if expense.payer?.id == member.id {
                    getsBackMinor += expense.outstandingReimbursementMinor
                }

                for split in expense.sortedSplits where split.member?.id == member.id {
                    if expense.payer?.id != member.id {
                        owesMinor += split.outstandingMinor
                    }
                }
            }

            for expense in pendingExpenses {
                if expense.payer?.id == member.id
                    || expense.sortedSplits.contains(where: { $0.member?.id == member.id }) {
                    pendingCount += 1
                }
            }

            return HouseholdMemberSummary(
                member: member,
                getsBackMinor: getsBackMinor,
                owesMinor: owesMinor,
                pendingCount: pendingCount
            )
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                nextStepCard
                summaryStrip
                attentionSection
                peopleSection
                billsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .navigationTitle("Household OS")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Split expense", systemImage: "plus.circle.fill") {
                        sheet = .expense
                    }
                    Button("Add member", systemImage: "person.badge.plus") {
                        sheet = .member(nil)
                    }
                    Button("Add bill", systemImage: "calendar.badge.plus") {
                        sheet = .bill
                    }
                    Button("Close out reimbursements", systemImage: "arrow.left.arrow.right.circle.fill") {
                        createCloseout()
                    }
                    .disabled(reimbursementDueMinor == 0)
                } label: {
                    Image(systemName: "plus")
                }
                .tint(appState.themePalette.accent)
            }
        }
        .floatBackground()
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .member(let member):
                HouseholdMemberEditorSheet(member: member)
                    .presentationDetents([.medium, .large])
            case .expense:
                HouseholdExpenseEditorSheet()
                    .presentationDetents([.large])
            case .bill:
                HouseholdBillEditorSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var nextStepCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    FloatIconBadge(icon: nextStep.icon, tint: nextStep.tint, size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(nextStep.title)
                            .font(.headline)
                        Text(nextStep.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Button(action: nextStep.action) {
                    Label(nextStep.buttonTitle, systemImage: nextStep.buttonIcon)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.themePalette.accent)

                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var summaryStrip: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SummaryMetricTile(
                title: "Pending",
                value: "\(pendingExpenses.count)",
                caption: "Need review",
                icon: "checklist",
                tint: appState.themePalette.caution
            )
            SummaryMetricTile(
                title: "To settle",
                value: money(reimbursementDueMinor),
                caption: "Open reimbursements",
                icon: "arrow.left.arrow.right.circle.fill",
                tint: appState.themePalette.accent
            )
            SummaryMetricTile(
                title: "This month",
                value: money(monthSpendMinor),
                caption: "Approved shared spend",
                icon: "calendar",
                tint: Color(hex: "#0A6FAE")
            )
            SummaryMetricTile(
                title: "Bills due",
                value: "\(dueSoonBills.count)",
                caption: "Next 7 days",
                icon: "doc.text.fill",
                tint: Color(hex: "#8A6DD7")
            )
        }
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Needs attention")

            if members.isEmpty {
                HouseholdGuideCard(
                    icon: "person.2.fill",
                    title: "Add your people first",
                    message: "Create one member for each person you split household money with.",
                    buttonTitle: "Add first member",
                    tint: appState.themePalette.accent,
                    action: { sheet = .member(nil) }
                )
            } else if pendingExpenses.isEmpty && dueSoonBills.isEmpty && reimbursementDueMinor == 0 {
                HouseholdGuideCard(
                    icon: "checkmark.seal.fill",
                    title: "Everything is clear",
                    message: "Add a shared expense when someone pays for the household.",
                    buttonTitle: "Split expense",
                    tint: appState.themePalette.accent,
                    action: { sheet = .expense }
                )
            } else {
                ForEach(pendingExpenses.prefix(3)) { expense in
                    HouseholdExpenseReviewRow(
                        expense: expense,
                        currencyCode: appState.selectedCurrencyCode,
                        onApprove: { approve(expense) },
                        onReject: { reject(expense) }
                    )
                }

                ForEach(dueSoonBills.prefix(2)) { bill in
                    HouseholdBillRow(bill: bill, currencyCode: appState.selectedCurrencyCode)
                }

                if reimbursementDueMinor > 0 {
                    HouseholdGuideCard(
                        icon: "arrow.left.arrow.right.circle.fill",
                        title: "Reimbursements are ready",
                        message: "Create settlement cases for everyone who owes money.",
                        buttonTitle: "Close out now",
                        tint: appState.themePalette.accent,
                        action: createCloseout
                    )
                }
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "People",
                actionTitle: "Add",
                action: { sheet = .member(nil) }
            )

            if members.isEmpty {
                EmptyStateView(
                    icon: "person.3.fill",
                    title: "No people yet",
                    message: "People are required before you can split expenses."
                )
                .floatGlassSurface(cornerRadius: FloatTheme.tileRadius)
            } else {
                VStack(spacing: 10) {
                    ForEach(memberSummaries) { summary in
                        Button {
                            sheet = .member(summary.member)
                        } label: {
                            HouseholdPersonRow(
                                summary: summary,
                                currencyCode: appState.selectedCurrencyCode
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var billsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Bills",
                actionTitle: "Add",
                action: { sheet = .bill }
            )

            if bills.isEmpty {
                HouseholdGuideCard(
                    icon: "calendar.badge.plus",
                    title: "Track recurring bills",
                    message: "Add rent, utilities, school fees, or subscriptions that the household reviews together.",
                    buttonTitle: "Add bill",
                    tint: Color(hex: "#8A6DD7"),
                    action: { sheet = .bill }
                )
            } else {
                ForEach(bills.prefix(4)) { bill in
                    HouseholdBillRow(bill: bill, currencyCode: appState.selectedCurrencyCode)
                }
            }
        }
    }

    private var nextStep: HouseholdNextStep {
        if members.isEmpty {
            return HouseholdNextStep(
                icon: "person.2.fill",
                title: "Start with people",
                message: "Add the people who share expenses with you. After that, every split takes only a few taps.",
                buttonTitle: "Add first member",
                buttonIcon: "person.badge.plus",
                tint: appState.themePalette.accent,
                action: { sheet = .member(nil) }
            )
        }

        if let firstPending = pendingExpenses.first {
            return HouseholdNextStep(
                icon: "checklist",
                title: "Review pending expense",
                message: AppLocalization.format(
                    "%@ is waiting to be approved and posted as a transaction.",
                    firstPending.title
                ),
                buttonTitle: "Review queue",
                buttonIcon: "checkmark.circle.fill",
                tint: appState.themePalette.caution,
                action: {}
            )
        }

        if reimbursementDueMinor > 0 {
            return HouseholdNextStep(
                icon: "arrow.left.arrow.right.circle.fill",
                title: "Settle the household",
                message: "Approved splits are ready to become settlement cases.",
                buttonTitle: "Close out reimbursements",
                buttonIcon: "arrow.right.circle.fill",
                tint: appState.themePalette.accent,
                action: createCloseout
            )
        }

        return HouseholdNextStep(
            icon: "plus.circle.fill",
            title: "Add the next shared expense",
            message: "Use this when someone pays for groceries, bills, travel, or anything shared at home.",
            buttonTitle: "Split expense",
            buttonIcon: "plus",
            tint: appState.themePalette.accent,
            action: { sheet = .expense }
        )
    }

    private func money(_ amountMinor: Int64) -> String {
        MoneyFormatter.string(
            minorUnits: amountMinor,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private func approve(_ expense: HouseholdExpenseItem) {
        do {
            try HouseholdRepository(modelContext: modelContext).approveExpense(expense)
            message = "Expense approved."
        } catch {
            message = error.localizedDescription
        }
    }

    private func reject(_ expense: HouseholdExpenseItem) {
        do {
            try HouseholdRepository(modelContext: modelContext).rejectExpense(expense)
            message = "Expense rejected."
        } catch {
            message = error.localizedDescription
        }
    }

    private func createCloseout() {
        do {
            let count = try HouseholdRepository(modelContext: modelContext)
                .createMonthlyCloseout(
                    expenses: expenses,
                    currencyCode: appState.selectedCurrencyCode
                )
            message = count == 0
                ? "No household balances to settle."
                : AppLocalization.format("%lld settlement cases created.", Int64(count))
        } catch {
            message = error.localizedDescription
        }
    }
}

private enum HouseholdSheet: Identifiable {
    case member(HouseholdMemberItem?)
    case expense
    case bill

    var id: String {
        switch self {
        case .member(let member): "member-\(member?.id.uuidString ?? "new")"
        case .expense: "expense"
        case .bill: "bill"
        }
    }
}

private struct HouseholdNextStep {
    let icon: String
    let title: LocalizedStringResource
    let message: String
    let buttonTitle: LocalizedStringResource
    let buttonIcon: String
    let tint: Color
    let action: () -> Void
}

private struct HouseholdMemberSummary: Identifiable {
    let member: HouseholdMemberItem
    let getsBackMinor: Int64
    let owesMinor: Int64
    let pendingCount: Int

    var id: UUID { member.id }
    var netMinor: Int64 { getsBackMinor - owesMinor }
}

private struct HouseholdGuideCard: View {
    let icon: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let buttonTitle: LocalizedStringResource
    let tint: Color
    let action: () -> Void

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    FloatIconBadge(icon: icon, tint: tint, size: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Button(action: action) {
                    Text(buttonTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(tint)
            }
        }
    }
}

private struct HouseholdExpenseReviewRow: View {
    let expense: HouseholdExpenseItem
    let currencyCode: String
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    FloatIconBadge(
                        icon: expense.category?.iconKey ?? "cart.fill",
                        tint: Color(hex: expense.category?.colorHex ?? "#0E7C7B")
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(expense.title)
                            .font(.headline)
                        Text(AppLocalization.format(
                            "%@ paid for %@",
                            expense.payerName,
                            expense.beneficiarySummary
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text(MoneyFormatter.string(minorUnits: expense.amountMinor, currencyCode: currencyCode))
                        .moneyStyle(size: 16, weight: .bold)
                }

                HStack(spacing: 10) {
                    Button("Reject", role: .destructive, action: onReject)
                        .buttonStyle(.bordered)
                    Button("Approve", action: onApprove)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct HouseholdPersonRow: View {
    let summary: HouseholdMemberSummary
    let currencyCode: String

    private var tint: Color {
        Color(hex: summary.member.colorHex)
    }

    private var balanceText: String {
        if summary.netMinor > 0 {
            return AppLocalization.format(
                "Gets back %@",
                MoneyFormatter.string(minorUnits: summary.netMinor, currencyCode: currencyCode)
            )
        }
        if summary.netMinor < 0 {
            return AppLocalization.format(
                "Owes %@",
                MoneyFormatter.string(minorUnits: abs(summary.netMinor), currencyCode: currencyCode)
            )
        }
        return String(localized: "Settled")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(summary.member.displayInitials)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.member.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(summary.member.role.title)
                    Text(balanceText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if summary.pendingCount > 0 {
                Text("\(summary.pendingCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.orange, in: Circle())
                    .accessibilityLabel(AppLocalization.format("%lld pending items", Int64(summary.pendingCount)))
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .floatGlassSurface(cornerRadius: FloatTheme.tileRadius, interactive: true)
    }
}

private struct HouseholdBillRow: View {
    let bill: HouseholdBillItem
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            FloatIconBadge(
                icon: bill.category?.iconKey ?? "doc.text.fill",
                tint: Color(hex: bill.category?.colorHex ?? "#8A6DD7")
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.title)
                    .font(.headline)
                Text(AppLocalization.format(
                    "%@ pays - due %@",
                    bill.payer?.displayName ?? String(localized: "No payer"),
                    bill.dueDate.formatted(date: .abbreviated, time: .omitted)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(MoneyFormatter.string(minorUnits: bill.amountMinor, currencyCode: currencyCode))
                .moneyStyle(size: 15, weight: .semibold)
        }
        .padding(16)
        .floatGlassSurface(cornerRadius: FloatTheme.tileRadius)
    }
}

private struct HouseholdMemberEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    let member: HouseholdMemberItem?
    @State private var name: String
    @State private var role: HouseholdMemberRole
    @State private var colorHex: String
    @State private var allowanceText: String
    @State private var message = ""

    private let colorChoices = ["#0E7C7B", "#0A6FAE", "#8A6DD7", "#B4613B", "#4F8A3B"]

    init(member: HouseholdMemberItem?) {
        self.member = member
        _name = State(initialValue: member?.displayName ?? "")
        _role = State(initialValue: member?.role ?? .adult)
        _colorHex = State(initialValue: member?.colorHex ?? "#0E7C7B")
        _allowanceText = State(
            initialValue: BudgetAmountField.majorAmountString(
                minorUnits: member?.monthlyAllowanceMinor ?? 0,
                currencyCode: MoneyFormatter.currencyCodeFromLocale()
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                    Picker("Role", selection: $role) {
                        ForEach(HouseholdMemberRole.allCases) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Monthly allowance") {
                    TextField("Optional amount", text: $allowanceText)
                        .keyboardType(.decimalPad)
                }

                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(colorChoices, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if colorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppLocalization.format("Choose color %@", hex))
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !message.isEmpty {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(member == nil ? "Add Member" : "Edit Member")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.isBlankForHousehold)
                }
            }
        }
    }

    private func save() {
        do {
            _ = try HouseholdRepository(modelContext: modelContext).saveMember(
                member,
                displayName: name,
                role: role,
                colorHex: colorHex,
                monthlyAllowanceMinor: BudgetAmountField.minorUnits(
                    fromMajorAmount: allowanceText,
                    currencyCode: appState.selectedCurrencyCode
                )
            )
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct HouseholdExpenseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \HouseholdMemberItem.createdAt) private var allMembers: [HouseholdMemberItem]
    @Query(sort: \CategoryItem.sortOrder) private var allCategories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var allAccounts: [AccountItem]
    @State private var title = ""
    @State private var amountText = ""
    @State private var expenseDate = Date()
    @State private var payerID: UUID?
    @State private var selectedMemberIDs = Set<UUID>()
    @State private var splitMethod = HouseholdSplitMethod.equal
    @State private var reimbursementRequired = true
    @State private var categoryID: UUID?
    @State private var accountID: UUID?
    @State private var note = ""
    @State private var message = ""

    private var members: [HouseholdMemberItem] {
        filterActiveProfile(allMembers).filter { !$0.archived }
    }

    private var categories: [CategoryItem] {
        filterActiveProfile(allCategories).filter { !$0.archived && !$0.isIncome }
    }

    private var accounts: [AccountItem] {
        filterActiveProfile(allAccounts).filter { !$0.archived }
    }

    private var selectedMembers: [HouseholdMemberItem] {
        members.filter { selectedMemberIDs.contains($0.id) }
    }

    private var amountMinor: Int64 {
        BudgetAmountField.minorUnits(
            fromMajorAmount: amountText,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private var canSave: Bool {
        !title.isBlankForHousehold && amountMinor > 0 && !selectedMembers.isEmpty
    }

    private var splitPreview: [HouseholdSplitPreview] {
        guard amountMinor > 0, !selectedMembers.isEmpty else { return [] }
        switch splitMethod {
        case .equal, .custom:
            let base = amountMinor / Int64(selectedMembers.count)
            let remainder = amountMinor - base * Int64(selectedMembers.count)
            return selectedMembers.enumerated().map { index, member in
                HouseholdSplitPreview(
                    member: member,
                    amountMinor: base + (index == 0 ? remainder : 0)
                )
            }
        case .singleMember:
            return selectedMembers.enumerated().map { index, member in
                HouseholdSplitPreview(member: member, amountMinor: index == 0 ? amountMinor : 0)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What was paid?") {
                    TextField("Example: Groceries, rent, school fee", text: $title)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $expenseDate, displayedComponents: .date)
                }

                Section("Who shares it?") {
                    Picker("Paid by", selection: $payerID) {
                        Text("No payer").tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.displayName).tag(Optional(member.id))
                        }
                    }

                    Picker("Split style", selection: $splitMethod) {
                        Text("Equal").tag(HouseholdSplitMethod.equal)
                        Text("One person").tag(HouseholdSplitMethod.singleMember)
                    }

                    Toggle("Track reimbursement", isOn: $reimbursementRequired)

                    if members.isEmpty {
                        Text("Add people before splitting an expense.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(members) { member in
                            Toggle(member.displayName, isOn: memberBinding(member.id))
                        }
                    }
                }

                Section("Split preview") {
                    if splitPreview.isEmpty {
                        Text("Enter an amount and choose people to see the split.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(splitPreview) { preview in
                            LabeledContent(
                                preview.member.displayName,
                                value: MoneyFormatter.string(
                                    minorUnits: preview.amountMinor,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                            )
                        }
                        Text("Saving creates a pending review item. Approve it to post the transaction.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    DisclosureGroup("Optional bookkeeping") {
                        Picker("Category", selection: $categoryID) {
                            Text("None").tag(UUID?.none)
                            ForEach(categories) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }
                        Picker("Account", selection: $accountID) {
                            Text("None").tag(UUID?.none)
                            ForEach(accounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        TextField("Note", text: $note, axis: .vertical)
                    }
                }

                if !message.isEmpty {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Split Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: configureDefaults)
        }
    }

    private func memberBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedMemberIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedMemberIDs.insert(id)
                } else {
                    selectedMemberIDs.remove(id)
                }
            }
        )
    }

    private func configureDefaults() {
        payerID = payerID ?? members.first?.id
        if selectedMemberIDs.isEmpty {
            selectedMemberIDs = Set(members.map(\.id))
        }
        categoryID = categoryID ?? categories.first?.id
        accountID = accountID ?? accounts.first?.id
    }

    private func save() {
        do {
            _ = try HouseholdRepository(modelContext: modelContext).createExpense(
                HouseholdExpenseDraft(
                    title: title,
                    amountMinor: amountMinor,
                    currencyCode: appState.selectedCurrencyCode,
                    expenseDate: expenseDate,
                    payer: payerID.flatMap { id in members.first { $0.id == id } },
                    members: selectedMembers,
                    splitMethod: splitMethod,
                    reimbursementRequired: reimbursementRequired,
                    category: categoryID.flatMap { id in categories.first { $0.id == id } },
                    account: accountID.flatMap { id in accounts.first { $0.id == id } },
                    receiptCapture: nil,
                    note: note,
                    customAmounts: [:]
                )
            )
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct HouseholdSplitPreview: Identifiable {
    let member: HouseholdMemberItem
    let amountMinor: Int64

    var id: UUID { member.id }
}

private struct HouseholdBillEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \HouseholdMemberItem.createdAt) private var allMembers: [HouseholdMemberItem]
    @Query(sort: \CategoryItem.sortOrder) private var allCategories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var allAccounts: [AccountItem]
    @State private var title = ""
    @State private var amountText = ""
    @State private var dueDate = Date()
    @State private var cadence = RecurringCadence.monthly
    @State private var payerID: UUID?
    @State private var categoryID: UUID?
    @State private var accountID: UUID?
    @State private var autoCreateApproval = false
    @State private var note = ""
    @State private var message = ""

    private var members: [HouseholdMemberItem] {
        filterActiveProfile(allMembers).filter { !$0.archived }
    }

    private var categories: [CategoryItem] {
        filterActiveProfile(allCategories).filter { !$0.archived && !$0.isIncome }
    }

    private var accounts: [AccountItem] {
        filterActiveProfile(allAccounts).filter { !$0.archived }
    }

    private var amountMinor: Int64 {
        BudgetAmountField.minorUnits(
            fromMajorAmount: amountText,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private var canSave: Bool {
        !title.isBlankForHousehold && amountMinor > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    TextField("Example: Rent, electricity, internet", text: $title)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    Picker("Repeats", selection: $cadence) {
                        ForEach(RecurringCadence.allCases) { cadence in
                            Text(cadence.title).tag(cadence)
                        }
                    }
                }

                Section("Owner") {
                    Picker("Paid by", selection: $payerID) {
                        Text("No payer").tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.displayName).tag(Optional(member.id))
                        }
                    }
                    Toggle("Create approval automatically", isOn: $autoCreateApproval)
                }

                Section {
                    DisclosureGroup("Optional bookkeeping") {
                        Picker("Category", selection: $categoryID) {
                            Text("None").tag(UUID?.none)
                            ForEach(categories) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }
                        Picker("Account", selection: $accountID) {
                            Text("None").tag(UUID?.none)
                            ForEach(accounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        TextField("Note", text: $note, axis: .vertical)
                    }
                }

                if !message.isEmpty {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Household Bill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                payerID = payerID ?? members.first?.id
                categoryID = categoryID ?? categories.first?.id
                accountID = accountID ?? accounts.first?.id
            }
        }
    }

    private func save() {
        do {
            _ = try HouseholdRepository(modelContext: modelContext).saveBill(
                title: title,
                amountMinor: amountMinor,
                currencyCode: appState.selectedCurrencyCode,
                dueDate: dueDate,
                cadence: cadence,
                payer: payerID.flatMap { id in members.first { $0.id == id } },
                category: categoryID.flatMap { id in categories.first { $0.id == id } },
                account: accountID.flatMap { id in accounts.first { $0.id == id } },
                autoCreateApproval: autoCreateApproval,
                note: note
            )
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

private extension String {
    var isBlankForHousehold: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
