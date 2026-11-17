// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// The rules keep their machine-readable form in `rules.json`; their words
/// live here, keyed by rule id, so adding a language never touches a regex.
///
/// The Turkish text in `rules.json` stays the fallback, which means a rule added
/// without a translation still reads correctly instead of showing an id.
public struct RuleText: Sendable {
    public let title: String
    public let message: String
}

public enum RuleLocalization {
    public static func text(forRule id: String, language: AppLanguage) -> RuleText? {
        allEntries[id]?[language == .system ? .english : language]
    }

    /// Built-in rules from the first release; the rest live in
    /// `RuleLocalization+Added.swift` so neither table grows past a screenful of review.
    static let allEntries = entries.merging(addedEntries) { first, _ in first }

    static let entries: [String: [AppLanguage: RuleText]] = [
        "R1": [
            .english: RuleText(
                title: "Destructive delete",
                message: "An irreversible delete aimed at the home folder, a top-level folder or the root of "
                    + "the file system"),
            .turkish: RuleText(
                title: "Yıkıcı silme",
                message: "Ev dizinini, bir üst düzey klasörü veya dosya sisteminin kökünü hedefleyen geri "
                    + "dönüşsüz silme"),
            .german: RuleText(
                title: "Destruktives Löschen",
                message: "Unwiderrufliches Löschen, das auf das Home-Verzeichnis, einen Ordner der obersten "
                    + "Ebene oder die Wurzel des Dateisystems zielt"),
            .spanish: RuleText(
                title: "Borrado destructivo",
                message: "Borrado irreversible dirigido a la carpeta personal, a una carpeta de primer nivel "
                    + "o a la raíz del sistema"),
            .italian: RuleText(
                title: "Cancellazione distruttiva",
                message: "Cancellazione irreversibile diretta alla cartella personale, a una cartella di "
                    + "primo livello o alla radice del filesystem"),
            .french: RuleText(
                title: "Suppression destructive",
                message: "Suppression irréversible visant le dossier personnel, un dossier de premier niveau "
                    + "ou la racine du système")
        ],
        "R2": [
            .english: RuleText(
                title: "Download and run",
                message: "Remote content is piped straight into a shell or an interpreter"),
            .turkish: RuleText(
                title: "İndirip çalıştırma",
                message: "Uzaktan indirilen içerik doğrudan kabuğa veya yorumlayıcıya veriliyor"),
            .german: RuleText(
                title: "Herunterladen und ausführen",
                message: "Remote-Inhalt wird direkt in eine Shell oder einen Interpreter geleitet"),
            .spanish: RuleText(
                title: "Descargar y ejecutar",
                message: "El contenido remoto se envía directamente a un shell o a un intérprete"),
            .italian: RuleText(
                title: "Scarica ed esegui",
                message: "Il contenuto remoto finisce direttamente in una shell o in un interprete"),
            .french: RuleText(
                title: "Télécharger et exécuter",
                message: "Le contenu distant part directement dans un shell ou un interpréteur")
        ],
        "R3": [
            .english: RuleText(
                title: "Privilege escalation",
                message: "The command runs with administrator rights"),
            .turkish: RuleText(
                title: "Yükseltilmiş yetki",
                message: "Komut yönetici yetkisiyle çalışıyor"),
            .german: RuleText(
                title: "Rechteausweitung",
                message: "Der Befehl läuft mit Administratorrechten"),
            .spanish: RuleText(
                title: "Escalada de privilegios",
                message: "El comando se ejecuta con permisos de administrador"),
            .italian: RuleText(
                title: "Escalation di privilegi",
                message: "Il comando gira con i permessi di amministratore"),
            .french: RuleText(
                title: "Élévation de privilèges",
                message: "La commande s'exécute avec les droits d'administrateur")
        ],
        "R4": [
            .english: RuleText(
                title: "Secret file access",
                message: "A file that may hold credentials or a private key"),
            .turkish: RuleText(
                title: "Sır dosyası erişimi",
                message: "Kimlik bilgisi veya özel anahtar içerebilecek dosya"),
            .german: RuleText(
                title: "Zugriff auf Secret-Dateien",
                message: "Eine Datei, die Zugangsdaten oder einen privaten Schlüssel enthalten kann"),
            .spanish: RuleText(
                title: "Acceso a archivos de secretos",
                message: "Un archivo que puede contener credenciales o una clave privada"),
            .italian: RuleText(
                title: "Accesso a file di segreti",
                message: "Un file che può contenere credenziali o una chiave privata"),
            .french: RuleText(
                title: "Accès aux fichiers de secrets",
                message: "Un fichier susceptible de contenir des identifiants ou une clé privée")
        ],
        "R5": [
            .english: RuleText(
                title: "Force push",
                message: "Can rewrite remote history with no way back"),
            .turkish: RuleText(
                title: "Force push",
                message: "Uzak geçmişi geri dönüşsüz değiştirebilir"),
            .german: RuleText(
                title: "Force-Push",
                message: "Kann die Historie im Remote unwiderruflich überschreiben"),
            .spanish: RuleText(
                title: "Force push",
                message: "Puede reescribir el historial remoto sin vuelta atrás"),
            .italian: RuleText(
                title: "Force push",
                message: "Può riscrivere la cronologia remota senza ritorno"),
            .french: RuleText(
                title: "Force push",
                message: "Peut réécrire l'historique distant sans retour possible")
        ],
        "R6": [
            .english: RuleText(
                title: "Permission change",
                message: "File permissions are being widened"),
            .turkish: RuleText(
                title: "İzin değişikliği",
                message: "Dosya izinleri genişletiliyor"),
            .german: RuleText(
                title: "Rechteänderung",
                message: "Dateiberechtigungen werden ausgeweitet"),
            .spanish: RuleText(
                title: "Cambio de permisos",
                message: "Se amplían los permisos de archivo"),
            .italian: RuleText(
                title: "Modifica dei permessi",
                message: "I permessi dei file vengono allargati"),
            .french: RuleText(
                title: "Changement de permissions",
                message: "Les permissions de fichiers sont élargies")
        ],
        "R7": [
            .english: RuleText(
                title: "Data upload",
                message: "Local file content is sent over the network"),
            .turkish: RuleText(
                title: "Veri gönderimi",
                message: "Yerel dosya içeriği ağ üzerinden gönderiliyor"),
            .german: RuleText(
                title: "Datenupload",
                message: "Lokaler Dateiinhalt wird über das Netz gesendet"),
            .spanish: RuleText(
                title: "Envío de datos",
                message: "El contenido de un archivo local se envía por la red"),
            .italian: RuleText(
                title: "Invio di dati",
                message: "Il contenuto di un file locale viene inviato sulla rete"),
            .french: RuleText(
                title: "Envoi de données",
                message: "Le contenu d'un fichier local est envoyé sur le réseau")
        ],
        "R8": [
            .english: RuleText(
                title: "Privileged container",
                message: "The container is attached to the host with broad rights"),
            .turkish: RuleText(
                title: "Ayrıcalıklı konteyner",
                message: "Konteyner ana makine kaynaklarına geniş yetkiyle bağlanıyor"),
            .german: RuleText(
                title: "Privilegierter Container",
                message: "Der Container hängt mit weitreichenden Rechten am Host"),
            .spanish: RuleText(
                title: "Contenedor privilegiado",
                message: "El contenedor se conecta al host con permisos amplios"),
            .italian: RuleText(
                title: "Container privilegiato",
                message: "Il container è collegato all'host con permessi ampi"),
            .french: RuleText(
                title: "Conteneur privilégié",
                message: "Le conteneur est relié à l'hôte avec des droits étendus")
        ],
        "R9": [
            .english: RuleText(
                title: "Write outside the workspace",
                message: "Writing outside the project and the user's space, into system folders"),
            .turkish: RuleText(
                title: "Çalışma dizini dışına yazma",
                message: "Proje dizininin ve kullanıcı alanının dışına, sistem klasörlerine yazılıyor"),
            .german: RuleText(
                title: "Schreiben außerhalb des Arbeitsordners",
                message: "Es wird außerhalb des Projekts und des Benutzerbereichs in Systemordner geschrieben"),
            .spanish: RuleText(
                title: "Escritura fuera del proyecto",
                message: "Se escribe fuera del proyecto y del espacio del usuario, en carpetas del sistema"),
            .italian: RuleText(
                title: "Scrittura fuori dal progetto",
                message: "Si scrive fuori dal progetto e dallo spazio dell'utente, in cartelle di sistema"),
            .french: RuleText(
                title: "Écriture hors du projet",
                message: "Écriture en dehors du projet et de l'espace de l'utilisateur, dans des dossiers système")
        ],
        "R10": [
            .english: RuleText(
                title: "Irreversible git operation",
                message: "Untracked files or local changes are deleted for good"),
            .turkish: RuleText(
                title: "Geri dönüşsüz git işlemi",
                message: "İzlenmeyen dosyalar veya yerel değişiklikler geri alınamaz şekilde siliniyor"),
            .german: RuleText(
                title: "Unwiderrufliche Git-Operation",
                message: "Nicht versionierte Dateien oder lokale Änderungen werden endgültig gelöscht"),
            .spanish: RuleText(
                title: "Operación de git irreversible",
                message: "Se borran sin remedio archivos sin seguimiento o cambios locales"),
            .italian: RuleText(
                title: "Operazione git irreversibile",
                message: "File non tracciati o modifiche locali vengono eliminati per sempre"),
            .french: RuleText(
                title: "Opération git irréversible",
                message: "Des fichiers non suivis ou des modifications locales sont supprimés définitivement")
        ]
    ]
}

public extension Rule {
    func localizedTitle(_ localizer: Localizer) -> String {
        RuleLocalization.text(forRule: id, language: localizer.language)?.title ?? title
    }

    func localizedMessage(_ localizer: Localizer) -> String {
        RuleLocalization.text(forRule: id, language: localizer.language)?.message ?? message
    }
}
