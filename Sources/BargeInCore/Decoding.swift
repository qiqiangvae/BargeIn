import Foundation

/// 存档解码的护栏：某个字段缺失、类型不符或枚举 rawValue 不认识时，只让那一个字段回默认值，
/// 不牵连同一条记录的其它字段。以前一个字段读不出来就抛，整份 `AppState` 解码失败回出厂——
/// 用户升一次级就丢一次数据。
extension KeyedDecodingContainer {
    /// 单值：读不出来就用 fallback。
    public func tolerant<T: Decodable>(_ type: T.Type, forKey key: Key, or fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(type, forKey: key)) .flatMap { $0 } ?? fallback()
    }

    /// 可空值：读不出来就是 nil。
    public func tolerantOptional<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) .flatMap { $0 }
    }

    /// 数组：一条坏数据只丢那一条，剩下的照读。
    public func tolerantArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        ((try? decodeIfPresent([FailableDecodable<T>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? []
    }
}

/// 让数组元素的解码失败变成 nil 而不是抛错。
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
