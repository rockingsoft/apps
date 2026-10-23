import Foundation

struct MaintenanceRule: Identifiable, Hashable {
    let id: String
    let title: String
    let details: String
    let intervalMonths: Int
    let intervalKilometers: Int
    var sourceName: String? = nil
    var sourceURL: URL? = nil
    var initiallySelected = true
}

struct MaintenanceSelection {
    let rule: MaintenanceRule
    let lastDate: Date
    let lastKilometers: Int
    let baselineUnknown: Bool
}

struct MaintenanceTemplate: Identifiable {
    var id: String { sourceURL.absoluteString + ":" + rules.map(\.id).joined(separator: ",") }
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
    private static let taosManual = URL(string: "https://www.volkswagen.com.ar/idhub/content/dam/onehub_pkw/importers/ar/tengo-un-volkswagen/manuales/manuales/2023/Manual-Taos_2023-04.pdf")!
    private static let toyotaCare = URL(string: "https://landings.toyota.com.ar/manuales/MANUAL.pdf")!
    private static let tirePressure = URL(string: "https://www.michelin.com.ar/auto/faq-cars")!
    private static let tireRotation = URL(string: "https://www.michelin.com.ar/auto/consejos/cuidado-de-los-neumaticos/rotacion-de-neumaticos")!
    private static let wipers = URL(string: "https://am.boschcarservice.com/co/es/consejos/limpiaparabrisas/")!

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
                    MaintenanceRule(id: "vw-taos-tsi-brake-fluid-24m", title: "Cambiar líquido de frenos", details: "Volkswagen recomienda cambiar el líquido de frenos cada 2 años. Confirmá el procedimiento y el fluido con el manual o taller oficial.", intervalMonths: 24, intervalKilometers: 0)
                ] + additionalRules(serviceKilometers: 15_000, maker: "vw-taos", manualName: "Manual Volkswagen Taos 2023", manualURL: taosManual)
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
                ] + additionalRules(serviceKilometers: 10_000, maker: "toyota-corolla", manualName: "Toyota Argentina · cuidados y mantenimiento", manualURL: toyotaCare)
            )
        }
        return nil
    }

    private static func additionalRules(serviceKilometers km: Int, maker: String, manualName: String, manualURL: URL) -> [MaintenanceRule] {
        func inspection(_ id: String, _ title: String, _ details: String) -> MaintenanceRule {
            MaintenanceRule(id: "\(maker)-\(id)", title: title, details: "Revisión sugerida en cada service. \(details)",
                            intervalMonths: 12, intervalKilometers: km, sourceName: manualName,
                            sourceURL: manualURL, initiallySelected: false)
        }
        return [
            MaintenanceRule(id: "common-tire-pressure-monthly", title: "Revisar presión de cubiertas", details: "Controlá en frío las cuatro cubiertas y la de auxilio, si tiene. Usá la presión indicada por el fabricante del auto. Michelin recomienda al menos una revisión mensual y antes de viajes largos.", intervalMonths: 1, intervalKilometers: 0, sourceName: "Michelin Argentina · presión", sourceURL: tirePressure, initiallySelected: false),
            MaintenanceRule(id: "common-tire-rotation-10000", title: "Rotar cubiertas", details: "Michelin sugiere aproximadamente cada 8.000–10.000 km. Respetá el patrón del manual y verificá que las medidas y el tipo de cubiertas permitan rotarlas.", intervalMonths: 0, intervalKilometers: 10_000, sourceName: "Michelin Argentina · rotación", sourceURL: tireRotation, initiallySelected: false),
            inspection("tire-condition", "Revisar desgaste de cubiertas", "Comprobá dibujo, cortes, deformaciones y desgaste desigual; revisá también el auxilio. Cambiá las cubiertas según su estado, no por un kilometraje fijo."),
            MaintenanceRule(id: "common-wipers-12m", title: "Cambiar escobillas limpiaparabrisas", details: "Bosch recomienda cambiarlas al menos una vez al año; adelantá el cambio si dejan vetas, hacen ruido o la goma está dañada. Revisá también el lavaparabrisas.", intervalMonths: 12, intervalKilometers: 0, sourceName: "Bosch Car Service · limpiaparabrisas", sourceURL: wipers, initiallySelected: false),
            inspection("brakes", "Revisar frenos", "Inspeccioná pastillas, discos, mangueras y funcionamiento. Cambiá las piezas por desgaste o indicación del taller, sin esperar un vencimiento fijo."),
            inspection("transmission-fluid", "Revisar aceite de caja", "Pedí controlar pérdidas, estado y mantenimiento de la transmisión. El cambio de aceite o fluido y su especificación dependen de la caja exacta y del manual; esta alerta no indica reemplazarlo automáticamente."),
            inspection("engine-air-filter", "Revisar filtro de aire del motor", "Inspeccioná suciedad y obstrucciones; sustituí según el plan de la versión o antes si circulás en zonas con mucho polvo."),
            inspection("cabin-filter", "Revisar filtro de habitáculo", "Comprobá el filtro de aire del climatizador y cambialo según el manual o si está obstruido."),
            inspection("cooling", "Revisar refrigerante y mangueras", "Comprobá nivel, pérdidas, radiador y mangueras con el motor frío. El intervalo de cambio y el producto dependen de la versión."),
            inspection("belts", "Revisar correas", "Controlá desgaste, grietas y tensión de correas auxiliares. Verificá en el manual si tu motor tiene correa de distribución y su intervalo específico."),
            inspection("battery", "Revisar batería", "Comprobá estado, bornes y capacidad de arranque, especialmente antes del invierno. Cambiala según diagnóstico."),
            inspection("lights-washer", "Revisar luces y lavaparabrisas", "Probá luces, señalización, bocina y rociadores; reponé líquido y repará fallas cuando aparezcan."),
            inspection("suspension-steering", "Revisar dirección y suspensión", "Controlá amortiguadores, rótulas, bujes, guardapolvos y alineación si hay vibraciones, tironeo o desgaste irregular."),
            inspection("ac", "Revisar climatización", "Comprobá aire acondicionado, calefacción y desempañado; repará fugas o falta de rendimiento según diagnóstico.")
        ]
    }

    private static func modelYear(in carName: String, brand: String, model: String) -> Int? {
        let identity = carName.components(separatedBy: " · ").first?.uppercased() ?? ""
        let prefix = "\(brand) \(model) "
        guard identity.hasPrefix(prefix) else { return nil }
        return Int(identity.dropFirst(prefix.count).split(separator: " ").first ?? "")
    }
}
