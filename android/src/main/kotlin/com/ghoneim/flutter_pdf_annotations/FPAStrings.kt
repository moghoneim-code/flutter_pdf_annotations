package com.ghoneim.flutter_pdf_annotations

import java.util.Locale

/**
 * Localized strings for flutter_pdf_annotations native UI.
 * Supports English (fallback), Arabic, Spanish, and Portuguese.
 * Language is resolved from the device locale automatically.
 */
object FPAStrings {

    private val lang: String get() = Locale.getDefault().language

    // MARK: - Common actions
    val cancel:  String get() = str("Cancel",  "إلغاء",   "Cancelar",  "Cancelar")
    val save:    String get() = str("Save",    "حفظ",     "Guardar",   "Salvar")
    val clear:   String get() = str("Clear",   "مسح",     "Borrar",    "Limpar")
    val back:    String get() = str("Back",    "رجوع",    "Volver",    "Voltar")
    val done:    String get() = str("Done",    "تم",      "Listo",     "Concluir")
    val confirm: String get() = str("Confirm", "تأكيد",   "Confirmar", "Confirmar")
    val delete:  String get() = str("Delete",  "حذف",     "Eliminar",  "Excluir")
    val discard: String get() = str("Discard", "تجاهل",   "Descartar", "Descartar")
    val undo:    String get() = str("Undo",    "تراجع",   "Deshacer",  "Desfazer")

    // MARK: - Tool names
    val draw:  String get() = str("Draw",  "رسم",    "Dibujar",  "Desenhar")
    val erase: String get() = str("Erase", "ممحاة",  "Borrador", "Borracha")
    val mark:  String get() = str("Mark",  "تمييز",  "Marcar",   "Marcar")
    val image: String get() = str("Image", "صورة",   "Imagen",   "Imagem")

    // MARK: - Aspect ratio
    val aspectLocked: String get() = str("Aspect: Locked",    "النسبة: مقفلة",     "Relación: Bloqueada", "Proporção: Travada")
    val aspectFree:   String get() = str("Aspect: Free",      "النسبة: حرة",       "Relación: Libre",     "Proporção: Livre")

    // MARK: - Alerts
    val clearAllTitle:       String get() = str("Clear All?",                       "مسح الكل؟",                             "¿Borrar todo?",          "Limpar tudo?")
    val clearAllMessage:     String get() = str("This will remove all annotations.", "سيتم حذف جميع التعليقات التوضيحية.",   "Se eliminarán todas las anotaciones.", "Todas as anotações serão removidas.")
    val discardImageTitle:   String get() = str("Discard Image?",                   "تجاهل الصورة؟",                         "¿Descartar imagen?",     "Descartar imagem?")
    val discardImageMessage: String get() = str("You have an unconfirmed image placement.", "يوجد موضع صورة غير مؤكد.",     "Hay una imagen sin confirmar.", "Há uma imagem não confirmada.")

    // MARK: - Status
    val saving:          String get() = str("Saving...",          "جاري الحفظ...", "Guardando...",           "Salvando...")
    val pdfSaved:        String get() = str("PDF saved!",         "!تم حفظ PDF",   "¡PDF guardado!",         "PDF salvo!")
    val errorBuildingPDF: String get() = str("Error building PDF", "خطأ في بناء PDF", "Error al generar el PDF", "Erro ao gerar o PDF")

    // MARK: - Page / title
    val page:         String get() = str("Page",             "صفحة",          "Página",          "Página")
    val defaultTitle: String get() = str("PDF Annotations",  "تعليقات PDF",   "Anotaciones PDF", "Anotações de PDF")

    // MARK: - Helpers
    fun pageLabel(current: Int, total: Int) = "$page $current/$total"

    private fun str(en: String, ar: String, es: String, pt: String): String = when (lang) {
        "ar" -> ar
        "es" -> es
        "pt" -> pt
        else -> en
    }
}
