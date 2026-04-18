//
//  CompanyConfig.swift
//  leanring-buddy
//

import Foundation

struct CompanyConfig: Codable {
    let company_id: String
    let company_name: String
    let rag_service_url: String
    let api_key: String
}

class CompanyConfigManager {
    private static let userDefaultsKey = "companyConfig"

    static func loadConfig() -> CompanyConfig? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(CompanyConfig.self, from: data)
    }

    static func saveConfig(_ config: CompanyConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    static func clearConfig() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    static func loadFromFile(at url: URL) -> CompanyConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CompanyConfig.self, from: data)
    }
}
