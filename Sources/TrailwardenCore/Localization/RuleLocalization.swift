// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// The rules keep their machine-readable form in `rules.json`; their words
/// live here, keyed by rule id, so adding a language never touches a regex.
///
/// The Turkish text in `rules.json` stays the fallback, which means a rule added
/// without a translation still reads correctly instead of showing an id.
public struct RuleText: Sendable {
    public let title: String
    public let message: String
    /// What happens, in one plain sentence (at most 60 characters).
    public let consequence: String
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
                    + "the file system",
                consequence: "Deletes your whole home folder or a system folder"),
            .turkish: RuleText(
                title: "Yıkıcı silme",
                message: "Ev dizinini, bir üst düzey klasörü veya dosya sisteminin kökünü hedefleyen geri "
                    + "dönüşsüz silme",
                consequence: "Ev klasörünü veya bir sistem klasörünü siler"),
            .german: RuleText(
                title: "Destruktives Löschen",
                message: "Unwiderrufliches Löschen, das auf das Home-Verzeichnis, einen Ordner der obersten "
                    + "Ebene oder die Wurzel des Dateisystems zielt",
                consequence: "Löscht Ihren Home-Ordner oder einen Systemordner"),
            .spanish: RuleText(
                title: "Borrado destructivo",
                message: "Borrado irreversible dirigido a la carpeta personal, a una carpeta de primer nivel "
                    + "o a la raíz del sistema",
                consequence: "Borra tu carpeta personal o una carpeta del sistema"),
            .italian: RuleText(
                title: "Cancellazione distruttiva",
                message: "Cancellazione irreversibile diretta alla cartella personale, a una cartella di "
                    + "primo livello o alla radice del filesystem",
                consequence: "Cancella la tua cartella personale o di sistema"),
            .french: RuleText(
                title: "Suppression destructive",
                message: "Suppression irréversible visant le dossier personnel, un dossier de premier niveau "
                    + "ou la racine du système",
                consequence: "Supprime votre dossier personnel ou un dossier système")
        ],
        "R2": [
            .english: RuleText(
                title: "Download and run",
                message: "Remote content is piped straight into a shell or an interpreter",
                consequence: "Runs code downloaded from the internet"),
            .turkish: RuleText(
                title: "İndirip çalıştırma",
                message: "Uzaktan indirilen içerik doğrudan kabuğa veya yorumlayıcıya veriliyor",
                consequence: "İnternetten indirilen kodu çalıştırır"),
            .german: RuleText(
                title: "Herunterladen und ausführen",
                message: "Remote-Inhalt wird direkt in eine Shell oder einen Interpreter geleitet",
                consequence: "Führt aus dem Internet geladenen Code aus"),
            .spanish: RuleText(
                title: "Descargar y ejecutar",
                message: "El contenido remoto se envía directamente a un shell o a un intérprete",
                consequence: "Ejecuta código descargado de internet"),
            .italian: RuleText(
                title: "Scarica ed esegui",
                message: "Il contenuto remoto finisce direttamente in una shell o in un interprete",
                consequence: "Esegue codice scaricato da internet"),
            .french: RuleText(
                title: "Télécharger et exécuter",
                message: "Le contenu distant part directement dans un shell ou un interpréteur",
                consequence: "Exécute du code téléchargé sur internet")
        ],
        "R3": [
            .english: RuleText(
                title: "Privilege escalation",
                message: "The command runs with administrator rights",
                consequence: "Runs a command with administrator rights"),
            .turkish: RuleText(
                title: "Yükseltilmiş yetki",
                message: "Komut yönetici yetkisiyle çalışıyor",
                consequence: "Bir komutu yönetici yetkisiyle çalıştırır"),
            .german: RuleText(
                title: "Rechteausweitung",
                message: "Der Befehl läuft mit Administratorrechten",
                consequence: "Führt einen Befehl mit Administratorrechten aus"),
            .spanish: RuleText(
                title: "Escalada de privilegios",
                message: "El comando se ejecuta con permisos de administrador",
                consequence: "Ejecuta un comando como administrador"),
            .italian: RuleText(
                title: "Escalation di privilegi",
                message: "Il comando gira con i permessi di amministratore",
                consequence: "Esegue un comando da amministratore"),
            .french: RuleText(
                title: "Élévation de privilèges",
                message: "La commande s'exécute avec les droits d'administrateur",
                consequence: "Exécute une commande en administrateur")
        ],
        "R4": [
            .english: RuleText(
                title: "Secret file access",
                message: "A file that may hold credentials or a private key",
                consequence: "Reads a file that may hold passwords or keys"),
            .turkish: RuleText(
                title: "Sır dosyası erişimi",
                message: "Kimlik bilgisi veya özel anahtar içerebilecek dosya",
                consequence: "Parola veya anahtar içerebilen bir dosyayı okur"),
            .german: RuleText(
                title: "Zugriff auf Secret-Dateien",
                message: "Eine Datei, die Zugangsdaten oder einen privaten Schlüssel enthalten kann",
                consequence: "Liest eine Datei mit möglichen Passwörtern oder Schlüsseln"),
            .spanish: RuleText(
                title: "Acceso a archivos de secretos",
                message: "Un archivo que puede contener credenciales o una clave privada",
                consequence: "Lee un archivo con posibles contraseñas o claves"),
            .italian: RuleText(
                title: "Accesso a file di segreti",
                message: "Un file che può contenere credenziali o una chiave privata",
                consequence: "Legge un file con possibili password o chiavi"),
            .french: RuleText(
                title: "Accès aux fichiers de secrets",
                message: "Un fichier susceptible de contenir des identifiants ou une clé privée",
                consequence: "Lit un fichier pouvant contenir mots de passe ou clés")
        ],
        "R5": [
            .english: RuleText(
                title: "Force push",
                message: "Rewrites or deletes a shared branch (main, release…) on the remote, with no way "
                    + "back",
                consequence: "Overwrites a shared branch online for everyone"),
            .turkish: RuleText(
                title: "Force push",
                message: "Uzaktaki ortak bir dalı (main, release…) geri dönüşsüz yeniden yazıyor veya "
                    + "siliyor",
                consequence: "Ortak bir dalı herkes için internette ezer"),
            .german: RuleText(
                title: "Force-Push",
                message: "Überschreibt oder löscht einen gemeinsamen Branch (main, release…) im Remote "
                    + "unwiderruflich",
                consequence: "Überschreibt einen gemeinsamen Branch für alle online"),
            .spanish: RuleText(
                title: "Force push",
                message: "Reescribe o borra una rama compartida (main, release…) en el remoto sin vuelta "
                    + "atrás",
                consequence: "Sobrescribe una rama compartida para todos"),
            .italian: RuleText(
                title: "Force push",
                message: "Riscrive o elimina un ramo condiviso (main, release…) sul remoto senza ritorno",
                consequence: "Sovrascrive online un branch condiviso per tutti"),
            .french: RuleText(
                title: "Force push",
                message: "Réécrit ou supprime une branche partagée (main, release…) sur le distant sans "
                    + "retour possible",
                consequence: "Écrase en ligne une branche partagée pour tous")
        ],
        "R6": [
            .english: RuleText(
                title: "Permission change",
                message: "File permissions are being widened",
                consequence: "Lets more people read or change a file"),
            .turkish: RuleText(
                title: "İzin değişikliği",
                message: "Dosya izinleri genişletiliyor",
                consequence: "Bir dosyayı daha çok kişinin okumasına izin verir"),
            .german: RuleText(
                title: "Rechteänderung",
                message: "Dateiberechtigungen werden ausgeweitet",
                consequence: "Erlaubt mehr Personen, eine Datei zu lesen oder zu ändern"),
            .spanish: RuleText(
                title: "Cambio de permisos",
                message: "Se amplían los permisos de archivo",
                consequence: "Permite que más gente lea o cambie un archivo"),
            .italian: RuleText(
                title: "Modifica dei permessi",
                message: "I permessi dei file vengono allargati",
                consequence: "Permette a più persone di leggere o modificare un file"),
            .french: RuleText(
                title: "Changement de permissions",
                message: "Les permissions de fichiers sont élargies",
                consequence: "Permet à plus de monde de lire ou modifier un fichier")
        ],
        "R7": [
            .english: RuleText(
                title: "Data upload",
                message: "A credential or secret file is sent over the network",
                consequence: "Sends a secret file to another computer"),
            .turkish: RuleText(
                title: "Veri gönderimi",
                message: "Kimlik bilgisi veya sır içeren bir dosya ağ üzerinden gönderiliyor",
                consequence: "Gizli bir dosyayı başka bir bilgisayara gönderir"),
            .german: RuleText(
                title: "Datenupload",
                message: "Eine Datei mit Zugangsdaten oder Geheimnissen wird über das Netz gesendet",
                consequence: "Sendet eine geheime Datei an einen anderen Computer"),
            .spanish: RuleText(
                title: "Envío de datos",
                message: "Se envía por la red un archivo con credenciales o secretos",
                consequence: "Envía un archivo secreto a otro ordenador"),
            .italian: RuleText(
                title: "Invio di dati",
                message: "Un file con credenziali o segreti viene inviato sulla rete",
                consequence: "Invia un file segreto a un altro computer"),
            .french: RuleText(
                title: "Envoi de données",
                message: "Un fichier d'identifiants ou de secrets est envoyé sur le réseau",
                consequence: "Envoie un fichier secret vers un autre ordinateur")
        ],
        "R8": [
            .english: RuleText(
                title: "Privileged container",
                message: "The container is attached to the host with broad rights",
                consequence: "Gives a container wide access to your Mac"),
            .turkish: RuleText(
                title: "Ayrıcalıklı konteyner",
                message: "Konteyner ana makine kaynaklarına geniş yetkiyle bağlanıyor",
                consequence: "Bir konteynere Mac'inize geniş erişim verir"),
            .german: RuleText(
                title: "Privilegierter Container",
                message: "Der Container hängt mit weitreichenden Rechten am Host",
                consequence: "Gibt einem Container weiten Zugriff auf Ihren Mac"),
            .spanish: RuleText(
                title: "Contenedor privilegiado",
                message: "El contenedor se conecta al host con permisos amplios",
                consequence: "Da a un contenedor acceso amplio a tu Mac"),
            .italian: RuleText(
                title: "Container privilegiato",
                message: "Il container è collegato all'host con permessi ampi",
                consequence: "Dà a un container ampio accesso al tuo Mac"),
            .french: RuleText(
                title: "Conteneur privilégié",
                message: "Le conteneur est relié à l'hôte avec des droits étendus",
                consequence: "Donne à un conteneur un large accès à votre Mac")
        ],
        "R9": [
            .english: RuleText(
                title: "Write outside the workspace",
                message: "Writing outside the project and the user's space, into system folders",
                consequence: "Writes files into system folders"),
            .turkish: RuleText(
                title: "Çalışma dizini dışına yazma",
                message: "Proje dizininin ve kullanıcı alanının dışına, sistem klasörlerine yazılıyor",
                consequence: "Sistem klasörlerine dosya yazar"),
            .german: RuleText(
                title: "Schreiben außerhalb des Arbeitsordners",
                message: "Es wird außerhalb des Projekts und des Benutzerbereichs in Systemordner geschrieben",
                consequence: "Schreibt Dateien in Systemordner"),
            .spanish: RuleText(
                title: "Escritura fuera del proyecto",
                message: "Se escribe fuera del proyecto y del espacio del usuario, en carpetas del sistema",
                consequence: "Escribe archivos en carpetas del sistema"),
            .italian: RuleText(
                title: "Scrittura fuori dal progetto",
                message: "Si scrive fuori dal progetto e dallo spazio dell'utente, in cartelle di sistema",
                consequence: "Scrive file nelle cartelle di sistema"),
            .french: RuleText(
                title: "Écriture hors du projet",
                message: "Écriture en dehors du projet et de l'espace de l'utilisateur, dans des dossiers système",
                consequence: "Écrit des fichiers dans les dossiers système")
        ],
        "R10": [
            .english: RuleText(
                title: "Irreversible git operation",
                message: "Untracked files or local changes are deleted for good",
                consequence: "Permanently deletes files and unsaved changes"),
            .turkish: RuleText(
                title: "Geri dönüşsüz git işlemi",
                message: "İzlenmeyen dosyalar veya yerel değişiklikler geri alınamaz şekilde siliniyor",
                consequence: "Dosyaları ve kaydedilmemiş değişiklikleri kalıcı siler"),
            .german: RuleText(
                title: "Unwiderrufliche Git-Operation",
                message: "Nicht versionierte Dateien oder lokale Änderungen werden endgültig gelöscht",
                consequence: "Löscht Dateien und Änderungen endgültig"),
            .spanish: RuleText(
                title: "Operación de git irreversible",
                message: "Se borran sin remedio archivos sin seguimiento o cambios locales",
                consequence: "Borra archivos y cambios para siempre"),
            .italian: RuleText(
                title: "Operazione git irreversibile",
                message: "File non tracciati o modifiche locali vengono eliminati per sempre",
                consequence: "Elimina file e modifiche per sempre"),
            .french: RuleText(
                title: "Opération git irréversible",
                message: "Des fichiers non suivis ou des modifications locales sont supprimés définitivement",
                consequence: "Supprime fichiers et modifications définitivement")
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

    /// The plain "what happens" sentence; a rule without one reads as its title.
    func localizedConsequence(_ localizer: Localizer) -> String {
        RuleLocalization.text(forRule: id, language: localizer.language)?.consequence
            ?? consequence
            ?? localizedTitle(localizer)
    }
}

public extension RiskHit {
    /// A stored hit keeps the message it was annotated with (the rules file's
    /// own text); what a reader sees follows the interface language.
    func localizedMessage(_ localizer: Localizer) -> String {
        RuleLocalization.text(forRule: ruleId, language: localizer.language)?.message ?? message
    }

    /// The plain "what happens" sentence; falls back to the rule's title.
    func localizedConsequence(_ localizer: Localizer) -> String {
        RuleLocalization.text(forRule: ruleId, language: localizer.language)?.consequence
            ?? EventPresentation.ruleTitle(self, localizer: localizer)
    }

    /// The command line, the MCP server and exports speak English.
    var englishMessage: String {
        RuleLocalization.text(forRule: ruleId, language: .english)?.message ?? message
    }
}
