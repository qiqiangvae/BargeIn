import Foundation
import BargeInCore
import SceneWater
import SceneActivity
import SceneSchedule
import SceneAlarm

/// `BargeIn --selftest`：不依赖 UI 的可运行检查，覆盖持久化、按场景调度、账本、队列与文案。
@MainActor
enum SelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ passed: Bool) {
            if !passed { failures.append(name) }
        }

        persistence(check)
        factory(check)
        rhythmSwitch(check)
        scheduling(check)
        behavior(check)
        instances(check)
        scenes(check)
        copyResolution(check)
        queue(check)
        calendarParsing(check)
        calendarScheduling(check)
        calendarStore(check)
        alarms(check)
        legacyData(check)
        updates(check)
        escapeCancel(check)
        escapeLayers(check)
        doubleReturnConfirm(check)
        shatterTimeline(check)

        if failures.isEmpty {
            print("selftest: PASS")
            return true
        }
        for failure in failures { print("selftest: FAIL - \(failure)") }
        return false
    }

    private static func activePreset(_ config: SceneConfig) -> Preset? {
        config.instances.first { $0.id == config.activeInstanceID }?.preset
    }

    // MARK: - 持久化

    private static func persistence(_ check: (String, Bool) -> Void) {
        let suiteName = "com.bargein.selftest"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            check("selftest suite available", false)
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let first = StateStore(defaults: defaults)
        first.drink()
        check(
            "默认按单杯量记录",
            first.state.water.consumedML == first.state.water.cupML && first.state.water.cupML > 0
        )

        first.recordSkip(.water)
        first.clearWaterProgress()
        check(
            "清空今日进度只归零毫升、不动账本",
            first.state.water.consumedML == 0 && first.config(.water).skipsToday == 1
        )
        first.drink()

        first.completeActivity()
        check("活动完成记一次", first.state.activity.doneToday == 1)

        let reloaded = StateStore(defaults: defaults)
        check(
            "persist round-trip",
            reloaded.state.water.consumedML == first.state.water.consumedML
                && reloaded.state.activity.doneToday == first.state.activity.doneToday
        )

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 出厂

    private static func factory(_ check: (String, Bool) -> Void) {
        let state = AppState()
        check("出厂两个场景都启用", state.waterConfig.isEnabled && state.activityConfig.isEnabled)
        check(
            "每个场景出厂三张卡",
            state.waterConfig.instances.count == 3 && state.activityConfig.instances.count == 3
        )
        check(
            "出厂第三张是碎裂",
            state.waterConfig.instances.last?.preset == .shatter
                && state.waterConfig.instances.last?.builtIn == true
        )
        check(
            "每个场景默认激活大字墙·标准",
            activePreset(state.waterConfig) == .wall
                && state.waterConfig.instances.first { $0.id == state.waterConfig.activeInstanceID }?.intensity == .standard
                && activePreset(state.activityConfig) == .wall
        )
        check(
            "每张出厂卡都来自该场景支持的预设",
            SceneID.allCases.allSatisfy { scene in
                state.config(scene).instances.allSatisfy { instance in
                    Catalog.theme(for: instance.preset).scenes.contains(scene)
                }
            }
        )
        check(
            "预设默认适用于所有场景",
            Catalog.theme(for: .wall).scenes == Set(SceneID.allCases)
        )
        check(
            "场景不支持的预设连同副本一起清掉",
            {
                let onlyWall = PresetInstance(preset: .wall, name: "大字墙", intensity: .standard, builtIn: true)
                var config = SceneConfig.makeDefault(
                    trigger: state.waterConfig.trigger,
                    catalog: [onlyWall],
                    defaultActive: .wall
                )
                config.instances.append(
                    PresetInstance(preset: .shatter, name: "碎裂 副本", intensity: nil, builtIn: false)
                )
                config.normalize(catalog: [onlyWall], defaultActive: .wall)
                return config.instances.map(\.preset) == [.wall] && config.activeInstanceID == onlyWall.id
            }()
        )
        check("喝水默认 60 分钟", state.waterConfig.trigger.rhythm == .interval(minutes: 60))
        check(
            "活动默认三个指定时刻",
            state.activityConfig.trigger.rhythm == .timesOfDay([
                TimeOfDay(hour: 10, minute: 30),
                TimeOfDay(hour: 14, minute: 30),
                TimeOfDay(hour: 16, minute: 30),
            ])
        )
        check(
            "日程出厂停用、前置 5 分钟、三张卡",
            !state.scheduleConfig.isEnabled
                && state.scheduleConfig.trigger.leadMinutes == 5
                && state.scheduleConfig.instances.count == 3
                && state.schedule.subscriptions.isEmpty
        )
        check(
            "闹钟出厂停用、三张卡、不带前置",
            !state.alarmConfig.isEnabled
                && state.alarmConfig.trigger == .alarms
                && state.alarmConfig.instances.count == 3
        )
        check("喝水配额默认 2000 / 250", state.water.targetML == 2000 && state.water.cupML == 250)
        check("活动从 0 次开始", state.activity.doneToday == 0)
    }

    // MARK: - 节奏二选一

    /// 设置里「固定间隔 / 指定时刻」切换：两套设置各留一份，切走再切回不该被重置。
    private static func rhythmSwitch(_ check: (String, Bool) -> Void) {
        let suiteName = "com.bargein.selftest.rhythm"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            check("节奏 selftest suite available", false)
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = StateStore(defaults: defaults)
        store.setTrigger(.rhythm(.interval(minutes: 30)), for: .water)
        store.setRhythmMode(timesOfDay: true, for: .water)
        check(
            "切到指定时刻给一个起点",
            store.trigger(for: .water).rhythm == .timesOfDay([TimeOfDay(hour: 10, minute: 0)])
        )
        store.setRhythmMode(timesOfDay: false, for: .water)
        check("切回固定间隔不重置间隔", store.trigger(for: .water).rhythm == .interval(minutes: 30))

        let times = [TimeOfDay(hour: 9, minute: 30), TimeOfDay(hour: 15, minute: 0)]
        store.setTrigger(.rhythm(.timesOfDay(times)), for: .activity)
        store.setRhythmMode(timesOfDay: false, for: .activity)
        store.setRhythmMode(timesOfDay: true, for: .activity)
        check("切回指定时刻不丢掉时刻", store.trigger(for: .activity).rhythm == .timesOfDay(times))

        store.setRhythmMode(timesOfDay: true, for: .activity)
        check("点当前那一边不动设置", store.trigger(for: .activity).rhythm == .timesOfDay(times))

        let edited = [TimeOfDay(hour: 9, minute: 0), TimeOfDay(hour: 16, minute: 0)]
        store.setRhythmMode(timesOfDay: true, for: .water)
        store.setTrigger(.rhythm(.timesOfDay(edited)), for: .water)
        store.setRhythmMode(timesOfDay: false, for: .water)

        let reloaded = StateStore(defaults: defaults)
        reloaded.setRhythmMode(timesOfDay: true, for: .water)
        check("切走的那一套跟着落盘", reloaded.trigger(for: .water).rhythm == .timesOfDay(edited))
        reloaded.setRhythmMode(timesOfDay: false, for: .water)
        check("重启后切回来还是原来那个间隔", reloaded.trigger(for: .water).rhythm == .interval(minutes: 30))

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 调度

    private static func scheduling(_ check: (String, Bool) -> Void) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }

        func runtime(
            _ schedule: Schedule,
            enabled: Bool = true,
            completed: Bool = false,
            paused: Date? = nil,
            restDays: Set<Int> = [1, 7]
        ) -> SceneRuntime {
            SceneRuntime(
                isEnabled: enabled,
                trigger: .rhythm(schedule),
                workStart: .nineAM,
                workEnd: .sixPM,
                restDays: restDays,
                pausedUntil: paused,
                isCompletedToday: completed
            )
        }

        func expect(_ name: String, _ now: Date, _ runtime: SceneRuntime, _ want: Date?) {
            check(name, FirePlan.next(after: now, runtime: runtime, calendar: calendar) == want)
        }

        // 2026-11-12 是周四。
        let water = runtime(.interval(minutes: 60))
        expect("interval: 时段内", at(12, 10, 30), water, at(12, 11, 0))
        expect("interval: 时段开始前", at(12, 8, 0), water, at(12, 9, 0))
        expect("interval: 时段结束后顺延", at(12, 18, 30), water, at(13, 9, 0))
        expect("interval: 跨周末", at(13, 17, 30), water, at(16, 9, 0))

        let restThursday = runtime(.interval(minutes: 60), restDays: [5])
        expect("休息日跳过", at(12, 10, 30), restThursday, at(13, 9, 0))

        let completedWater = runtime(.interval(minutes: 60), completed: true)
        expect("喝水达标只停喝水", at(12, 10, 30), completedWater, at(13, 9, 0))

        let paused = runtime(.interval(minutes: 60), paused: at(12, 15, 0))
        expect("暂停优先", at(12, 10, 30), paused, at(12, 16, 0))

        let fixed = runtime(.timesOfDay([TimeOfDay(hour: 9, minute: 30), TimeOfDay(hour: 14, minute: 0)]))
        expect("指定时刻", at(12, 10, 0), fixed, at(12, 14, 0))
        expect("指定时刻: 用尽后顺延", at(12, 15, 0), fixed, at(13, 9, 30))

        let outOfHours = runtime(.timesOfDay([TimeOfDay(hour: 20, minute: 0)]))
        expect("时段外的指定时刻被忽略", at(12, 10, 0), outOfHours, nil)

        let disabled = runtime(.interval(minutes: 60), enabled: false)
        expect("场景停用不调度", at(12, 10, 30), disabled, nil)

        let activity = runtime(.timesOfDay([
            TimeOfDay(hour: 10, minute: 30),
            TimeOfDay(hour: 14, minute: 30),
            TimeOfDay(hour: 16, minute: 30),
        ]))
        expect("活动: 第一个点", at(12, 9, 0), activity, at(12, 10, 30))
        expect("活动: 中间点", at(12, 11, 0), activity, at(12, 14, 30))
        expect("活动: 末点后顺延到次日", at(12, 17, 0), activity, at(13, 10, 30))
    }

    // MARK: - 预设行为

    /// 某张卡此刻的呈现参数：预设自己的基础参数，强度由实例带进来。
    private static func tier(_ instance: PresetInstance) -> Presentation {
        Catalog.presentation(for: instance)
    }

    private static func behavior(_ check: (String, Bool) -> Void) {
        let gentle = PresetInstance(preset: .gentle, name: "温柔", intensity: nil, builtIn: true)
        let wall = PresetInstance(preset: .wall, name: "大字墙", intensity: .standard, builtIn: true)
        let strict = PresetInstance(preset: .wall, name: "大字墙", intensity: .strict, builtIn: true)

        check("呈现: 温柔可推迟、不锁", tier(gentle).allowsPostpone && tier(gentle).dismissDelay == 0)
        check("呈现: 标准可推迟、不锁", tier(wall).allowsPostpone && tier(wall).dismissDelay == 0)
        check("呈现: 强硬不可推迟、锁 5 秒", !tier(strict).allowsPostpone && tier(strict).dismissDelay == 5)
        check("强度是预设的属性", Catalog.theme(for: .wall).intensities == [.standard, .strict])
        check("温柔没有强度", Catalog.theme(for: .gentle).intensities.isEmpty)
        check("碎裂没有强度", Catalog.theme(for: .shatter).intensities.isEmpty)
    }

    // MARK: - 实例与首页顺序

    private static func instances(_ check: (String, Bool) -> Void) {
        let suiteName = "com.bargein.selftest.instances"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)

        let store = StateStore(defaults: defaults)
        check("两场景各自三张出厂卡", store.config(.water).instances.count == 3 && store.config(.activity).instances.count == 3)
        check(
            "喝水出厂选中大字墙·标准",
            store.activeInstance(for: .water).preset == .wall
                && store.activeInstance(for: .water).intensity == .standard
        )

        guard let copied = store.duplicate(store.activeInstance(for: .water).id, in: .water) else {
            check("复制出厂卡", false)
            return defaults.removePersistentDomain(forName: suiteName)
        }
        check("复制不自动切换", store.config(.water).activeInstanceID != copied)
        check("副本自动命名", store.config(.water).instances.first { $0.id == copied }?.name == "大字墙 副本")
        check("副本只出现在当前场景", store.config(.activity).instances.count == 3)

        check("副本排在最后", store.config(.water).instances.last?.id == copied)
        let orderBefore = store.config(.water).instances.map(\.id)

        store.activate(copied, in: .water)
        check("切换激活不挪动卡片位置", store.config(.water).instances.map(\.id) == orderBefore)
        check("切换后呈现跟实例走", tier(store.activeInstance(for: .water)).allowsPostpone)

        store.setIntensity(copied, in: .water, .strict)
        check(
            "副本可改强度",
            !tier(store.activeInstance(for: .water)).allowsPostpone
                && tier(store.activeInstance(for: .water)).dismissDelay == 5
        )

        store.setCopy(copied, in: .water, slot: .word, to: "老铁，水了")
        check("改文案落到实例覆盖", store.hasOverride(copied, in: .water, slot: .word))
        store.resetCopy(copied, in: .water)
        check("恢复默认清掉覆盖", store.hasOverride(copied, in: .water, slot: .word) == false)

        store.delete(copied, in: .water)
        check(
            "删掉在用的副本回落大字墙·标准",
            store.activeInstance(for: .water).preset == .wall
                && store.activeInstance(for: .water).intensity == .standard
        )

        if let builtIn = store.config(.water).instances.first(where: { $0.builtIn })?.id {
            store.delete(builtIn, in: .water)
        }
        check("内置不可删", store.config(.water).instances.count == 3)
        check("删掉副本后只剩内置三张", store.config(.water).instances.allSatisfy(\.builtIn))

        // 复制出来的卡都排在内置三张之后，且复制不会替用户切换当前预设
        let wallID = store.config(.water).instances.first { $0.preset == .wall }?.id
        guard let first = wallID.flatMap({ store.duplicate($0, in: .water) }),
              let second = wallID.flatMap({ store.duplicate($0, in: .water) })
        else {
            check("再复制两张", false)
            return defaults.removePersistentDomain(forName: suiteName)
        }
        check("副本追加在末尾", store.config(.water).instances.suffix(2).map(\.id) == [first, second])
        check("复制不切换激活", store.config(.water).activeInstanceID != second)

        // 点一张卡只换勾选：网格顺序保持稳定，卡片不会在鼠标下跳位
        let orderBeforeSwitch = store.config(.water).instances.map(\.id)
        store.activate(second, in: .water)
        check("点选只改勾选", store.config(.water).activeInstanceID == second)
        check("点选不改卡片顺序", store.config(.water).instances.map(\.id) == orderBeforeSwitch)

        // 改名只改卡片名：首尾空白去掉，空名不生效，派生副本跟着新名走
        store.rename(first, in: .water, to: "  暴躁大字墙  ")
        check("副本可改名", store.config(.water).instances.first { $0.id == first }?.name == "暴躁大字墙")
        store.rename(first, in: .water, to: "   ")
        check("空名不生效", store.config(.water).instances.first { $0.id == first }?.name == "暴躁大字墙")
        let derived = store.duplicate(first, in: .water)
        check(
            "改名后再复制按新名派生",
            derived.flatMap { id in store.config(.water).instances.first { $0.id == id }?.name } == "暴躁大字墙 副本"
        )

        // 落盘往返：实例列表与激活项都要活下来
        let reloaded = StateStore(defaults: defaults)
        check("实例列表落盘", reloaded.config(.water).instances.count == 6)
        check("激活项落盘", reloaded.config(.water).activeInstanceID == store.config(.water).activeInstanceID)
        check("卡片顺序落盘", reloaded.config(.water).instances.map(\.id) == store.config(.water).instances.map(\.id))
        check("改好的名字落盘", reloaded.config(.water).instances.first { $0.id == first }?.name == "暴躁大字墙")

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 场景隔离与启用

    private static func scenes(_ check: (String, Bool) -> Void) {
        let suiteName = "com.bargein.selftest.scenes"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)

        let store = StateStore(defaults: defaults)
        store.recordSkip(.water)
        check("跳过喝水不影响活动账本", store.config(.water).skipsToday == 1 && store.config(.activity).skipsToday == 0)

        store.recordSkip(.activity)
        store.completeActivity()
        check("完成只记录、不清跳过", store.config(.activity).skipsToday == 1 && store.state.activity.doneToday == 1)
        store.drink()
        check(
            "记一杯只加进度、不清跳过",
            store.config(.water).skipsToday == 1 && store.state.water.consumedML == store.state.water.cupML
        )

        store.set(\.water.consumedML, store.state.water.targetML)
        let now = Date()
        check("喝水达标后顺延到次日", store.nextFireDate(for: .water, after: now).map { !store.isSameDay($0, now) } == true)
        check("喝水达标不影响活动调度", store.nextFireDate(for: .activity, after: now) != nil)

        store.setSceneEnabled(false, for: .activity)
        check("停用活动后不调度", store.nextFireDate(for: .activity, after: now) == nil)
        check("停用活动不影响喝水", store.nextFireDate(for: .water, after: now) != nil)
        store.setSceneEnabled(false, for: .water)
        check("全部停用没有下一次", store.nextFireDate(for: .water, after: now) == nil)
        store.setSceneEnabled(true, for: .water)
        store.setSceneEnabled(true, for: .activity)

        check("闹钟出厂停用不调度", !store.isSceneEnabled(.alarm) && store.nextFireDate(for: .alarm, after: now) == nil)
        store.setSceneEnabled(true, for: .alarm)
        check("闹钟打开但还没有闹钟时不触发", store.nextFireDate(for: .alarm, after: now) == nil)
        check("闹钟场景配置落盘", StateStore(defaults: defaults).isSceneEnabled(.alarm))
        store.setSceneEnabled(false, for: .alarm)

        store.applyPresetToAllScenes(.gentle)
        check(
            "首启选择落到全部场景",
            store.activeInstance(for: .water).preset == .gentle
                && store.activeInstance(for: .activity).preset == .gentle
                && store.activeInstance(for: .schedule).preset == .gentle
                && store.activeInstance(for: .alarm).preset == .gentle
        )

        store.set(\.lastActiveDate, Calendar.current.date(byAdding: .day, value: -1, to: now)!)
        store.refreshDay(now: now)
        check(
            "跨日重置两个场景",
            store.state.water.consumedML == 0
                && store.state.activity.doneToday == 0
                && store.config(.water).skipsToday == 0
                && store.config(.activity).skipsToday == 0
        )

        // 唤醒补提醒只在同一天、工作时段内、未暂停时成立
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        let windowDefaults = UserDefaults(suiteName: "com.bargein.selftest.window")!
        windowDefaults.removePersistentDomain(forName: "com.bargein.selftest.window")
        let windowStore = StateStore(defaults: windowDefaults, calendar: calendar)
        check("工作时段内可补提醒", windowStore.isWithinActiveWindow(at: at(12, 10, 0)))
        check("休息日不补提醒", windowStore.isWithinActiveWindow(at: at(14, 10, 0)) == false)
        check("时段外不补提醒", windowStore.isWithinActiveWindow(at: at(12, 18, 30)) == false)
        windowStore.set(\.pausedUntil, at(12, 15, 0))
        check("暂停中不补提醒", windowStore.isWithinActiveWindow(at: at(12, 10, 0)) == false)
        windowDefaults.removePersistentDomain(forName: "com.bargein.selftest.window")

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 文案

    private static func copyResolution(_ check: (String, Bool) -> Void) {
        let wall = PresetInstance(preset: .wall, name: "大字墙", intensity: .standard)
        let water = WaterScene.descriptor
        let waterValues = WaterState(consumedML: 750).copyValues

        check("文案: 默认大字词", CopyText.text(.word, instance: wall, scene: water, values: waterValues) == "该喝水了")
        check(
            "文案: 进度模板填变量",
            CopyText.text(.progress, instance: wall, scene: water, values: waterValues)
                == "750 / 2,000 ml"
        )
        check("文案: 识别不出未知变量", CopyText.hasUnknownVariables("还差 {remaining} ml", scene: water) == false)
        check("文案: 杯数不再是变量", CopyText.hasUnknownVariables("{cup}/{cups} 杯", scene: water))
        check("文案: 识别未知变量", CopyText.hasUnknownVariables("今天第 {glass} 杯", scene: water))

        var custom = wall
        custom.copyOverrides[CopySlot.word.rawValue] = "老铁，水了"
        check(
            "文案: 实例覆盖优先",
            CopyText.text(.word, instance: custom, scene: water, values: waterValues) == "老铁，水了"
        )

        var broken = wall
        broken.copyOverrides[CopySlot.progress.rawValue] = "还差 {glass} 杯"
        check(
            "文案: 未知变量整段回落",
            CopyText.text(.progress, instance: broken, scene: water, values: waterValues)
                == "750 / 2,000 ml"
        )

        let activity = ActivityScene.descriptor
        check("活动: 默认大字词", CopyText.text(.word, instance: wall, scene: activity, values: [:]) == "该活动了")
        check(
            "活动: 进度是动作指令",
            CopyText.text(.progress, instance: wall, scene: activity, values: [:]) == "站起来，活动 1 分钟"
        )
        check("活动: 没有可用变量", CopyText.hasUnknownVariables("今天第 {cup} 次", scene: activity))

        let copy = ReminderCopy.make(instance: wall, scene: activity, values: [:])
        check("活动提醒文案", copy.word == "该活动了" && copy.progress == "站起来，活动 1 分钟")

        check("温柔只渲染标题与进度", Catalog.theme(for: .gentle).slots == [.title, .progress])
        check("大字墙渲染大字词与进度", Catalog.theme(for: .wall).slots == [.word, .progress])

        // 日程状态行：几天以后的事只报天，不印几千分钟
        let now = Date(timeIntervalSinceReferenceDate: 0)
        check(
            "文案: 几小时以后报小时",
            RelativeTime.distance(from: now, to: now.addingTimeInterval(2 * 3600 + 5 * 60)) == "2 小时 5 分钟后"
        )
        check("文案: 几天以后只报天", RelativeTime.distance(from: now, to: now.addingTimeInterval(6813 * 60)) == "4 天后")
    }

    // MARK: - 队列

    private static func queue(_ check: (String, Bool) -> Void) {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let eventA = EventKey(uid: "a", start: now)
        let eventB = EventKey(uid: "b", start: now)

        let different: [(key: ReminderKey, at: Date)] = [
            (.sceneOnly(.water), now),
            (.sceneOnly(.activity), now.addingTimeInterval(-60)),
            (ReminderKey(scene: .schedule, event: eventA), now.addingTimeInterval(-10)),
        ]
        check(
            "队列: 先到先排",
            ReminderQueue.sorted(different) == [
                .sceneOnly(.activity),
                ReminderKey(scene: .schedule, event: eventA),
                .sceneOnly(.water),
            ]
        )

        let same: [(key: ReminderKey, at: Date)] = [
            (.sceneOnly(.water), now),
            (.sceneOnly(.activity), now),
        ]
        check("队列: 并列按场景顺序", ReminderQueue.sorted(same) == [.sceneOnly(.water), .sceneOnly(.activity)])

        var pending: [ReminderKey] = []
        ReminderQueue.enqueue([.sceneOnly(.water), .sceneOnly(.activity)], into: &pending)
        ReminderQueue.enqueue(
            [
                .sceneOnly(.water),
                ReminderKey(scene: .schedule, event: eventA),
                ReminderKey(scene: .schedule, event: eventA),
                ReminderKey(scene: .schedule, event: eventB),
            ],
            into: &pending
        )
        check(
            "队列: 同场景一条、日程按事件各一条",
            pending.count == 4
                && pending.filter { $0.scene == .water }.count == 1
                && pending.filter { $0.scene == .schedule }.count == 2
        )
    }

    // MARK: - 闹钟

    private static func alarms(_ check: (String, Bool) -> Void) {
        let calendar = shanghai()
        func day(_ dayNumber: Int) -> Date {
            // 2026-11：13 是周五，14 是周六，16 是周一。
            calendar.date(from: DateComponents(year: 2026, month: 11, day: dayNumber))!
        }
        let workStart = TimeOfDay(hour: 9, minute: 0)
        let workEnd = TimeOfDay(hour: 18, minute: 0)
        let restDays: Set<Int> = [1, 7]
        func issue(_ alarm: Alarm) -> AlarmIssue? {
            AlarmPolicy.issue(
                for: alarm,
                workStart: workStart,
                workEnd: workEnd,
                restDays: restDays,
                calendar: calendar
            )
        }

        let lunch = Alarm(title: "点外卖", time: TimeOfDay(hour: 11, minute: 30))
        check("闹钟: 每天、工作时段内有效", issue(lunch) == nil)
        check(
            "闹钟: 工作时段外无效",
            issue(Alarm(title: "去健身", time: TimeOfDay(hour: 19, minute: 30))) == .outsideWorkHours
        )
        check(
            "闹钟: 结束时刻算时段外（与指定时刻一致）",
            issue(Alarm(title: "下班", time: workEnd)) == .outsideWorkHours
        )
        check(
            "闹钟: 一次性落在休息日无效",
            issue(Alarm(
                title: "交周报",
                time: TimeOfDay(hour: 16, minute: 0),
                recurrence: .once(day(14))
            )) == .restDay
        )
        check(
            "闹钟: 一次性落在工作日有效",
            issue(Alarm(
                title: "交周报",
                time: TimeOfDay(hour: 16, minute: 0),
                recurrence: .once(day(16))
            )) == nil
        )
        check(
            "闹钟: 日期卡在未来 7 天内",
            AlarmPolicy.clamp(day(30), now: day(13), calendar: calendar) == day(19)
        )

        let suiteName = "com.bargein.selftest.alarms"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)
        let store = StateStore(defaults: defaults, calendar: calendar)

        let id = store.addAlarm(Alarm(title: "点外卖", time: TimeOfDay(hour: 11, minute: 30)))
        check("闹钟: 添加进列表", store.alarms.count == 1 && store.alarm(id)?.title == "点外卖")
        store.updateAlarm(id) { item in
            item.title = "吃饭"
            item.time = TimeOfDay(hour: 12, minute: 0)
        }
        check(
            "闹钟: 编辑即时生效",
            store.alarm(id)?.title == "吃饭" && store.alarm(id)?.time == TimeOfDay(hour: 12, minute: 0)
        )
        store.setAlarmEnabled(false, for: id)
        check("闹钟: 单独停用", store.alarm(id)?.isEnabled == false)
        check(
            "闹钟: 配置落盘",
            StateStore(defaults: defaults).alarm(id)?.title == "吃饭"
                && StateStore(defaults: defaults).alarm(id)?.isEnabled == false
        )
        store.deleteAlarm(id)
        check("闹钟: 删除后从列表消失", store.alarms.isEmpty)

        // 无效是派生的：改一次通用时间就重判，不落盘、不需要重建条目。
        let lateID = store.addAlarm(Alarm(title: "去健身", time: TimeOfDay(hour: 19, minute: 30)))
        check(
            "闹钟: 工作时段外的条目判无效",
            store.alarm(lateID).flatMap(store.alarmIssue) == .outsideWorkHours
        )
        store.set(\.workEnd, TimeOfDay(hour: 21, minute: 0))
        check("闹钟: 改工作时段后立即重判", store.alarm(lateID).flatMap(store.alarmIssue) == nil)
        store.set(\.workEnd, TimeOfDay(hour: 18, minute: 0))
        store.deleteAlarm(lateID)

        // 逐条容错：一条不是对象的闹钟只丢它自己，其余照留。
        guard let encoded = try? JSONEncoder().encode(AlarmState(alarms: [lunch])),
              var object = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any],
              let items = object["alarms"] as? [Any]
        else {
            check("闹钟: 存档可编码", false)
            return
        }
        object["alarms"] = items + ["not-an-alarm"]
        guard let patched = try? JSONSerialization.data(withJSONObject: object),
              let decoded = try? JSONDecoder().decode(AlarmState.self, from: patched)
        else {
            check("闹钟: 坏条目不拖垮整份状态", false)
            return
        }
        check("闹钟: 坏条目只丢那一条", decoded.alarms.count == 1 && decoded.alarms.first?.title == "点外卖")

        // 缺字段的闹钟按缺哪补哪读回来，不整条丢。
        let sparse = Data(#"{"alarms":[{"title":"开会","time":{"hour":10,"minute":0}}]}"#.utf8)
        let sparseState = try? JSONDecoder().decode(AlarmState.self, from: sparse)
        check(
            "闹钟: 缺字段补默认值",
            sparseState?.alarms.count == 1
                && sparseState?.alarms.first?.recurrence == .daily
                && sparseState?.alarms.first?.isEnabled == true
        )

        // 调度：铺点、补发、结束
        store.set(\.workStart, TimeOfDay(hour: 9, minute: 0))
        store.set(\.workEnd, TimeOfDay(hour: 18, minute: 0))
        store.set(\.restDays, [1, 7])
        store.setSceneEnabled(true, for: .alarm)

        let friday = day(13)
        let lunchID = store.addAlarm(Alarm(title: "点外卖", time: TimeOfDay(hour: 11, minute: 30)))
        let moments = store.alarmMoments(after: friday)
        let weekdays = moments.map { calendar.component(.weekday, from: $0.at) }
        check(
            "闹钟: 每天铺点跳过休息日",
            moments.count == 6
                && !weekdays.contains(1)
                && !weekdays.contains(7)
                && moments.allSatisfy { $0.id == lunchID.uuidString }
        )

        let at1130 = calendar.date(bySettingHour: 11, minute: 30, second: 0, of: friday)!
        check("闹钟: 到点入队", store.dueAlarms(at: at1130.addingTimeInterval(5 * 60)).count == 1)
        check(
            "闹钟: 重复闹钟错过不补",
            store.dueAlarms(at: at1130.addingTimeInterval(30 * 60)).isEmpty
        )

        let outsideID = store.addAlarm(Alarm(title: "去健身", time: TimeOfDay(hour: 19, minute: 30)))
        check(
            "闹钟: 无效条目不产生候选",
            !store.alarmMoments(after: friday).contains { $0.id == outsideID.uuidString }
        )
        store.deleteAlarm(outsideID)

        let monday = day(16)
        let onceID = store.addAlarm(Alarm(
            title: "交周报",
            time: TimeOfDay(hour: 16, minute: 0),
            recurrence: .once(monday)
        ))
        let at1600 = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: monday)!
        check(
            "闹钟: 一次性在补发窗口内补一次",
            store.dueAlarms(at: at1600.addingTimeInterval(30 * 60))
                .contains { $0.key.event?.uid == onceID.uuidString }
        )
        check(
            "闹钟: 一次性出窗口不补",
            store.dueAlarms(at: at1600.addingTimeInterval(61 * 60))
                .allSatisfy { $0.key.event?.uid != onceID.uuidString }
        )

        // 免打扰按"不在场"处理：期间不采集，结束后仍在窗口内补一次。
        store.set(\.pausedUntil, at1600.addingTimeInterval(20 * 60))
        check(
            "闹钟: 免打扰期间不采集",
            store.dueAlarms(at: at1600.addingTimeInterval(10 * 60)).isEmpty
        )
        store.set(\.pausedUntil, Optional<Date>.none)
        check(
            "闹钟: 免打扰结束后仍在窗口内补",
            store.dueAlarms(at: at1600.addingTimeInterval(30 * 60))
                .contains { $0.key.event?.uid == onceID.uuidString }
        )

        // 补发窗口被当天工作时段结束封顶：下班之后不再补。
        let lateOnceID = store.addAlarm(Alarm(
            title: "收尾",
            time: TimeOfDay(hour: 17, minute: 50),
            recurrence: .once(monday)
        ))
        let at1750 = calendar.date(bySettingHour: 17, minute: 50, second: 0, of: monday)!
        check(
            "闹钟: 补发窗口被下班截断",
            store.dueAlarms(at: at1750.addingTimeInterval(5 * 60))
                .contains { $0.key.event?.uid == lateOnceID.uuidString }
                && store.dueAlarms(at: at1750.addingTimeInterval(15 * 60))
                    .allSatisfy { $0.key.event?.uid != lateOnceID.uuidString }
        )

        // 推迟跨过下班时间，仍补一次（和日程「推迟过的还要提醒」一致）。
        let earlyID = store.addAlarm(Alarm(title: "收尾会", time: TimeOfDay(hour: 17, minute: 55)))
        let at1755 = calendar.date(bySettingHour: 17, minute: 55, second: 0, of: monday)!
        store.snoozeAlarm(EventKey(uid: earlyID.uuidString, start: at1755), minutes: 5, at: at1755)
        check(
            "闹钟: 推迟跨过下班仍补一次",
            store.dueAlarms(at: at1755.addingTimeInterval(6 * 60))
                .contains { $0.key.event?.uid == earlyID.uuidString }
        )
        store.deleteAlarm(earlyID)
        store.deleteAlarm(lateOnceID)

        let onceKey = EventKey(uid: onceID.uuidString, start: at1600)
        store.finishAlarm(onceKey)
        check("闹钟: 一次性关闭后从列表消失", store.alarm(onceID) == nil)
        store.finishAlarm(EventKey(uid: lunchID.uuidString, start: at1130))
        check("闹钟: 每天关闭后留在列表", store.alarm(lunchID) != nil)

        store.recordSkip(.alarm)
        check(
            "闹钟: 跳过记在闹钟自己的账本上",
            store.config(.alarm).skipsToday == 1 && store.config(.water).skipsToday == 0
        )
        store.finishAlarm(EventKey(uid: lunchID.uuidString, start: at1130))
        check("闹钟: 知道了只记录、不清跳过", store.config(.alarm).skipsToday == 1)

        let lunchKey = EventKey(uid: lunchID.uuidString, start: at1130)
        let values = store.copyValues(for: ReminderKey(scene: .alarm, event: lunchKey))
        let descriptor = store.descriptor(.alarm)
        let copy = ReminderCopy.make(
            instance: store.activeInstance(for: .alarm),
            scene: descriptor,
            values: values
        )
        check(
            "闹钟: 大字词是内容、进度行是时刻",
            values["title"] == "点外卖" && values["start"] == "11:30"
                && copy.word == "点外卖" && copy.progress == "11:30"
        )
        check("闹钟: 完成动作是知道了", descriptor.completionLabel == "知道了")

        // 下一次触发：处理过的跳过、推迟过的顺延
        let runtime = SceneRuntime(
            isEnabled: true,
            trigger: .alarms,
            workStart: TimeOfDay(hour: 9, minute: 0),
            workEnd: TimeOfDay(hour: 18, minute: 0),
            restDays: [1, 7],
            pausedUntil: nil,
            isCompletedToday: false,
            moments: [ScheduledMoment(id: "a", at: at1130, isOneShot: false)]
        )
        check(
            "闹钟: 下一次触发取最早的未处理时刻",
            FirePlan.next(after: friday.addingTimeInterval(9 * 3600), runtime: runtime, calendar: calendar)
                == at1130
        )
        var handledRuntime = runtime
        handledRuntime.handledMoments = [EventKey(uid: "a", start: at1130)]
        check(
            "闹钟: 处理过的时刻不再触发",
            FirePlan.next(after: friday, runtime: handledRuntime, calendar: calendar) == nil
        )
        var snoozedRuntime = runtime
        let snoozedAt = at1130.addingTimeInterval(5 * 60)
        snoozedRuntime.snoozedMoments = [EventKey(uid: "a", start: at1130): snoozedAt]
        check(
            "闹钟: 推迟后按推迟时刻再触发",
            FirePlan.next(after: friday, runtime: snoozedRuntime, calendar: calendar) == snoozedAt
        )

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 日历

    private static func shanghai() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    private static func icsDate(_ text: String, calendar: Calendar) -> Date? {
        guard let event = IcsParser.parse(text, calendar: calendar).first else { return nil }
        return event.start
    }

    private static func calendarParsing(_ check: (String, Bool) -> Void) {
        let calendar = shanghai()
        let friday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 0, minute: 0))!
        let window = DateInterval(start: friday, duration: 3 * 86_400)

        let weekly = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:weekly@example.com
        SUMMARY:周会
        LOCATION:会议室 A
        DTSTART;TZID=Asia/Shanghai:20261113T093000
        RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=FR
        END:VEVENT
        END:VCALENDAR
        """
        let weeklyEvents = IcsParser.occurrences(
            from: weekly,
            subscriptionID: UUID(),
            window: window,
            calendar: calendar
        )
        check(
            "日历: 周会落在周五 9:30",
            weeklyEvents.count == 1
                && weeklyEvents.first.map { calendar.component(.hour, from: $0.start) == 9 } == true
                && weeklyEvents.first?.title == "周会"
        )

        // 真实日历（钉钉、Google）都是 CRLF，Swift 会把 \r\n 视作一个字符，必须单独钉住。
        let crlf = weekly.replacingOccurrences(of: "\n", with: "\r\n")
        check(
            "日历: CRLF 换行也能解析",
            IcsParser.occurrences(from: crlf, subscriptionID: UUID(), window: window, calendar: calendar).count == 1
        )

        let excluded = weekly.replacingOccurrences(
            of: "END:VEVENT",
            with: "EXDATE;TZID=Asia/Shanghai:20261113T093000\nEND:VEVENT"
        )
        check(
            "日历: EXDATE 排除这一次",
            IcsParser.occurrences(from: excluded, subscriptionID: UUID(), window: window, calendar: calendar).isEmpty
        )

        // 钉钉下发的形态：主事件带 RRULE，被改期的那一次单独下发，DTSTART 是新时间、RECURRENCE-ID 是原时间。
        let rescheduled = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:review@example.com
        SUMMARY:评审会
        DTSTART;TZID=Asia/Shanghai:20261113T133000
        RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=FR
        END:VEVENT
        BEGIN:VEVENT
        UID:review@example.com
        SUMMARY:评审会
        DTSTART;TZID=Asia/Shanghai:20261113T141500
        RECURRENCE-ID:20261113T053000Z
        END:VEVENT
        END:VCALENDAR
        """
        let rescheduledEvents = IcsParser.occurrences(
            from: rescheduled,
            subscriptionID: UUID(),
            window: window,
            calendar: calendar
        )
        check(
            "日历: 改期的那一次只留新时间，旧时间让位",
            rescheduledEvents.count == 1
                && rescheduledEvents.first?.start
                    == calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 14, minute: 15))
        )

        // 同一实例被服务器下发两遍（两个集合里都有这场会）：只留一条。
        let duplicated = weekly.replacingOccurrences(
            of: "END:VCALENDAR",
            with: """
            BEGIN:VEVENT
            UID:weekly@example.com
            SUMMARY:周会
            DTSTART;TZID=Asia/Shanghai:20261113T093000
            END:VEVENT
            END:VCALENDAR
            """
        )
        check(
            "日历: 同一次发生重复下发只留一条",
            IcsParser.occurrences(from: duplicated, subscriptionID: UUID(), window: window, calendar: calendar).count == 1
        )

        let allDay = """
        BEGIN:VEVENT
        UID:allday@example.com
        SUMMARY:交社保
        DTSTART;VALUE=DATE:20261113
        END:VEVENT
        """
        check(
            "日历: 全天事件不提醒",
            IcsParser.occurrences(from: allDay, subscriptionID: UUID(), window: window, calendar: calendar).isEmpty
        )

        let utc = """
        BEGIN:VEVENT
        UID:utc@example.com
        SUMMARY:UTC 会议
        DTSTART:20261113T013000Z
        END:VEVENT
        """
        let utcStart = icsDate(utc, calendar: calendar)
        check(
            "日历: UTC 换算成本地 9:30",
            utcStart != nil && calendar.component(.hour, from: utcStart!) == 9 && calendar.component(.minute, from: utcStart!) == 30
        )

        let folded = """
        BEGIN:VEVENT
        UID:folded@example.com
        SUMMARY:很长的标题被折
         行了
        DTSTART;TZID=Asia/Shanghai:20261113T100000
        END:VEVENT
        """
        check(
            "日历: 折行拼回一个标题",
            IcsParser.parse(folded, calendar: calendar).first?.title == "很长的标题被折行了"
        )

        check("日历: 只接受 https", Subscription.normalize("http://example.com/a.ics") == nil)
        check(
            "日历: webcal 改写成 https",
            Subscription.normalize("webcal://example.com/a.ics")?.absoluteString == "https://example.com/a.ics"
        )
    }

    private static func calendarScheduling(_ check: (String, Bool) -> Void) {
        let calendar = shanghai()
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 8, minute: 0))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 10, minute: 0))!
        let event = EventOccurrence(
            subscriptionID: UUID(),
            uid: "meeting",
            start: start,
            title: "评审"
        )

        func runtime(
            events: [EventOccurrence],
            handled: Set<EventKey> = [],
            snoozed: [EventKey: Date] = [:],
            restDays: Set<Int> = [1, 7],
            paused: Date? = nil
        ) -> SceneRuntime {
            SceneRuntime(
                isEnabled: true,
                trigger: .events(leadMinutes: 5),
                workStart: .nineAM,
                workEnd: .sixPM,
                restDays: restDays,
                pausedUntil: paused,
                isCompletedToday: false,
                events: events,
                handled: handled,
                snoozedUntil: snoozed
            )
        }

        let expected = start.addingTimeInterval(-300)
        check(
            "日程: 触发时刻是开始前 5 分钟",
            FirePlan.next(after: monday, runtime: runtime(events: [event]), calendar: calendar) == expected
        )

        // 休息日（周一不是休息日，换成周日）依然要提醒：周日的会不该被静默吞掉。
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 8, minute: 0))!
        let sundayStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10, minute: 0))!
        let sundayEvent = EventOccurrence(
            subscriptionID: UUID(),
            uid: "sunday",
            start: sundayStart,
            title: "周日的事"
        )
        check(
            "日程: 休息日照常提醒",
            FirePlan.next(after: sunday, runtime: runtime(events: [sundayEvent], restDays: [1, 7]), calendar: calendar)
                == sundayStart.addingTimeInterval(-300)
        )

        // 晚上 20:00 的会不受工作时段约束。
        let evening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 20, minute: 0))!
        let eveningEvent = EventOccurrence(
            subscriptionID: UUID(),
            uid: "evening",
            start: evening,
            title: "晚饭"
        )
        check(
            "日程: 工作时段外照常提醒",
            FirePlan.next(after: monday, runtime: runtime(events: [eveningEvent]), calendar: calendar)
                == evening.addingTimeInterval(-300)
        )

        check(
            "日程: 已经开完的会不补",
            FirePlan.next(
                after: start.addingTimeInterval(900),
                runtime: runtime(events: [event]),
                calendar: calendar
            ) == nil
        )
        check(
            "日程: 提醒过的不重弹",
            FirePlan.next(
                after: monday,
                runtime: runtime(events: [event], handled: [event.key]),
                calendar: calendar
            ) == nil
        )
        let firedAt = start.addingTimeInterval(-300)
        let snoozedUntil = firedAt.addingTimeInterval(300)
        check(
            "日程: 推迟后按推迟时刻再提醒",
            FirePlan.next(
                after: firedAt,
                runtime: runtime(events: [event], snoozed: [event.key: snoozedUntil]),
                calendar: calendar
            ) == snoozedUntil
        )
        check(
            "日程: 免打扰期间不触发",
            FirePlan.next(
                after: monday,
                runtime: runtime(events: [event], paused: start.addingTimeInterval(3600)),
                calendar: calendar
            ) == nil
        )
    }

    private static func calendarStore(_ check: (String, Bool) -> Void) {
        let suiteName = "com.bargein.selftest.calendar"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            check("日历 suite 可用", false)
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let calendar = shanghai()
        let store = StateStore(defaults: defaults, calendar: calendar)
        let subscription = Subscription(
            kind: .ics,
            name: "测试日历",
            url: URL(string: "https://example.com/a.ics")!
        )
        store.upsert(subscription)
        store.setTrigger(.events(leadMinutes: 5), for: .schedule)
        store.setSceneEnabled(true, for: .schedule)

        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9, minute: 0))!
        let soon = now.addingTimeInterval(10 * 60)
        let later = now.addingTimeInterval(3600)
        store.setEvents([
            EventOccurrence(subscriptionID: subscription.id, uid: "soon", start: soon, title: "十分钟后"),
            EventOccurrence(subscriptionID: subscription.id, uid: "later", start: later, title: "一小时后"),
        ])

        check("日程: 下一次触发取最近一场", store.nextFireDate(for: .schedule, after: now) == soon.addingTimeInterval(-300))
        check("日程: popover 显示最近一场", store.nextEvent(after: now)?.uid == "soon")
        check("日程: 未到点不入队", store.dueEvents(for: .schedule, at: now).isEmpty)
        check("日程: 到点入队", store.dueEvents(for: .schedule, at: soon.addingTimeInterval(-240)).count == 1)

        store.markHandled(EventKey(uid: "soon", start: soon), at: now)
        check("日程: 处理过的不再入队", store.dueEvents(for: .schedule, at: soon.addingTimeInterval(-240)).isEmpty)
        check("日程: 处理过的不再是下一场", store.nextEvent(after: now)?.uid == "later")

        store.upsert(subscription)
        check("日程: 同一来源不重复添加", store.subscriptions.count == 1)

        store.setSubscriptionEnabled(false, for: subscription.id)
        check("日程: 停用来源后无事件可用", store.scheduleEvents.isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 旧数据

    private static func legacyData(_ check: (String, Bool) -> Void) {
        func decode(_ json: String) -> AppState? {
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(AppState.self, from: data)
        }

        if let state = decode("{}") {
            check(
                "空数据回出厂两个场景",
                state.waterConfig.instances.count == 3 && state.activityConfig.instances.count == 3
            )
            check(
                "老存档默认开着自动检查更新",
                state.checkForUpdates && state.lastNotifiedVersion == nil
            )
        } else {
            check("空数据可解码", false)
        }

        // 老存档只有两张内置：解码时补一张碎裂，追加在末尾，激活项不动；解码两次也不会重复补。
        var old = AppState()
        old.waterConfig.instances.removeAll { $0.preset == .shatter }
        let oldWater = old.waterConfig
        if let data = try? JSONEncoder().encode(old),
           var decoded = try? JSONDecoder().decode(AppState.self, from: data) {
            check(
                "老存档补一张碎裂",
                decoded.waterConfig.instances.count == 3
                    && decoded.waterConfig.instances.last?.preset == .shatter
            )
            check("补卡不动激活项", decoded.waterConfig.activeInstanceID == oldWater.activeInstanceID)
            if let again = try? JSONEncoder().encode(decoded),
               let twice = try? JSONDecoder().decode(AppState.self, from: again) {
                decoded = twice
            }
            check("补卡幂等", decoded.waterConfig.instances.count == 3)
        } else {
            check("老存档补卡可解码", false)
        }

        // 老实例里可能还留着裂纹字段：现在没有这个属性，解码时直接忽略。
        if let legacy = try? JSONDecoder().decode(PresetInstance.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","preset":"shatter","name":"碎裂","pattern":"fixed","copyOverrides":{},"builtIn":true}"#.utf8)) {
            check("老碎裂实例仍可解码", legacy.preset == .shatter)
        } else {
            check("老碎裂实例可解码", false)
        }
        let shatterTier = tier(PresetInstance(preset: .shatter, name: "碎裂", intensity: nil))
        let wallStandardTier = tier(PresetInstance(preset: .wall, name: "大字墙", intensity: .standard))
        check(
            "碎裂档位与大字墙·标准同档",
            shatterTier.allowsPostpone == wallStandardTier.allowsPostpone
                && shatterTier.dismissDelay == wallStandardTier.dismissDelay
                && shatterTier.interruptNeedsHold == wallStandardTier.interruptNeedsHold
        )

        // 内部开发阶段没有老用户：旧扁平存档能解码即可，业务数据回出厂，不炸启动。
        if let state = decode(#"{"preset":"strict","consumedML":500,"skipsToday":2,"hasOnboarded":true}"#) {
            check("旧数据回出厂场景", state.waterConfig.instances.count == 3 && state.hasOnboarded)
        } else {
            check("旧数据可解码", false)
        }

        // 11/12 那版存档的 `schedule` 里还没有 `subscriptions`：以前整份存档解码失败、回出厂，
        // 用户看到的正是"重新打包安装之后首屏又出现、数据全丢"。
        let beforeSubscriptions = #"{"water":{"targetML":2000,"cupML":250,"consumedML":750},"schedule":{"handled":{}},"hasOnboarded":true,"workStart":{"hour":9,"minute":0},"workEnd":{"hour":18,"minute":0},"restDays":[1,7]}"#
        if let state = decode(beforeSubscriptions) {
            check(
                "缺 schedule.subscriptions 的老存档不丢进度",
                state.water.consumedML == 750 && state.hasOnboarded && state.schedule.subscriptions.isEmpty
            )
        } else {
            check("缺 schedule.subscriptions 的老存档可解码", false)
        }

        // 一张卡的 preset 是不认识的 rawValue：只丢这一张，别的一个不动。
        var withBadCard = AppState()
        withBadCard.water.consumedML = 750
        withBadCard.hasOnboarded = true
        if var json = jsonObject(withBadCard),
           var water = json["waterConfig"] as? [String: Any],
           var instances = water["instances"] as? [[String: Any]],
           !instances.isEmpty {
            instances[0]["preset"] = "不认识的预置"
            water["instances"] = instances
            json["waterConfig"] = water
            if let state = decodeObject(AppState.self, json) {
                check("一张坏卡只丢一张", state.water.consumedML == 750 && state.hasOnboarded)
            } else {
                check("有坏卡的存档可解码", false)
            }
        } else {
            check("坏卡样本可构造", false)
        }

        // 护栏：以后往存档类型里加字段，忘了给默认值就会在这里红——
        // 那种错误上线一次就吞一次存档。
        check("空 WaterState 可解码", decodes(WaterState.self, "{}"))
        check("空 ActivityState 可解码", decodes(ActivityState.self, "{}"))
        check("空 ScheduleState 可解码", decodes(ScheduleState.self, "{}"))
        check("只剩 preset 的卡可解码", decodes(PresetInstance.self, #"{"preset":"wall"}"#))
        check("只剩 trigger 的场景配置可解码", decodes(SceneConfig.self, #"{"trigger":{"events":{"leadMinutes":5}}}"#))
        check("只剩 kind 与 url 的订阅可解码", decodes(Subscription.self, #"{"kind":"ics","url":"https://example.com/a.ics"}"#))

        // 逐字段容错也救不回来的档：整份另存一份，别静默删。
        let suiteName = "com.bargein.selftest.unreadable"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
            let before = backupFiles()
            defaults.set(Data("not an AppState".utf8), forKey: "AppState")
            let store = StateStore(defaults: defaults)
            let after = backupFiles()
            check("读不了的档另存一份", after.subtracting(before).count == 1)
            check("读不了的档回出厂但不崩", !store.state.hasOnboarded && store.progress == 0)
            for url in after.subtracting(before) { try? FileManager.default.removeItem(at: url) }
            defaults.removePersistentDomain(forName: suiteName)
        } else {
            check("坏档样本可写", false)
        }
    }

    private static func decodes<T: Decodable>(_ type: T.Type, _ json: String) -> Bool {
        (try? JSONDecoder().decode(type, from: Data(json.utf8))) != nil
    }

    private static func jsonObject(_ state: AppState) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func decodeObject<T: Decodable>(_ type: T.Type, _ json: [String: Any]) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func backupFiles() -> Set<URL> {
        let dir = StateStore.backupDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return Set(names.map { dir.appendingPathComponent($0) })
    }

    // MARK: - 更新检查

    private static func updates(_ check: (String, Bool) -> Void) {
        check("版本: 0.5.0 比 0.4.1 新", UpdateChecker.isNewer("0.5.0", than: "0.4.1"))
        check("版本: 逐段按数字比，0.4.10 比 0.4.9 新", UpdateChecker.isNewer("0.4.10", than: "0.4.9"))
        check("版本: 带 v 的 tag 与裸版本同版", !UpdateChecker.isNewer("v0.4.1", than: "0.4.1"))
        check("版本: 同版不算更新", !UpdateChecker.isNewer("0.4.1", than: "0.4.1"))
        check("版本: 缺段按 0 补", !UpdateChecker.isNewer("0.4", than: "0.4.0"))
        check("版本: 旧版本不算更新", !UpdateChecker.isNewer("0.4.0", than: "0.4.1"))

        let atom = #"""
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <updated>2026-11-16T08:23:52Z</updated>
            <link rel="alternate" type="text/html" href="https://github.com/qiqiangvae/BargeIn/releases/tag/v0.5.0"/>
            <title>Barge In 0.5.0</title>
            <content type="html">&lt;p&gt;产品介绍&lt;/p&gt;
        &lt;h2&gt;变更：自动更新检查&lt;/h2&gt;
        &lt;ul&gt;&lt;li&gt;有新版时用温柔卡提醒&lt;/li&gt;&lt;/ul&gt;</content>
          </entry>
        </feed>
        """#
        let release = UpdateChecker.release(fromFeed: Data(atom.utf8))
        check("发布: 从 atom 取到版本", release?.version == "0.5.0")
        check(
            "发布: 按发布命名拼出安装包",
            release?.downloadURL.absoluteString
                == "https://github.com/qiqiangvae/BargeIn/releases/download/v0.5.0/Barge-In-0.5.0-macos-arm64.zip"
        )
        check(
            "发布: 带出发布页",
            release?.pageURL.absoluteString
                == "https://github.com/qiqiangvae/BargeIn/releases/tag/v0.5.0"
        )
        check("发布: 第一个小标题就是这次更新了什么", release?.summary == "变更：自动更新检查")
        check(
            "发布: 没有小标题就用发布名",
            UpdateChecker.summary(from: nil, title: "自动更新检查", version: "0.5.0") == "自动更新检查"
        )
        check(
            "发布: 只有版本号的标题不当作摘要",
            UpdateChecker.summary(from: nil, title: "Barge In 0.5.0", version: "0.5.0") == nil
        )
        check("发布: 坏 atom 解析为空", UpdateChecker.release(fromFeed: Data("<feed/>".utf8)) == nil)

        let suiteName = "com.bargein.selftest.updates"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)
        let store = StateStore(defaults: defaults)
        check("更新: 默认开着自动检查", store.state.checkForUpdates)
        store.set(\.checkForUpdates, false)
        store.set(\.lastNotifiedVersion, "0.5.0")
        let reloaded = StateStore(defaults: defaults)
        check(
            "更新: 开关与已通知版本都落盘",
            !reloaded.state.checkForUpdates && reloaded.state.lastNotifiedVersion == "0.5.0"
        )
        let model = SettingsModel(store: reloaded, onboarding: false)
        model.selectPage(.app)
        check("更新: 点通知卡落在通用页", model.tabIndex == SceneID.allCases.count)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 提醒层

    private static func escapeLayers(_ check: (String, Bool) -> Void) {
        let suiteName = "com.bargein.selftest.escape"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)
        let store = StateStore(defaults: defaults)

        let model = SettingsModel(store: store, onboarding: false)
        check("Esc: 场景 tab 上关窗", model.escape == .closeWindow)

        model.selectTab(SceneID.allCases.count)
        check("Esc: 通用 tab 上关窗", model.page == .app && model.escape == .closeWindow)

        model.selectTab(1)
        check("tab: 点场景回到场景页", model.page == .scene && model.selectedScene == .activity)

        model.editingID = store.activeInstance(for: .water).id
        check("Esc: 编辑面板先收", model.escape == .closeEditor)

        model.selectTab(SceneID.allCases.count)
        check("tab: 去通用页收起编辑", model.editingID == nil && model.page == .app)

        model.selectScene(.activity)
        check("Esc: 切场景收起编辑", model.editingID == nil && model.selectedScene == .activity)

        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func escapeCancel(_ check: (String, Bool) -> Void) {
        let t0 = Date()

        let locked = OverlayState(dismissDelay: 10)
        check("Esc: 解锁前单击不取消", locked.registerEscape(now: t0) == false)
        check("Esc: 解锁前快速双击取消", locked.registerEscape(now: t0.addingTimeInterval(0.4)))

        // 已解锁也一样：Esc 的中断语义不看等级与延迟。
        let unlocked = OverlayState(dismissDelay: 0)
        check("Esc: 解锁后单击也不取消", unlocked.registerEscape(now: t0) == false)
        check("Esc: 解锁后快速双击取消", unlocked.registerEscape(now: t0.addingTimeInterval(0.4)))

        let slow = OverlayState(dismissDelay: 10)
        _ = slow.registerEscape(now: t0)
        check("Esc: 两次间隔过久不算双击", slow.registerEscape(now: t0.addingTimeInterval(2)) == false)
    }

    private static func doubleReturnConfirm(_ check: (String, Bool) -> Void) {
        let t0 = Date()

        let confirm = OverlayState(dismissDelay: 0)
        check("Enter: 单击不确认", confirm.registerReturn(now: t0) == false)
        check("Enter: 快速双击确认", confirm.registerReturn(now: t0.addingTimeInterval(0.4)))
        check("Enter: 与 Esc 各记一份", confirm.registerEscape(now: t0.addingTimeInterval(0.5)) == false)

        let slowConfirm = OverlayState(dismissDelay: 0)
        _ = slowConfirm.registerReturn(now: t0)
        check("Enter: 两次间隔过久不算双击", slowConfirm.registerReturn(now: t0.addingTimeInterval(2)) == false)
    }

    /// 碎裂：裂满之后还要慢慢掉十块小碎片，落完画布才停。
    private static func shatterTimeline(_ check: (String, Bool) -> Void) {
        let fracture = Fracture.generate(seed: 20261113)
        let shed = fracture.pieces.filter { $0.shedAt != nil }
        check("碎裂: 等待期掉十块小碎片", shed.count == 10)
        check(
            "碎裂: 脱落都在裂满之后、走得比退场慢",
            shed.allSatisfy { piece in
                guard let at = piece.shedAt else { return false }
                return at > Fracture.holdAt && piece.shedDuration >= 2.4
            }
        )
        let end = shed.map { ($0.shedAt ?? 0) + $0.shedDuration }.max() ?? 0
        check("碎裂: shedEnd 是最后一块落完的时刻", abs(fracture.shedEnd - end) < 0.001)

        let randomShedCounts = [1, 42, 777].map { seed in
            Fracture.generate(seed: seed).pieces.filter { $0.shedAt != nil }.count
        }
        check("碎裂: 每次不同的花纹也掉十块", randomShedCounts.allSatisfy { $0 == 10 })
    }
}
