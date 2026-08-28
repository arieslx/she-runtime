//
//  CopyProvider.swift
//  sheRuntime
//
//  多语言文案读取工具。
//  - 文案存在 Resources/copy_zh.json 和 copy_en.json（键结构相同）。
//  - 按系统语言取文案；如果目标语言该条为空，自动回退到中文。
//  - 产品/文案(小花)以后改字，只改 JSON，不碰代码。
//  - 现在只填了中文；英文文件已留好同样的键，等以后翻译。
//

import Foundation

enum AppLanguage: String {
    case zh, en
    static var current: AppLanguage {
        if let override = ProcessInfo.processInfo.environment["APP_LANGUAGE"],
           let language = AppLanguage(rawValue: override) {
            return language
        }
        let code = Locale.preferredLanguages.first ?? "zh"
        return code.hasPrefix("en") ? .en : .zh
    }
}

struct CopyProvider {
    static let shared = CopyProvider()

    private let primary: [String: Any]   // 当前语言
    private let fallback: [String: Any]  // 中文兜底

    private init() {
        func load(_ name: String) -> [String: Any] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            return obj
        }
        let zh = load("copy_zh")
        primary = AppLanguage.current == .en ? load("copy_en") : zh
        fallback = zh
    }

    /// 用点路径取文案，如 t("today.heroCopy")。空值自动回退中文。
    func t(_ path: String) -> String {
        if let v = value(in: primary, path: path), !v.isEmpty { return v }
        return value(in: fallback, path: path) ?? path
    }

    private func value(in dict: [String: Any], path: String) -> String? {
        var node: Any? = dict
        for key in path.split(separator: ".") {
            node = (node as? [String: Any])?[String(key)]
        }
        return node as? String
    }
}

// 简写：C.t("today.title")
typealias C = CopyProvider
extension CopyProvider { static func t(_ p: String) -> String { shared.t(p) } }
