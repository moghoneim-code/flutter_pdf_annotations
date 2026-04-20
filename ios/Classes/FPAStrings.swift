import Foundation

/// Localized strings for flutter_pdf_annotations native UI.
/// Supports English (fallback), Arabic, Spanish, and Portuguese.
/// Language is resolved from the device locale automatically.
struct FPAStrings {

    /// Resolved from the device locale. Call `configure(locale:)` to override.
    private(set) static var current: FPAStrings = FPAStrings.fromDeviceLocale()

    /// Override the locale used for the editor UI.
    /// Pass `nil` to revert to the device locale.
    static func configure(locale: String?) {
        current = FPAStrings(lang: locale ?? deviceLanguage())
    }

    private static func fromDeviceLocale() -> FPAStrings {
        FPAStrings(lang: deviceLanguage())
    }

    private static func deviceLanguage() -> String {
        if #available(iOS 16, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            return (Locale.current as NSLocale).object(forKey: .languageCode) as? String ?? "en"
        }
    }

    // MARK: - Common actions
    let cancel: String
    let save: String
    let clear: String
    let back: String
    let done: String
    let confirm: String
    let delete: String
    let discard: String
    let undo: String

    // MARK: - Tool names
    let draw: String
    let erase: String
    let mark: String
    let image: String

    // MARK: - Aspect ratio
    let aspectLocked: String
    let aspectFree: String
    let aspectLockedShort: String
    let aspectFreeShort: String

    // MARK: - Alerts
    let clearAllTitle: String
    let clearAllMessage: String
    let discardImageTitle: String
    let discardImageMessage: String

    // MARK: - Status
    let saving: String
    let pdfSaved: String
    let errorBuildingPDF: String

    // MARK: - Page
    let page: String

    // MARK: - Default title
    let defaultTitle: String

    // MARK: - Helpers
    func pageLabel(current: Int, total: Int) -> String { "\(page) \(current)/\(total)" }

    // MARK: - Init
    init(lang: String) {
        switch lang {
        case "ar":
            cancel             = "إلغاء"
            save               = "حفظ"
            clear              = "مسح"
            back               = "رجوع"
            done               = "تم"
            confirm            = "تأكيد"
            delete             = "حذف"
            discard            = "تجاهل"
            undo               = "تراجع"
            draw               = "رسم"
            erase              = "ممحاة"
            mark               = "تمييز"
            image              = "صورة"
            aspectLocked       = "النسبة: مقفلة"
            aspectFree         = "النسبة: حرة"
            aspectLockedShort  = "مقفلة"
            aspectFreeShort    = "حرة"
            clearAllTitle      = "مسح الكل؟"
            clearAllMessage    = "سيتم حذف جميع التعليقات التوضيحية."
            discardImageTitle  = "تجاهل الصورة؟"
            discardImageMessage = "يوجد موضع صورة غير مؤكد."
            saving             = "جاري الحفظ..."
            pdfSaved           = "!تم حفظ PDF"
            errorBuildingPDF   = "خطأ في بناء PDF"
            page               = "صفحة"
            defaultTitle       = "تعليقات PDF"

        case "es":
            cancel             = "Cancelar"
            save               = "Guardar"
            clear              = "Borrar"
            back               = "Volver"
            done               = "Listo"
            confirm            = "Confirmar"
            delete             = "Eliminar"
            discard            = "Descartar"
            undo               = "Deshacer"
            draw               = "Dibujar"
            erase              = "Borrador"
            mark               = "Marcar"
            image              = "Imagen"
            aspectLocked       = "Relación: Bloqueada"
            aspectFree         = "Relación: Libre"
            aspectLockedShort  = "Bloqueada"
            aspectFreeShort    = "Libre"
            clearAllTitle      = "¿Borrar todo?"
            clearAllMessage    = "Se eliminarán todas las anotaciones."
            discardImageTitle  = "¿Descartar imagen?"
            discardImageMessage = "Hay una imagen sin confirmar."
            saving             = "Guardando..."
            pdfSaved           = "¡PDF guardado!"
            errorBuildingPDF   = "Error al generar el PDF"
            page               = "Página"
            defaultTitle       = "Anotaciones PDF"

        case "pt":
            cancel             = "Cancelar"
            save               = "Salvar"
            clear              = "Limpar"
            back               = "Voltar"
            done               = "Concluir"
            confirm            = "Confirmar"
            delete             = "Excluir"
            discard            = "Descartar"
            undo               = "Desfazer"
            draw               = "Desenhar"
            erase              = "Borracha"
            mark               = "Marcar"
            image              = "Imagem"
            aspectLocked       = "Proporção: Travada"
            aspectFree         = "Proporção: Livre"
            aspectLockedShort  = "Travada"
            aspectFreeShort    = "Livre"
            clearAllTitle      = "Limpar tudo?"
            clearAllMessage    = "Todas as anotações serão removidas."
            discardImageTitle  = "Descartar imagem?"
            discardImageMessage = "Há uma imagem não confirmada."
            saving             = "Salvando..."
            pdfSaved           = "PDF salvo!"
            errorBuildingPDF   = "Erro ao gerar o PDF"
            page               = "Página"
            defaultTitle       = "Anotações de PDF"

        default: // "en" and all unsupported — English fallback
            cancel             = "Cancel"
            save               = "Save"
            clear              = "Clear"
            back               = "Back"
            done               = "Done"
            confirm            = "Confirm"
            delete             = "Delete"
            discard            = "Discard"
            undo               = "Undo"
            draw               = "Draw"
            erase              = "Erase"
            mark               = "Mark"
            image              = "Image"
            aspectLocked       = "Aspect: Locked"
            aspectFree         = "Aspect: Free"
            aspectLockedShort  = "Locked"
            aspectFreeShort    = "Free"
            clearAllTitle      = "Clear All?"
            clearAllMessage    = "This will remove all annotations."
            discardImageTitle  = "Discard Image?"
            discardImageMessage = "You have an unconfirmed image placement."
            saving             = "Saving..."
            pdfSaved           = "PDF saved!"
            errorBuildingPDF   = "Error building PDF"
            page               = "Page"
            defaultTitle       = "PDF Annotations"
        }
    }
}
