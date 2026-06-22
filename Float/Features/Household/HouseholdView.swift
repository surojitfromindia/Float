import SwiftData
import SwiftUI

struct HouseholdView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \HouseholdMemberItem.createdAt) private var allMembers: [HouseholdMemberItem]
    @Query(sort: \HouseholdExpenseItem.createdAt, order: .reverse) private var allExpenses: [HouseholdExpenseItem]
    @Query(sort: \HouseholdBillItem.dueDate) private var allBills: [HouseholdBillItem]
    @Query(sort: \HouseholdActivityItem.createdAt, order: .reverse) private var allActivities: [HouseholdActivityItem]
    @State private var memberToEdit: HouseholdMemberItem?
    @State private var isAddingMember = false
    @State private var isAddingExpense = false
    @State private var isAddingBill = false
    @State private var message = ""

    private var members: [HouseholdMemberItem] {
        filterActiveProfile(allMembers).filter { !$0.archived }
    }

    private var expenses: [HouseholdExpenseItem] {
        filterActiveProfile(allExpenses)
    }

    private var bills: [HouseholdBillItem] {
        filterActiveProfile(allBills).filter(\.active)
    }

    private var activities: [HouseholdActivityItem] {
        Array(filterActiveProfile(allActivities).prefix(8))
    }

    private var pendingExpenses: [HouseholdExpenseItem] {
        expenses.filter { $0.approvalStatus == .pending }
    }

    private var approvedThisMonth: [HouseholdExpenseItem] {
        let calendar = Calendar.current
        return expenses.filter {
            $0.approvalStatus == .approved
                && calendar.isDate($0.expenseDate, equalTo: Date(), toGranularity: .month)
        }
    }

    private var dueSoonBills: [HouseholdBillItem] {
        bills.filter(\.isDueSoon)
    }

    private var monthSpendMinor: Int64 {
        approvedThisMonth.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var pendingAmountMinor: Int64 {
        pendingExpenses.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var reimbursementDueMinor: Int64 {
        expenses.reduce(Int64(0)) { $0 + $1.outstandingReimbursementMinor }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                hero
                metricsGrid
                approvalInbox
                membersSection
                billsSection
                activitySection
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .floatBackground()
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $isAddingMember) {
            HouseholdMemberEditorSheet(member: nil)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $memberToEdit) { member in
            HouseholdMemberEditorSheet(member: member)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isAddingExpense) {
            HouseholdExpenseEditorSheet()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isAddingBill) {
            HouseholdBillEditorSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Household OS")
                        .font(.largeTitle.bold())
                    Text("Shared approvals, member allowances, bills, and reimbursements in one place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                FloatIconBadge(
                    icon: "house.and.flag.fill",
                    tint: appState.themePalette.accent,
                    size: 48
                )
            }

            HStack(spacing: 10) {
                Button {
                    isAddingExpense = true
                } label: {
                    Label("Add shared expense", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    Button("Add member") { isAddingMember = true }
                    Button("Add bill") { isAddingBill = true }
                    Button("Monthly closeout") { createCloseout() }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .padding(.top, 28)
        .floatGlassSurface(
            cornerRadius: FloatTheme.radius,
            material: .ultraThinMaterial,
            tint: appState.themePalette.accent,
            strokeOpacity: 0.08,
            shadowOpacity: 0.08,
            shadowRadius: 24,
            shadowY: 14
        )
        .padding(.horizontal, -20)
        .padding(.top, -20)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SummaryMetricTile(
                title: "Pending",
                value: money(pendingAmountMinor),
                captionText: AppLocalization.format("%lld approvals", Int64(pendingExpenses.count)),
                icon: "checklist",
                tint: appState.themePalette.caution
            )
            SummaryMetricTile(
                title: "This month",
                value: money(monthSpendMinor),
                captionText: AppLocalization.format("%lld approved", Int64(approvedThisMonth.count)),
                icon: "calendar",
                tint: appState.themePalette.accent
            )
            SummaryMetricTile(
                title: "Reimburse",
                value: money(reimbursementDueMinor),
                caption: "Open member balances",
                icon: "arrow.left.arrow.right.circle.fill",
                tint: Color(hex: "#0A6FAE")
            )
            SummaryMetricTile(
                title: "Bills",
                value: "\(dueSoonBills.count)",
                caption: "Due in 7 days",
                icon: "doc.text.fill",
                tint: Color(hex: "#8A6DD7")
            )
        }
    }

    private var approvalInbox: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Shared Approval Inbox",
                actionTitle: "Add",
                action: { isAddingExpense = true }
            )

            if pendingExpenses.isEmpty {
                GlassCard {
                    EmptyStateView(
                        icon: "checkmark.seal.fill",
                        title: "Nothing waiting",
                        message: "Shared expenses that need payer, member, or reimbursement review will appear here."
                    )
                }
            } else {
                ForEach(pendingExpenses) { expense in
                    HouseholdExpenseRow(
                        expense: expense,
                        currencyCode: appState.selectedCurrencyCode,
                        onApprove: { approve(expense) },
                        onReject: { reject(expense) }
                    )
                }
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Members",
                actionTitle: "Add",
                action: { isAddingMember = true }
            )
            if members.isEmpty {
                GlassCard {
                    EmptyStateView(
                        icon: "person.3.fill",
                        title: "No household members",
                        message: "Add family members to approve shared expenses, track allowances, and create reimbursements."
                    )
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(members) { member in
                            Button {
                                memberToEdit = member
                            } label: {
                                HouseholdMemberCard(
                                    member: member,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var billsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Bill Command Center",
                actionTitle: "Add",
                action: { isAddingBill = true }
            )
            if bills.isEmpty {
                GlassCard {
                    EmptyStateView(
                        icon: "doc.text.magnifyingglass",
                        title: "No shared bills",
                        message: "Add rent, utilities, subscriptions, or school fees that the household tracks together."
                    )
                }
            } else {
                ForEach(bills.prefix(5)) { bill in
                    HouseholdBillRow(bill: bill, currencyCode: appState.selectedCurrencyCode)
                }
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Household Activity")
            if activities.isEmpty {
                GlassCard {
                    EmptyStateView(
                        icon: "clock.arrow.circlepath",
                        title: "No household activity",
                        message: "Approvals, bills, and closeouts will build a shared audit trail here."
                    )
                }
            } else {
                ForEach(activities) { activity in
                    HouseholdActivityRow(activity: activity, currencyCode: appState.selectedCurrencyCode)
                }
            }
        }
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

private struct HouseholdExpenseRow: View {
    let expense: HouseholdExpenseItem
    let currencyCode: String
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    FloatIconBadge(
                        icon: expense.category?.iconKey ?? "cart.fill",
                        tint: Color(hex: expense.category?.colorHex ?? "#0E7C7B")
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(expense.title)
                            .font(.headline)
                        Text(AppLocalization.format(
                            "%@ paid - %@",
                            expense.payerName,
                            expense.beneficiarySummary
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
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

private struct HouseholdMemberCard: View {
    let member: HouseholdMemberItem
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(member.displayInitials)
                    .font(.headline)
                    .foregroundStyle(Color(hex: member.colorHex))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: member.colorHex).opacity(0.16), in: Circle())
                Spacer()
                Text(member.role.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Monthly allowance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(MoneyFormatter.string(minorUnits: member.monthlyAllowanceMinor, currencyCode: currencyCode))
                    .moneyStyle(size: 18, weight: .bold)
            }
        }
        .frame(width: 180, alignment: .leading)
        .padding(16)
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
                    "%@ - %@",
                    bill.payer?.displayName ?? String(localized: "No payer"),
                    bill.dueDate.formatted(date: .abbreviated, time: .omitted)
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MoneyFormatter.string(minorUnits: bill.amountMinor, currencyCode: currencyCode))
                .moneyStyle(size: 15, weight: .semibold)
        }
        .padding(16)
        .floatGlassSurface(cornerRadius: FloatTheme.tileRadius)
    }
}

private struct HouseholdActivityRow: View {
    let activity: HouseholdActivityItem
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: icon, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(.subheadline.weight(.semibold))
                Text(activity.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let amount = activity.amountMinor {
                Text(MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode))
                    .moneyStyle(size: 13, weight: .semibold)
            }
        }
        .padding(14)
        .floatGlassSurface(cornerRadius: FloatTheme.tileRadius)
    }

    private var icon: String {
        switch activity.kind {
        case .expenseCreated: "plus.circle.fill"
        case .expenseApproved: "checkmark.seal.fill"
        case .expenseRejected: "xmark.circle.fill"
        case .billAdded: "doc.text.fill"
        case .allowanceChanged: "person.crop.circle.badge.checkmark"
        case .closeoutCreated: "arrow.left.arrow.right.circle.fill"
        }
    }

    private var tint: Color {
        switch activity.kind {
        case .expenseRejected: Color(hex: "#B4613B")
        case .billAdded: Color(hex: "#8A6DD7")
        case .closeoutCreated: Color(hex: "#0A6FAE")
        default: Color(hex: "#0E7C7B")
        }
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
                Section("Member") {
                    TextField("Name", text: $name)
                    Picker("Role", selection: $role) {
                        ForEach(HouseholdMemberRole.allCases) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    TextField("Monthly allowance", text: $allowanceText)
                        .keyboardType(.decimalPad)
                    TextField("Color hex", text: $colorHex)
                        .textInputAutocapitalization(.characters)
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    TextField("Title", text: $title)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $expenseDate, displayedComponents: .date)
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
                }

                Section("Household") {
                    Picker("Paid by", selection: $payerID) {
                        Text("No payer").tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.displayName).tag(Optional(member.id))
                        }
                    }
                    Picker("Split", selection: $splitMethod) {
                        ForEach(HouseholdSplitMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    Toggle("Needs reimbursement", isOn: $reimbursementRequired)
                    ForEach(members) { member in
                        Toggle(
                            member.displayName,
                            isOn: memberBinding(member.id)
                        )
                    }
                }

                Section("Note") {
                    TextField("Optional note", text: $note, axis: .vertical)
                }

                if !message.isEmpty {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Shared Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
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
        if payerID == nil {
            payerID = members.first?.id
        }
        if selectedMemberIDs.isEmpty {
            selectedMemberIDs = Set(members.prefix(2).map(\.id))
        }
        categoryID = categoryID ?? categories.first?.id
        accountID = accountID ?? accounts.first?.id
    }

    private func save() {
        let selectedMembers = members.filter { selectedMemberIDs.contains($0.id) }
        do {
            _ = try HouseholdRepository(modelContext: modelContext).createExpense(
                HouseholdExpenseDraft(
                    title: title,
                    amountMinor: BudgetAmountField.minorUnits(
                        fromMajorAmount: amountText,
                        currencyCode: appState.selectedCurrencyCode
                    ),
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    TextField("Title", text: $title)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    Picker("Repeats", selection: $cadence) {
                        ForEach(RecurringCadence.allCases) { cadence in
                            Text(cadence.title).tag(cadence)
                        }
                    }
                    Toggle("Create approval automatically", isOn: $autoCreateApproval)
                }

                Section("Ownership") {
                    Picker("Paid by", selection: $payerID) {
                        Text("No payer").tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.displayName).tag(Optional(member.id))
                        }
                    }
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
                    TextField("Optional note", text: $note, axis: .vertical)
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
                amountMinor: BudgetAmountField.minorUnits(
                    fromMajorAmount: amountText,
                    currencyCode: appState.selectedCurrencyCode
                ),
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
