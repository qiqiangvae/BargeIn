import AppKit
import SwiftUI
import BargeInCore
import SceneSchedule

@MainActor
final class StatusItemController: NSObject {
    private let store: StateStore
    private let engine: ReminderEngine
    private let presence: Presence
    private let feeds: FeedService
    private let presenter = ReminderPresenter()
    private let updateNotice = UpdateNoticePresenter()
    private let updates: UpdateChecker
    private let settings = SettingsWindowController()
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    /// 当前正在呈现的那一条；完成 / 推迟 / 中断只作用于它。
    private var currentKey: ReminderKey?

    override init() {
        let store = StateStore()
        let presence = Presence()
        self.store = store
        self.presence = presence
        self.engine = ReminderEngine(store: store, presence: presence)
        self.feeds = FeedService(store: store)
        self.updates = UpdateChecker(store: store)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = BrandMark.menuBarImage()
            button.toolTip = "Barge In · 身体节律"
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: store, engine: engine) { [weak self] in
                guard let self else { return }
                popover.performClose(nil)
                showSettings()
            }
        )

        wireReminderActions()
        engine.onPendingChanged = { [weak self] in self?.presentNext() }
        // 人离开时收起提醒、作废队列；回到在场后重算，日程靠自己的窗口补，节奏等下一个点。
        presence.onBecameAbsent = { [weak self] in self?.wentAbsent() }
        presence.onBecamePresent = { [weak self] in self?.engine.systemChanged() }
        // 订阅拉回来新事件后立刻重算，不让一条五分钟后的会等到下一轮刷新。
        feeds.onEventsChanged = { [weak self] in self?.engine.feedsChanged() }
        feeds.start()
        // 自动检查更新：只问 GitHub 有没有新版本；通知走温柔卡，不开系统通知权限。
        updates.onFoundNewVersion = { [weak self] release in self?.offerUpdate(release) }
        updates.start()

        if !store.state.hasOnboarded {
            // 首屏只出现一次：开窗就记下。用户直接关窗、⌘Q、强退、不点「就用这个」，
            // 都不该让首屏下次再来一遍——那等于每次启动都从头开始。
            store.set(\.hasOnboarded, true)
            showSettings(onboarding: true)
        }

        if CommandLine.arguments.contains("--demo") {
            present(.sceneOnly(.water))
        }
        if CommandLine.arguments.contains("--demo-update") {
            // 开发期看更新卡长什么样：不检查、不发通告，点卡片照常落设置·通用。
            updateNotice.show(version: "0.5.0", current: updates.currentVersion ?? "0.4.4") { [weak self] in
                self?.showSettings(page: .app)
            }
        }
    }

    /// 队列里的每一条都走自己的场景：完成 / 推迟 / 中断只作用于它。
    private func wireReminderActions() {
        presenter.onComplete = { [weak self] in self?.completeCurrent() }
        presenter.onPostpone = { [weak self] in self?.postponeCurrent() }
        presenter.onInterrupt = { [weak self] in self?.interruptCurrent() }
        // 碎裂退场要播完坠落才关窗；队列里的下一条在那之后再出现。
        presenter.onDismissed = { [weak self] in self?.presentNext() }
    }

    private func completeCurrent() {
        guard let key = currentKey else { return }
        switch key.scene {
        case .water:
            store.drink()
        case .activity:
            store.completeActivity()
        case .schedule:
            if let event = key.event { store.completeSchedule(event) }
        case .alarm:
            if let event = key.event { store.finishAlarm(event) }
        }
        advance()
    }

    private func postponeCurrent() {
        guard let key = currentKey else { return }
        store.recordSkip(key.scene)
        engine.postpone(key, minutes: 5)
        advance()
    }

    private func interruptCurrent() {
        guard let key = currentKey else { return }
        store.recordSkip(key.scene)
        if key.scene == .alarm {
            if let event = key.event { store.finishAlarm(event) }
        } else if let event = key.event {
            store.markHandled(event)
        }
        advance()
    }

    /// 关掉当前这一条，队列里还有就立刻呈现下一条；最后一条才把前台还回去。
    private func advance() {
        let hasPending = engine.pendingCount > 0
        // dismiss 对没有退场动画的预设（温柔、大字墙，以及开了降低动态的碎裂）是同步的：
        // 它会立刻走 onDismissed → presentNext，把队列里的下一条弹出来并重新设置 currentKey。
        // 晚一步清就会把新的 currentKey 抹成 nil，新提醒的所有动作都变成空操作。
        currentKey = nil
        presenter.dismiss(reactivate: !hasPending)
        engine.reschedule()
        presentNext()
    }

    /// 人离开了：正在显示的提醒立刻收起、队列作废。不记跳过、不标记日程已处理。
    private func wentAbsent() {
        engine.abandonPending()
        guard presenter.isShowing else { return }
        // 人已经不在了：不播退场动画，立刻收起。
        presenter.dismiss(reactivate: false, animated: false)
        currentKey = nil
    }

    private func presentNext() {
        guard !presenter.isShowing, let key = engine.dequeue() else { return }
        // 队列里剩下的这一条如果是在人离开之后才被取出来的，直接丢，不弹给回来的自己。
        guard presence.isPresent else { return }
        present(key)
    }

    private func present(_ key: ReminderKey) {
        guard !presenter.isShowing else { return }
        currentKey = key
        let instance = store.activeInstance(for: key.scene)
        presenter.show(
            model: reminderModel(for: key, instance: instance),
            presentation: Catalog.presentation(for: instance)
        )
    }

    private func showSettings(onboarding: Bool = false, page: SettingsModel.Page? = nil) {
        settings.show(
            store: store,
            engine: engine,
            feeds: feeds,
            updates: updates,
            onboarding: onboarding,
            page: page,
            onPreview: { [weak self] scene, instance in
                self?.previewReminder(scene: scene, instance: instance)
            },
            onFinishOnboarding: { [weak self] in
                // 首次启动的最后一幕：窗口关掉、只剩菜单栏，紧接一次真实呈现。
                guard let self else { return }
                self.settings.close()
                self.previewReminder(scene: .water, instance: self.store.activeInstance(for: .water))
            }
        )
    }

    /// 自动检查发现新版本：每个版本只提醒一次；正在弹提醒或设置窗口开着时不叠一张卡。
    private func offerUpdate(_ release: UpdateChecker.Release) {
        guard store.state.checkForUpdates,
              updates.isSupported,
              store.state.lastNotifiedVersion != release.version,
              !presenter.isShowing,
              !settings.isVisible
        else { return }
        store.set(\.lastNotifiedVersion, release.version)
        updateNotice.show(
            version: release.version,
            current: updates.currentVersion ?? ""
        ) { [weak self] in
            self?.showSettings(page: .app)
        }
    }

    /// 设置里的预览：按这张卡自己的配置呈现，动作只关闭，不写进度、不记账、不动调度。
    private func previewReminder(scene: SceneID, instance: PresetInstance) {
        presenter.show(
            model: reminderModel(for: ReminderKey(scene: scene), instance: instance),
            presentation: Catalog.presentation(for: instance),
            preview: true
        )
    }

    private func reminderModel(for key: ReminderKey, instance: PresetInstance) -> ReminderModel {
        let descriptor = store.descriptor(key.scene)
        // 预览没有真实的那一条（日程事件 / 闹钟）：缺的变量用场景自己的样例值补，
        // 别让模板里的 {title} 原样露出来。真实提醒拿到的是当次的真实值，不会被样例盖住。
        var values = store.copyValues(for: key)
        if values.isEmpty { values = descriptor.sampleValues }
        var copy = ReminderCopy.make(instance: instance, scene: descriptor, values: values)

        if key.scene == .schedule,
           let eventKey = key.event,
           let event = store.event(for: eventKey),
           event.start <= Date() {
            // 推迟到会都开始了才再响：进度行回落成"已经开始"。
            copy.progress = "\(ScheduleValues.startText(event.start, calendar: .current)) 已经开始"
        }

        return ReminderModel(
            completionLabel: descriptor.completionLabel,
            completionSymbol: descriptor.completionSymbol,
            copy: copy,
            pendingCount: engine.pendingCount
        )
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            engine.reschedule()
            // 菜单栏点击不一定会激活 App；不激活则 popover 窗口拿不到 key，键盘事件全落在原 App 上。
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
