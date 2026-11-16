import AppKit
import SwiftUI
import BargeInCore
import SceneWater
import SceneActivity
import SceneAlarm
import SceneSchedule

/// `BargeIn --snapshot <dir>`：把几个界面离屏渲染成 PNG，用于开发期视觉检查。
/// 与 `--selftest`、`--demo` 同类，不参与正常启动路径。
@MainActor
enum DevSnapshot {
    static func run(directory: String) -> Int {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: "com.bargein.snapshot") ?? .standard
        defaults.removePersistentDomain(forName: "com.bargein.snapshot")
        let store = StateStore(defaults: defaults)
        let engine = ReminderEngine(store: store, presence: Presence())
        let feeds = FeedService(store: store)
        let updates = UpdateChecker(store: store, currentVersion: "0.4.3")
        store.set(\.water.consumedML, 1000)
        store.set(\.activity.doneToday, 2)
        engine.reschedule()

        func renderSettings(_ model: SettingsModel, _ name: String, dark: Bool = false) {
            let view = SettingsView(
                store: store, engine: engine, feeds: feeds, updates: updates, model: model,
                onPreview: { _, _ in }, onFinishOnboarding: {}
            )
            .background(Color(nsColor: .windowBackgroundColor))
            // 窗口高度跟着内容走，截图也按内容量一遍，别再用固定 720 把空白也框进去
            renderFitting(view, width: 640, name: name, in: dir, dark: dark)
        }

        let popover = PopoverView(store: store, engine: engine, onOpenSettings: {})
            .background(Color(nsColor: .windowBackgroundColor))
        renderPopover(popover, name: "popover.png", in: dir)
        renderPopover(popover, name: "popover-dark.png", in: dir, dark: true)

        store.set(\.pausedUntil, Date().addingTimeInterval(3600))
        let paused = PopoverView(store: store, engine: engine, onOpenSettings: {})
            .background(Color(nsColor: .windowBackgroundColor))
        renderPopover(paused, name: "popover-paused.png", in: dir)
        store.set(\.pausedUntil, nil)

        store.set(\.water.consumedML, store.state.water.targetML)
        let completed = PopoverView(store: store, engine: engine, onOpenSettings: {})
            .background(Color(nsColor: .windowBackgroundColor))
        renderPopover(completed, name: "popover-completed.png", in: dir)
        store.set(\.water.consumedML, 1000)

        let settingsModel = SettingsModel(store: store, onboarding: false)
        renderSettings(settingsModel, "settings.png")
        renderSettings(settingsModel, "settings-dark.png", dark: true)

        // 版本卡：同一个页面按检查的生命周期换文案，五种状态各截一张。
        let release = UpdateChecker.Release(
            version: "0.5.0",
            downloadURL: URL(string: "https://example.com/Barge-In-0.5.0-macos-arm64.zip")!,
            pageURL: URL(string: "https://github.com/qiqiangvae/BargeIn/releases/tag/v0.5.0")!,
            summary: "自动更新检查：有新版时用温柔卡提醒"
        )
        updates.setStatusForSnapshot(.available(release))
        renderSettings(SettingsModel(store: store, onboarding: false, page: .app), "settings-app.png")
        updates.setStatusForSnapshot(.downloading(version: "0.5.0", received: 872_000, total: 2_081_617))
        renderSettings(SettingsModel(store: store, onboarding: false, page: .app), "settings-app-downloading.png")
        updates.setStatusForSnapshot(.upToDate)
        renderSettings(SettingsModel(store: store, onboarding: false, page: .app), "settings-app-current.png")
        updates.setStatusForSnapshot(.failed("连不上 GitHub，检查网络后再试"))
        renderSettings(SettingsModel(store: store, onboarding: false, page: .app), "settings-app-failed.png")
        updates.setStatusForSnapshot(.available(release))
        renderSettings(
            SettingsModel(store: store, onboarding: false, selectedScene: .activity),
            "settings-activity.png"
        )
        let alarmModel = SettingsModel(store: store, onboarding: false, selectedScene: .alarm)
        store.addAlarm(Alarm(title: "点外卖", time: TimeOfDay(hour: 11, minute: 30)))
        store.addAlarm(Alarm(
            title: "交周报",
            time: TimeOfDay(hour: 16, minute: 0),
            recurrence: .once(AlarmPolicy.clamp(
                Date().addingTimeInterval(3 * 86_400),
                now: Date(),
                calendar: .current
            ))
        ))
        store.addAlarm(Alarm(title: "去健身", time: TimeOfDay(hour: 19, minute: 30)))
        renderSettings(alarmModel, "settings-alarm.png")
        let alarmEditModel = SettingsModel(store: store, onboarding: false, selectedScene: .alarm)
        if let first = store.alarms.first {
            alarmEditModel.editingAlarmID = first.id
            alarmEditModel.alarmTitleDraft = first.title
        }
        renderSettings(alarmEditModel, "settings-alarm-editing.png")
        store.setSceneEnabled(true, for: .alarm)
        let alarmPopover = PopoverView(store: store, engine: engine, onOpenSettings: {})
            .background(Color(nsColor: .windowBackgroundColor))
        renderPopover(alarmPopover, name: "popover-alarm.png", in: dir)
        store.setSceneEnabled(false, for: .alarm)

        let renameTarget = store.duplicate(store.activeInstance(for: .water).id, in: .water)
        let editingModel = SettingsModel(store: store, onboarding: false)
        editingModel.editingID = renameTarget
        editingModel.renameDraft = store.config(.water).instances.first { $0.id == renameTarget }?.name ?? ""
        renderSettings(editingModel, "settings-editing.png")

        // 多张卡：所有卡都排在首页网格里，不再有「全部预设」二级页。
        store.duplicate(store.activeInstance(for: .water).id, in: .water)
        store.duplicate(store.activeInstance(for: .water).id, in: .water)
        renderSettings(SettingsModel(store: store, onboarding: false), "settings-many-cards.png")

        // 编辑一张副本：动作行、编辑面板都跟着"使用中"的那张卡。
        let copyTarget = store.config(.water).instances[3]
        store.activate(copyTarget.id, in: .water)
        let copyEditingModel = SettingsModel(store: store, onboarding: false)
        copyEditingModel.editingID = copyTarget.id
        copyEditingModel.renameDraft = copyTarget.name
        renderSettings(copyEditingModel, "settings-copy-editing.png")

        let onboardingDefaults = UserDefaults(suiteName: "com.bargein.snapshot.onboarding") ?? .standard
        onboardingDefaults.removePersistentDomain(forName: "com.bargein.snapshot.onboarding")
        let onboardingStore = StateStore(defaults: onboardingDefaults)
        let onboardingEngine = ReminderEngine(store: onboardingStore, presence: Presence())
        let onboardingFeeds = FeedService(store: onboardingStore)
        let onboardingUpdates = UpdateChecker(store: onboardingStore, currentVersion: "0.4.3")
        let onboarding = SettingsView(
            store: onboardingStore, engine: onboardingEngine, feeds: onboardingFeeds,
            updates: onboardingUpdates,
            model: SettingsModel(store: onboardingStore, onboarding: true),
            onPreview: { _, _ in }, onFinishOnboarding: {}
        )
        .background(Color(nsColor: .windowBackgroundColor))
        renderWindow(onboarding, width: 640, height: 720, name: "onboarding.png", in: dir)
        renderWindow(onboarding, width: 640, height: 720, name: "onboarding-dark.png", in: dir, dark: true)

        let timePanel = TimePickerPanel(label: "开始", time: TimeOfDay(hour: 9, minute: 30), onChange: { _ in })
            .frame(width: 236, height: 252)
            .background(Color(nsColor: .windowBackgroundColor))
        renderWindow(timePanel, width: 236, height: 252, name: "time-picker.png", in: dir)
        renderWindow(timePanel, width: 236, height: 252, name: "time-picker-dark.png", in: dir, dark: true)

        let oddMinutePanel = TimePickerPanel(label: "开始", time: TimeOfDay(hour: 9, minute: 37), onChange: { _ in })
            .frame(width: 236, height: 252)
            .background(Color(nsColor: .windowBackgroundColor))
        renderWindow(oddMinutePanel, width: 236, height: 252, name: "time-picker-odd.png", in: dir)

        store.setTrigger(
            .rhythm(.timesOfDay([TimeOfDay(hour: 9, minute: 30), TimeOfDay(hour: 20, minute: 0)])),
            for: .water
        )
        renderSettings(SettingsModel(store: store, onboarding: false), "settings-rhythm.png")
        store.setTrigger(.rhythm(.interval(minutes: 60)), for: .water)
        engine.reschedule()

        // 日程：一条假的钉钉订阅，让日程 tab 与 popover 行都有内容。
        let scheduleSubscription = Subscription(
            kind: .caldav,
            name: "钉钉 · 工作日历",
            url: URL(string: "https://calendar.dingtalk.com")!,
            username: "u_example****",
            calendars: [
                CalendarRef(href: "/dav/u_example/primary/", displayName: "主日历"),
                CalendarRef(href: "/dav/u_example/work/", displayName: "工作日历"),
            ],
            lastFetchedAt: Date().addingTimeInterval(-180)
        )
        store.upsert(scheduleSubscription)
        store.setSceneEnabled(true, for: .schedule)
        let soon = Date().addingTimeInterval(11 * 60)
        let calendar = Calendar.current
        let today = Date()
        func todayAt(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        store.setEvents([
            EventOccurrence(
                subscriptionID: scheduleSubscription.id,
                uid: "mock-morning",
                start: todayAt(9, 30),
                title: "晨会",
                location: "会议室 A"
            ),
            EventOccurrence(
                subscriptionID: scheduleSubscription.id,
                uid: "mock-review",
                start: soon,
                title: "Q4 产品评审",
                location: "会议室 A"
            ),
            EventOccurrence(
                subscriptionID: scheduleSubscription.id,
                uid: "mock-design",
                start: todayAt(14, 0),
                title: "和设计过一版原型"
            ),
            EventOccurrence(
                subscriptionID: scheduleSubscription.id,
                uid: "mock-weekly",
                start: todayAt(16, 30),
                title: "周会",
                location: "飞书会议"
            ),
        ])
        engine.reschedule()

        let scheduleModel = SettingsModel(store: store, onboarding: false, selectedScene: .schedule)
        renderSettings(scheduleModel, "settings-schedule.png")
        renderSettings(scheduleModel, "settings-schedule-dark.png", dark: true)

        let addingModel = SettingsModel(store: store, onboarding: false, selectedScene: .schedule)
        addingModel.addingSubscription = true
        addingModel.discovered = [
            CalendarRef(href: "/dav/u_example/primary/", displayName: "主日历"),
            CalendarRef(href: "/dav/u_example/work/", displayName: "工作日历"),
            CalendarRef(href: "/dav/u_example/holiday/", displayName: "订阅：节假日"),
        ]
        addingModel.selectedCalendars = ["/dav/u_example/primary/", "/dav/u_example/work/"]
        renderSettings(addingModel, "settings-schedule-add.png")

        let todayModel = SettingsModel(store: store, onboarding: false, selectedScene: .schedule)
        todayModel.expandedSubscriptionID = scheduleSubscription.id
        renderSettings(todayModel, "settings-schedule-today.png")
        renderSettings(todayModel, "settings-schedule-today-dark.png", dark: true)

        let schedulePopover = PopoverView(store: store, engine: engine, onOpenSettings: {})
            .background(Color(nsColor: .windowBackgroundColor))
        renderPopover(schedulePopover, name: "popover-schedule.png", in: dir)

        let water = WaterScene.descriptor
        let activity = ActivityScene.descriptor
        let wallInstance = store.config(.water).instances.first { $0.preset == .wall }!
        let gentleInstance = store.config(.water).instances.first { $0.preset == .gentle }!
        let activityWall = store.config(.activity).instances.first { $0.preset == .wall }!

        func reminderModel(
            _ scene: SceneDescriptor,
            _ instance: PresetInstance,
            pending: Int = 0
        ) -> ReminderModel {
            ReminderModel(
                completionLabel: scene.completionLabel,
                completionSymbol: scene.completionSymbol,
                copy: ReminderCopy.make(
                    instance: instance,
                    scene: scene,
                    values: store.copyValues(for: scene.id)
                ),
                pendingCount: pending
            )
        }

        func renderOverlay(
            _ model: ReminderModel,
            _ instance: PresetInstance,
            name: String,
            unlockDelay: TimeInterval = 0,
            preview: Bool = false,
            width: CGFloat = 1440,
            height: CGFloat = 900,
            settle: TimeInterval = 1.5
        ) {
            let state = OverlayState(dismissDelay: unlockDelay)
            state.start()
            let view = ReminderOverlay(
                model: model,
                presentation: Catalog.presentation(for: instance),
                state: state,
                isPreview: preview,
                onComplete: {}, onPostpone: {}, onInterrupt: {}
            )
            // 全屏层自带深墨底；卡片截图需要一层窗口底色，否则圆角外是透明的。
            .background(width < 500 ? Color(nsColor: .windowBackgroundColor) : Color.clear)
            renderWindow(view, width: width, height: height, name: name, in: dir, dark: width >= 500, settle: settle)
        }

        let waterModel = reminderModel(water, wallInstance)
        renderOverlay(waterModel, wallInstance, name: "overlay.png")
        renderOverlay(reminderModel(water, wallInstance, pending: 1), wallInstance, name: "overlay-pending.png")
        renderOverlay(waterModel, gentleInstance, name: "card.png", width: 360, height: 260)
        let updateCard = UpdateNoticeCard(version: "0.5.0", current: "0.4.2", onOpen: {}, onClose: {})
            .background(Color(nsColor: .windowBackgroundColor))
        renderWindow(updateCard, width: 360, height: 260, name: "update-notice.png", in: dir)
        renderWindow(updateCard, width: 360, height: 260, name: "update-notice-dark.png", in: dir, dark: true)
        let strictWall = PresetInstance(preset: .wall, name: "大字墙", intensity: .strict, builtIn: true)
        renderOverlay(
            reminderModel(water, strictWall),
            strictWall,
            name: "overlay-locked.png",
            unlockDelay: 5,
            settle: 2.2
        )
        renderOverlay(waterModel, wallInstance, name: "overlay-preview.png", preview: true)
        renderOverlay(reminderModel(activity, activityWall), activityWall, name: "overlay-activity.png")

        // 闹钟：大字词是这条的内容，进度行是时刻。
        if let firstAlarm = store.alarms.first {
            let alarmDescriptor = store.descriptor(.alarm)
            let alarmWall = store.activeInstance(for: .alarm)
            let at = firstAlarm.time.date(on: Date(), calendar: .current)
            let key = ReminderKey(scene: .alarm, event: EventKey(uid: firstAlarm.id.uuidString, start: at))
            let model = ReminderModel(
                completionLabel: alarmDescriptor.completionLabel,
                completionSymbol: alarmDescriptor.completionSymbol,
                copy: ReminderCopy.make(
                    instance: alarmWall,
                    scene: alarmDescriptor,
                    values: store.copyValues(for: key)
                ),
                pendingCount: 0
            )
            renderOverlay(model, alarmWall, name: "overlay-alarm.png")
        }

        // 碎裂：裂满停住（等用户处理），以及确认后整片坠落的一帧。
        let shatterInstance = store.config(.water).instances.first { $0.preset == .shatter } ?? Catalog.makeInstances(for: .water)[2]
        let shatterModel = ReminderModel(
            completionLabel: water.completionLabel,
            completionSymbol: water.completionSymbol,
            copy: ReminderCopy.make(
                instance: shatterInstance,
                scene: water,
                values: store.copyValues(for: .water)
            ),
            pendingCount: 0
        )
        let shatterAnimator = ShatterAnimator(seed: 20261113, reduceMotion: false)
        let shatterState = OverlayState(dismissDelay: 0)
        shatterState.start()
        let shatterOverlay = ReminderOverlay(
            model: shatterModel,
            presentation: Catalog.presentation(for: shatterInstance),
            state: shatterState,
            animator: shatterAnimator,
            onComplete: {}, onPostpone: {}, onInterrupt: {}
        )
        renderWindow(shatterOverlay, width: 1440, height: 900, name: "overlay-shatter.png", in: dir, dark: true, settle: 2.8)

        // 等用户处理时，几块小碎片还在慢慢往下掉。
        let shedAnimator = ShatterAnimator(seed: 20261113, reduceMotion: false)
        let shedState = OverlayState(dismissDelay: 0)
        shedState.start()
        let shedOverlay = ReminderOverlay(
            model: shatterModel,
            presentation: Catalog.presentation(for: shatterInstance),
            state: shedState,
            animator: shedAnimator,
            onComplete: {}, onPostpone: {}, onInterrupt: {}
        )
        renderWindow(shedOverlay, width: 1440, height: 900, name: "overlay-shatter-shed.png", in: dir, dark: true, settle: 5.4)

        let cracksAnimator = ShatterAnimator(seed: 20261113, reduceMotion: false)
        let cracksState = OverlayState(dismissDelay: 0)
        cracksState.start()
        let cracksOverlay = ReminderOverlay(
            model: shatterModel,
            presentation: Catalog.presentation(for: shatterInstance),
            state: cracksState,
            animator: cracksAnimator,
            onComplete: {}, onPostpone: {}, onInterrupt: {}
        )
        renderWindow(cracksOverlay, width: 1440, height: 900, name: "overlay-shatter-cracks.png", in: dir, dark: true, settle: 1.35)

        let fallingAnimator = ShatterAnimator(seed: 20261113, reduceMotion: false)
        let fallingState = OverlayState(dismissDelay: 0)
        fallingState.start()
        let fallingOverlay = ReminderOverlay(
            model: shatterModel,
            presentation: Catalog.presentation(for: shatterInstance),
            state: fallingState,
            animator: fallingAnimator,
            onComplete: {}, onPostpone: {}, onInterrupt: {}
        )
        fallingAnimator.beginExit()
        renderWindow(fallingOverlay, width: 1440, height: 900, name: "overlay-shatter-fall.png", in: dir, dark: true, settle: 0.8)

        print("snapshot: wrote \(dir.path)")
        return 0
    }

    /// popover 的高度由内容决定：先量一次，再按量到的尺寸渲染，README 截图才不会被撑大。
    private static func renderPopover<V: View>(
        _ view: V,
        name: String,
        in dir: URL,
        dark: Bool = false
    ) {
        let content = view.environment(\.colorScheme, dark ? .dark : .light)
        let measuring = NSHostingView(rootView: content)
        measuring.layoutSubtreeIfNeeded()
        let height = measuring.fittingSize.height
        renderWindow(
            view,
            width: 304,
            height: height > 120 ? height : 520,
            name: name,
            in: dir,
            dark: dark
        )
    }

    /// 按视图自身的高度渲染：设置窗口的内容高矮随页面走，固定高度会框进空白。
    private static func renderFitting<V: View>(
        _ view: V,
        width: CGFloat,
        minHeight: CGFloat = 420,
        maxHeight: CGFloat = 900,
        name: String,
        in dir: URL,
        dark: Bool = false
    ) {
        let content = view
            .frame(width: width)
            .environment(\.colorScheme, dark ? .dark : .light)
        let measuring = NSHostingView(rootView: content)
        measuring.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        measuring.layoutSubtreeIfNeeded()
        let fit = measuring.fittingSize
        renderWindow(
            view,
            width: width,
            height: min(max(fit.height, minHeight), maxHeight),
            name: name,
            in: dir,
            dark: dark
        )
    }

    private static func renderWindow<V: View>(
        _ view: V,
        width: CGFloat,
        height: CGFloat,
        name: String,
        in dir: URL,
        dark: Bool = false,
        settle: TimeInterval = 0.35,
        scrollToY: CGFloat? = nil
    ) {
        let content = view
            .frame(width: width, height: height)
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: content)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = hosting
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        if let scrollToY, let scrollView = findScrollView(in: hosting) {
            let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(scrollToY, maxY)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("snapshot: failed \(name)")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.close()
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: dir.appendingPathComponent(name))
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }
}
