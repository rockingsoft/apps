import AppIntents
import SwiftUI
import WidgetKit

@main struct NidoControls: WidgetBundle {
    var body: some Widget {
        ExpenseControl()
    }
}

struct ExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.schoren.garage.controls.expense") {
            ControlWidgetButton(action: CaptureExpenseIntent()) {
                Label("Dictar gasto", systemImage: "mic.fill")
            }
        }
        .displayName("Dictar gasto")
        .description("Hablá y Nido registra el gasto automáticamente.")
    }
}
