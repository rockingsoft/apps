import Foundation

struct MaintenanceRule: Identifiable, Hashable {
    let id: String
    let title: String
    let details: String
    let intervalMonths: Int
    let intervalKilometers: Int
}

struct MaintenanceSelection {
    let rule: MaintenanceRule
    let lastDate: Date
    let lastKilometers: Int
}

struct MaintenanceTemplate {
    let title: String
    let applicability: String
    let sourceName: String
    let sourceURL: URL
    let rules: [MaintenanceRule]

    func excluding(_ ruleIDs: Set<String>) -> MaintenanceTemplate {
        MaintenanceTemplate(title: title, applicability: applicability, sourceName: sourceName, sourceURL: sourceURL,
                            rules: rules.filter { !ruleIDs.contains($0.id) })
    }
}

enum MaintenanceCatalog {
    static func template(for car: Car) -> MaintenanceTemplate? {
        if let year = modelYear(in: car.name, brand: "VOLKSWAGEN", model: "TAOS"), (2021...2026).contains(year),
           car.name.localizedCaseInsensitiveContains("TSI") {
            return MaintenanceTemplate(
                title: "Plan base Volkswagen Taos",
                applicability: "Taos TSI \(year), uso normal. Revisá el manual de tu versión para tareas y especificaciones exactas.",
                sourceName: "Volkswagen Argentina · Libro Blanco, págs. 15–16",
                sourceURL: URL(string: "https://www.volkswagen.com.ar/idhub/content/dam/onehub_pkw/importers/ar/tengo-un-volkswagen/mantenimiento/Vw_LibroBlanco.pdf")!,
                rules: [
                    MaintenanceRule(id: "vw-taos-tsi-periodic-15000", title: "Service periódico", details: "Inspección y mantenimiento según el plan oficial. El Libro Blanco incluye aceite y filtro de aceite y filtro de aire para el servicio naftero. Confirmá los trabajos y la especificación del aceite en el manual de tu Taos.", intervalMonths: 12, intervalKilometers: 15_000),
                    MaintenanceRule(id: "vw-taos-tsi-brake-fluid-24m", title: "Líquido de frenos", details: "Volkswagen recomienda cambiar el líquido de frenos cada 2 años. Confirmá el procedimiento y el fluido con el manual o taller oficial.", intervalMonths: 24, intervalKilometers: 0)
                ]
            )
        }
        if let year = modelYear(in: car.name, brand: "TOYOTA", model: "COROLLA"), (2020...2026).contains(year) {
            return MaintenanceTemplate(
                title: "Plan base Toyota Corolla",
                applicability: "Corolla \(year), uso normal. El detalle de trabajos depende de la versión y el manual.",
                sourceName: "Toyota Argentina · Garantía y plan de mantenimiento",
                sourceURL: URL(string: "https://www.toyota.com.ar/mi-toyota/garantia")!,
                rules: [
                    MaintenanceRule(id: "toyota-corolla-periodic-10000", title: "Service periódico", details: "Toyota Argentina indica mantenimiento cada 10.000 km o 12 meses, lo que ocurra primero. Consultá el plan de tu versión para los trabajos, repuestos y lubricantes de cada visita.", intervalMonths: 12, intervalKilometers: 10_000)
                ]
            )
        }
        return nil
    }

    private static func modelYear(in carName: String, brand: String, model: String) -> Int? {
        let identity = carName.components(separatedBy: " · ").first?.uppercased() ?? ""
        let prefix = "\(brand) \(model) "
        guard identity.hasPrefix(prefix) else { return nil }
        return Int(identity.dropFirst(prefix.count).split(separator: " ").first ?? "")
    }
}
