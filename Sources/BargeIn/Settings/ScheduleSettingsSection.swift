import SwiftUI
import BargeInCore
import SceneSchedule

/// 日程 tab 的两张卡：订阅与前置。节奏就是日历本身，所以这里没有节奏卡。
struct ScheduleSettingsSection: View {
    let store: StateStore
    let model: SettingsModel
    let feeds: FeedService
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            subscriptionsCard
            leadCard
        }
    }

    // MARK: - 订阅

    private var subscriptionsCard: some View {
        SettingsCard(
            title: "订阅",
            footnote: summaryText,
            trailing: AnyView(refreshLink)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if store.subscriptions.isEmpty {
                    Text("还没有订阅。可以填一套 CalDAV 账号（钉钉、企业微信、iCloud），或贴一条日历地址。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(store.subscriptions) { subscription in
                        subscriptionBlock(subscription)
                    }
                }

                addButton
                if model.addingSubscription { addForm }

                Text("只读：Barge In 只做读取（GET / PROPFIND / REPORT），从不写回，也不上传任何内容。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryText: String? {
        guard !store.subscriptions.isEmpty else { return nil }
        let latest = store.subscriptions.compactMap(\.lastFetchedAt).max()
        let count = "\(store.subscriptions.count) 个来源"
        guard let latest else { return count }
        return "\(count) · \(agoText(latest))"
    }

    private var refreshLink: some View {
        Button {
            Task { await feeds.refreshAll(force: true) }
        } label: {
            Text("立即刷新")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.accentText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(feeds.isRefreshing)
        .accessibilityLabel("立即刷新所有订阅")
    }

    /// 一行订阅 + 它今天的事件列表。展开面板紧贴在这一行下方。
    private func subscriptionBlock(_ subscription: Subscription) -> some View {
        let events = store.events(for: subscription.id)
        return VStack(alignment: .leading, spacing: 0) {
            subscriptionRow(subscription, todayCount: events.count)
            if model.expandedSubscriptionID == subscription.id {
                todayPanel(events)
            }
        }
    }

    private func todayPanel(_ events: [EventOccurrence]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Theme.stroke)
                .frame(width: 1)
            VStack(alignment: .leading, spacing: 3) {
                if events.isEmpty {
                    Text("今天没有日程")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 3)
                } else {
                    // 每分钟重算一次"过去没有"：列表开着时不刷新的话，14:00 的会过了点还亮着。
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(events) { event in
                                todayLine(event, now: context.date)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 26)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
    }

    private func todayLine(_ event: EventOccurrence, now: Date) -> some View {
        // 已经过去的会降一档对比度：今天的安排一眼能分出"还没到的"和"已经开完的"。
        let isPast = event.start < now
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(ScheduleValues.startText(event.start, calendar: .current))
                .font(.system(size: 11.5, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isPast ? .tertiary : .secondary)
                .frame(width: 36, alignment: .leading)
            Text(event.title)
                .font(.system(size: 11.5))
                .foregroundStyle(isPast ? .secondary : .primary)
                .lineLimit(1)
            if let location = event.location, !location.isEmpty {
                Text(location)
                    .font(.system(size: 10.5))
                    .foregroundStyle(isPast ? .quaternary : .tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func subscriptionRow(_ subscription: Subscription, todayCount: Int) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(subscription.lastError == nil ? Theme.accent : Theme.warn)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(metaText(subscription))
                    .font(.system(size: 10.5))
                    .foregroundStyle(subscription.lastError == nil ? Color.secondary : Theme.warn)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                model.expandedSubscriptionID = model.expandedSubscriptionID == subscription.id
                    ? nil
                    : subscription.id
            } label: {
                Text("今日 \(todayCount) 场")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("查看 \(subscription.name) 的今日 \(todayCount) 场日程")

            Toggle("", isOn: Binding(
                get: { subscription.isEnabled },
                set: { enabled in
                    store.setSubscriptionEnabled(enabled, for: subscription.id)
                    onChanged()
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel("启用 \(subscription.name)")

            ConfirmDeleteButton(
                form: .quiet,
                label: "删除 \(subscription.name)",
                confirming: model.confirmingDelete == "sub:\(subscription.id.uuidString)",
                onArm: { model.confirmingDelete = "sub:\(subscription.id.uuidString)" }
            ) {
                model.confirmingDelete = nil
                delete(subscription)
            }
        }
        .padding(9)
        .cardChrome(radius: 10, fill: Color.primary.opacity(0.04))
    }

    private func metaText(_ subscription: Subscription) -> String {
        let kind = subscription.kind == .caldav
            ? "CalDAV · \(subscription.calendars.count) 本日历"
            : "日历地址"
        if let error = subscription.lastError {
            return "\(kind) · \(error.message)"
        }
        guard let fetched = subscription.lastFetchedAt else { return "\(kind) · 还没同步" }
        return "\(kind) · \(agoText(fetched))"
    }

    private func agoText(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "刚刚同步" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) 分钟前同步" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前同步" }
        return "\(hours / 24) 天前同步"
    }

    private var addButton: some View {
        Button {
            model.addingSubscription.toggle()
            if !model.addingSubscription { model.resetSubscriptionDraft() }
        } label: {
            Label(model.addingSubscription ? "收起" : "添加订阅", systemImage: model.addingSubscription ? "minus" : "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 添加订阅

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegmentedControl(
                labels: ["CalDAV 账户", "日历地址"],
                selected: model.subscriptionMode.rawValue
            ) { index in
                model.subscriptionMode = index == 0 ? .caldav : .ics
                model.connectError = nil
                model.discovered = []
                model.selectedCalendars = []
            }

            if model.subscriptionMode == .caldav {
                caldavFields
            } else {
                icsFields
            }

            if !model.discovered.isEmpty { calendarPicker }
            if let error = model.connectError { InlineWarning(text: error) }

            Text("钉钉：日历设置 → 同步 → 同步到其他日历 → 获取 CalDAV 账号 · 企业微信 caldav.wecom.work · 飞书 caldav.feishu.cn")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .cardChrome(fill: Color.primary.opacity(0.04))
    }

    private var caldavFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("服务器") {
                SettingTextField(placeholder: "https://calendar.dingtalk.com", text: draft(\.serverDraft))
            }
            HStack(spacing: 8) {
                field("账号") {
                    SettingTextField(placeholder: "u_xxx", text: draft(\.usernameDraft))
                }
                field("密码") {
                    SettingTextField(placeholder: "CalDAV 密码", text: draft(\.passwordDraft), secure: true)
                }
            }
            HStack(spacing: 8) {
                compactButton(model.isConnecting ? "连接中…" : "连接") {
                    connectCalDAV()
                }
                .disabled(model.isConnecting)
                if model.isConnecting {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var icsFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("日历地址") {
                SettingTextField(placeholder: "https://…/basic.ics", text: draft(\.urlDraft))
            }
            HStack(spacing: 8) {
                field("用户名（可选）") {
                    SettingTextField(placeholder: "", text: draft(\.usernameDraft))
                }
                field("密码（可选）") {
                    SettingTextField(placeholder: "", text: draft(\.passwordDraft), secure: true)
                }
            }
            HStack(spacing: 8) {
                compactButton(model.isConnecting ? "连接中…" : "连接并保存") {
                    connectICS()
                }
                .disabled(model.isConnecting)
                if model.isConnecting {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var calendarPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("发现 \(model.discovered.count) 本日历 · 选要提醒的")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(model.discovered, id: \.href) { calendar in
                Toggle(isOn: Binding(
                    get: { model.selectedCalendars.contains(calendar.href) },
                    set: { selected in
                        if selected {
                            model.selectedCalendars.insert(calendar.href)
                        } else {
                            model.selectedCalendars.remove(calendar.href)
                        }
                    }
                )) {
                    Text(calendar.displayName)
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }
            HStack(spacing: 8) {
                compactButton("保存") { saveCalDAV() }
                    .disabled(model.selectedCalendars.isEmpty)
                Button("取消") { model.resetSubscriptionDraft() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 动作

    private func connectCalDAV() {
        guard !model.isConnecting else { return }
        model.isConnecting = true
        model.connectError = nil
        model.discovered = []
        let server = model.serverDraft
        let username = model.usernameDraft
        let password = model.passwordDraft
        Task {
            defer { model.isConnecting = false }
            do {
                let (resolved, calendars) = try await feeds.discover(
                    serverText: server,
                    username: username,
                    password: password
                )
                model.serverDraft = resolved.absoluteString
                model.discovered = calendars
                model.selectedCalendars = Set([calendars.first?.href].compactMap { $0 })
            } catch {
                model.connectError = (error as? FeedError)?.message ?? "连接失败，检查服务器与账号"
            }
        }
    }

    private func saveCalDAV() {
        guard !model.isConnecting, let server = Subscription.normalize(model.serverDraft) else { return }
        let calendars = model.discovered.filter { model.selectedCalendars.contains($0.href) }
        guard !calendars.isEmpty else { return }
        model.isConnecting = true
        model.connectError = nil
        let username = model.usernameDraft
        let password = model.passwordDraft
        Task {
            defer { model.isConnecting = false }
            do {
                let subscription = try await feeds.finishCalDAV(
                    server: server,
                    username: username,
                    password: password,
                    name: server.host ?? "日历",
                    calendars: calendars
                )
                store.upsert(subscription)
                Keychain.setPassword(password, for: subscription.id)
                await feeds.refresh(subscription, force: true)
                model.resetSubscriptionDraft()
                onChanged()
            } catch {
                model.connectError = (error as? FeedError)?.message ?? "这台服务器没有可读的日历"
            }
        }
    }

    private func connectICS() {
        guard !model.isConnecting else { return }
        model.isConnecting = true
        model.connectError = nil
        let url = model.urlDraft
        let username = model.usernameDraft
        let password = model.passwordDraft
        Task {
            defer { model.isConnecting = false }
            do {
                let subscription = try await feeds.connectICS(
                    urlText: url,
                    username: username,
                    password: password
                )
                store.upsert(subscription)
                Keychain.setPassword(password, for: subscription.id)
                await feeds.refresh(subscription, force: true)
                model.resetSubscriptionDraft()
                onChanged()
            } catch {
                model.connectError = (error as? FeedError)?.message ?? "无法读取这条地址"
            }
        }
    }

    private func delete(_ subscription: Subscription) {
        if model.expandedSubscriptionID == subscription.id {
            model.expandedSubscriptionID = nil
        }
        store.removeSubscription(subscription.id)
        Keychain.deletePassword(for: subscription.id)
        feeds.forget(subscription.id)
        onChanged()
    }

    // MARK: - 前置

    private var leadCard: some View {
        SettingsCard(title: "前置") {
            SettingsRow(title: "事件开始前") {
                AmountStepper(value: store.leadMinutes, range: 1...60, step: 1, unit: "分钟") { minutes in
                    store.setLeadMinutes(minutes)
                    onChanged()
                }
            }
            Text("全天事件不提醒；已经开始超过 10 分钟的事件不再补提醒；重复事件按规则展开。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 小控件

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private struct SettingTextField: View {
        let placeholder: String
        @Binding var text: String
        var secure: Bool = false

        @FocusState private var focused: Bool

        var body: some View {
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .modifier(InputChrome(focused: focused))
            .focused($focused)
        }
    }

    private func draft(_ keyPath: ReferenceWritableKeyPath<SettingsModel, String>) -> Binding<String> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { model[keyPath: keyPath] = $0 }
        )
    }
}
