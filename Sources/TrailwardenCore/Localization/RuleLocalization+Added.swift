// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Words for the rules added after the first release (R11 onward).
extension RuleLocalization {
    static let addedEntries: [String: [AppLanguage: RuleText]] = [
        "R11": [
            .english: RuleText(
                title: "Environment file access",
                message: "An environment file can hold API keys or passwords"),
            .turkish: RuleText(
                title: "Ortam dosyası erişimi",
                message: "Ortam dosyası API anahtarı veya parola içerebilir"),
            .german: RuleText(
                title: "Zugriff auf Umgebungsdatei",
                message: "Eine Umgebungsdatei kann API-Schlüssel oder Passwörter enthalten"),
            .spanish: RuleText(
                title: "Acceso a archivo de entorno",
                message: "Un archivo de entorno puede contener claves de API o contraseñas"),
            .italian: RuleText(
                title: "Accesso a file di ambiente",
                message: "Un file di ambiente può contenere chiavi API o password"),
            .french: RuleText(
                title: "Accès au fichier d'environnement",
                message: "Un fichier d'environnement peut contenir des clés API ou des mots de passe")
        ],
        "R12": [
            .english: RuleText(
                title: "Password read from the keychain",
                message: "A password or key in the macOS Keychain is being read out"),
            .turkish: RuleText(
                title: "Anahtarlıktan parola okuma",
                message: "macOS Anahtarlığı'ndaki bir parola veya anahtar açığa okunuyor"),
            .german: RuleText(
                title: "Passwort aus dem Schlüsselbund lesen",
                message: "Ein Passwort oder Schlüssel im macOS-Schlüsselbund wird ausgelesen"),
            .spanish: RuleText(
                title: "Lectura de contraseña del llavero",
                message: "Se lee una contraseña o clave del Llavero de macOS"),
            .italian: RuleText(
                title: "Lettura di password dal portachiavi",
                message: "Una password o chiave nel Portachiavi di macOS viene letta"),
            .french: RuleText(
                title: "Lecture d'un mot de passe du trousseau",
                message: "Un mot de passe ou une clé du Trousseau macOS est lu en clair")
        ],
        "R13": [
            .english: RuleText(
                title: "Persistence",
                message: "A job is being installed that will run on its own after the session ends (launchd "
                    + "or cron)"),
            .turkish: RuleText(
                title: "Kalıcılık kurulumu",
                message: "Oturum kapansa da kendiliğinden çalışacak bir iş kuruluyor (launchd veya cron)"),
            .german: RuleText(
                title: "Dauerhafte Installation",
                message: "Ein Job wird eingerichtet, der nach Sitzungsende von selbst weiterläuft (launchd "
                    + "oder cron)"),
            .spanish: RuleText(
                title: "Instalación de persistencia",
                message: "Se instala una tarea que seguirá ejecutándose sola al cerrar la sesión (launchd o cron)"),
            .italian: RuleText(
                title: "Installazione di persistenza",
                message: "Viene installato un job che continuerà a girare da solo dopo la sessione (launchd o cron)"),
            .french: RuleText(
                title: "Installation de persistance",
                message: "Une tâche est installée et continuera de tourner seule après la session (launchd ou cron)")
        ],
        "R14": [
            .english: RuleText(
                title: "Shell startup file change",
                message: "A startup file that runs in every new terminal is being changed"),
            .turkish: RuleText(
                title: "Kabuk başlangıç dosyası değişikliği",
                message: "Her yeni terminalde çalışacak bir başlangıç dosyası değiştiriliyor"),
            .german: RuleText(
                title: "Änderung der Shell-Startdatei",
                message: "Eine Startdatei, die in jedem neuen Terminal läuft, wird geändert"),
            .spanish: RuleText(
                title: "Cambio en archivo de inicio del shell",
                message: "Se modifica un archivo de inicio que se ejecuta en cada terminal nueva"),
            .italian: RuleText(
                title: "Modifica del file di avvio della shell",
                message: "Viene modificato un file di avvio eseguito in ogni nuovo terminale"),
            .french: RuleText(
                title: "Modification du fichier de démarrage du shell",
                message: "Un fichier de démarrage exécuté dans chaque nouveau terminal est modifié")
        ],
        "R15": [
            .english: RuleText(
                title: "Agent settings change",
                message: "An agent's permissions, hooks or MCP servers are being changed"),
            .turkish: RuleText(
                title: "Ajan ayarı değişikliği",
                message: "Bir ajanın izinleri, kancaları veya MCP sunucuları değiştiriliyor"),
            .german: RuleText(
                title: "Änderung der Agent-Einstellungen",
                message: "Berechtigungen, Hooks oder MCP-Server eines Agenten werden geändert"),
            .spanish: RuleText(
                title: "Cambio de ajustes del agente",
                message: "Se modifican los permisos, hooks o servidores MCP de un agente"),
            .italian: RuleText(
                title: "Modifica delle impostazioni dell'agente",
                message: "Vengono modificati permessi, hook o server MCP di un agente"),
            .french: RuleText(
                title: "Modification des réglages de l'agent",
                message: "Les permissions, hooks ou serveurs MCP d'un agent sont modifiés")
        ],
        "R16": [
            .english: RuleText(
                title: "Approval bypass",
                message: "An agent is being started so that it runs everything without asking"),
            .turkish: RuleText(
                title: "Onay atlatma",
                message: "Bir ajan, onay sormadan her şeyi çalıştıracak şekilde başlatılıyor"),
            .german: RuleText(
                title: "Umgehen der Freigabe",
                message: "Ein Agent wird so gestartet, dass er alles ohne Rückfrage ausführt"),
            .spanish: RuleText(
                title: "Omisión de aprobación",
                message: "Se inicia un agente para que ejecute todo sin preguntar"),
            .italian: RuleText(
                title: "Aggiramento dell'approvazione",
                message: "Un agente viene avviato in modo da eseguire tutto senza chiedere"),
            .french: RuleText(
                title: "Contournement de l'approbation",
                message: "Un agent est lancé pour tout exécuter sans demander")
        ],
        "R17": [
            .english: RuleText(
                title: "Git hook bypass",
                message: "Pre-commit or pre-push checks (lint, tests, secret scan) are switched off"),
            .turkish: RuleText(
                title: "Git kancası atlatma",
                message: "Commit veya push öncesi kontroller (lint, test, sır taraması) devre dışı"),
            .german: RuleText(
                title: "Umgehen von Git-Hooks",
                message: "Prüfungen vor Commit oder Push (Lint, Tests, Secret-Scan) werden abgeschaltet"),
            .spanish: RuleText(
                title: "Omisión de hooks de git",
                message: "Se desactivan las comprobaciones previas al commit o push (lint, tests, escaneo de "
                    + "secretos)"),
            .italian: RuleText(
                title: "Aggiramento degli hook git",
                message: "I controlli prima di commit o push (lint, test, scansione dei segreti) vengono "
                    + "disattivati"),
            .french: RuleText(
                title: "Contournement des hooks git",
                message: "Les contrôles avant commit ou push (lint, tests, analyse de secrets) sont désactivés")
        ],
        "R18": [
            .english: RuleText(
                title: "GitHub deletion",
                message: "A repository, release or secret is being deleted on GitHub"),
            .turkish: RuleText(
                title: "GitHub kaynağı silme",
                message: "Bir depo, sürüm veya gizli değer GitHub'dan siliniyor"),
            .german: RuleText(
                title: "GitHub-Ressource löschen",
                message: "Ein Repository, Release oder Secret wird auf GitHub gelöscht"),
            .spanish: RuleText(
                title: "Borrado de recurso en GitHub",
                message: "Se borra un repositorio, una release o un secreto en GitHub"),
            .italian: RuleText(
                title: "Eliminazione di risorsa GitHub",
                message: "Un repository, una release o un segreto viene eliminato su GitHub"),
            .french: RuleText(
                title: "Suppression d'une ressource GitHub",
                message: "Un dépôt, une release ou un secret est supprimé sur GitHub")
        ],
        "R19": [
            .english: RuleText(
                title: "Package or release publish",
                message: "Something is being published to a public package registry or release"),
            .turkish: RuleText(
                title: "Paket veya sürüm yayınlama",
                message: "Herkese açık bir pakete veya sürüme yayın yapılıyor"),
            .german: RuleText(
                title: "Paket oder Release veröffentlichen",
                message: "Etwas wird in einer öffentlichen Paketquelle oder als Release veröffentlicht"),
            .spanish: RuleText(
                title: "Publicación de paquete o versión",
                message: "Se publica algo en un registro de paquetes o en una release públicos"),
            .italian: RuleText(
                title: "Pubblicazione di pacchetto o release",
                message: "Qualcosa viene pubblicato in un registro di pacchetti o in una release pubblici"),
            .french: RuleText(
                title: "Publication d'un paquet ou d'une version",
                message: "Quelque chose est publié dans un registre de paquets ou une release publics")
        ],
        "R20": [
            .english: RuleText(
                title: "CI pipeline change",
                message: "A CI definition that runs on a server with secrets is being changed"),
            .turkish: RuleText(
                title: "CI hattı değişikliği",
                message: "Sunucuda gizli değerlerle çalışan CI tanımı değiştiriliyor"),
            .german: RuleText(
                title: "Änderung der CI-Pipeline",
                message: "Eine CI-Definition, die auf einem Server mit Secrets läuft, wird geändert"),
            .spanish: RuleText(
                title: "Cambio en el pipeline de CI",
                message: "Se modifica una definición de CI que se ejecuta en un servidor con secretos"),
            .italian: RuleText(
                title: "Modifica della pipeline CI",
                message: "Viene modificata una definizione CI eseguita su un server con segreti"),
            .french: RuleText(
                title: "Modification du pipeline CI",
                message: "Une définition CI exécutée sur un serveur avec des secrets est modifiée")
        ],
        "R21": [
            .english: RuleText(
                title: "macOS protection disabled",
                message: "A protection such as Gatekeeper, SIP, quarantine or the firewall is being switched off"),
            .turkish: RuleText(
                title: "macOS korumasını kapatma",
                message: "Gatekeeper, SIP, karantina veya güvenlik duvarı gibi bir koruma kapatılıyor"),
            .german: RuleText(
                title: "macOS-Schutz deaktivieren",
                message: "Ein Schutz wie Gatekeeper, SIP, Quarantäne oder die Firewall wird abgeschaltet"),
            .spanish: RuleText(
                title: "Desactivar protección de macOS",
                message: "Se desactiva una protección como Gatekeeper, SIP, cuarentena o el cortafuegos"),
            .italian: RuleText(
                title: "Disattivazione di una protezione macOS",
                message: "Viene disattivata una protezione come Gatekeeper, SIP, quarantena o firewall"),
            .french: RuleText(
                title: "Désactivation d'une protection macOS",
                message: "Une protection comme Gatekeeper, SIP, la quarantaine ou le pare-feu est désactivée")
        ],
        "R22": [
            .english: RuleText(
                title: "Remote shell",
                message: "A shell is being wired to a network connection; the machine could be driven from outside"),
            .turkish: RuleText(
                title: "Uzak kabuk",
                message: "Kabuk bir ağ bağlantısına bağlanıyor; makine dışarıdan yönetilebilir"),
            .german: RuleText(
                title: "Remote-Shell",
                message: "Eine Shell wird an eine Netzwerkverbindung gekoppelt; der Rechner ließe sich von "
                    + "außen steuern"),
            .spanish: RuleText(
                title: "Shell remoto",
                message: "Se conecta un shell a una conexión de red; la máquina podría controlarse desde fuera"),
            .italian: RuleText(
                title: "Shell remota",
                message: "Una shell viene collegata a una connessione di rete; la macchina potrebbe essere "
                    + "controllata dall'esterno"),
            .french: RuleText(
                title: "Shell distant",
                message: "Un shell est relié à une connexion réseau ; la machine pourrait être pilotée de "
                    + "l'extérieur")
        ],
        "R23": [
            .english: RuleText(
                title: "Disk erase",
                message: "A disk or partition is being erased or overwritten"),
            .turkish: RuleText(
                title: "Disk silme",
                message: "Bir disk veya bölüm siliniyor ya da üzerine yazılıyor"),
            .german: RuleText(
                title: "Datenträger löschen",
                message: "Ein Datenträger oder eine Partition wird gelöscht oder überschrieben"),
            .spanish: RuleText(
                title: "Borrado de disco",
                message: "Se borra o sobrescribe un disco o una partición"),
            .italian: RuleText(
                title: "Cancellazione del disco",
                message: "Un disco o una partizione viene cancellato o sovrascritto"),
            .french: RuleText(
                title: "Effacement de disque",
                message: "Un disque ou une partition est effacé ou écrasé")
        ],
        "R24": [
            .english: RuleText(
                title: "Destructive database command",
                message: "A database or schema is dropped, a DELETE without WHERE takes every row, or Redis "
                    + "is flushed"),
            .turkish: RuleText(
                title: "Yıkıcı veritabanı komutu",
                message: "Veritabanı veya şema siliniyor, koşulsuz DELETE tüm satırları götürüyor ya da "
                    + "Redis boşaltılıyor"),
            .german: RuleText(
                title: "Destruktiver Datenbankbefehl",
                message: "Datenbank oder Schema werden gelöscht, ein DELETE ohne WHERE entfernt alle Zeilen "
                    + "oder Redis wird geleert"),
            .spanish: RuleText(
                title: "Comando destructivo de base de datos",
                message: "Se elimina una base de datos o un esquema, un DELETE sin WHERE se lleva todas las "
                    + "filas o se vacía Redis"),
            .italian: RuleText(
                title: "Comando distruttivo sul database",
                message: "Un database o uno schema viene eliminato, un DELETE senza WHERE rimuove tutte le "
                    + "righe o Redis viene svuotato"),
            .french: RuleText(
                title: "Commande destructive de base de données",
                message: "Une base ou un schéma est supprimé, un DELETE sans WHERE emporte toutes les lignes "
                    + "ou Redis est vidé")
        ],
        "R25": [
            .english: RuleText(
                title: "Infrastructure teardown",
                message: "Cloud resources, servers or databases are being deleted"),
            .turkish: RuleText(
                title: "Altyapı silme",
                message: "Bulut kaynakları, sunucular veya veritabanları siliniyor"),
            .german: RuleText(
                title: "Infrastruktur abbauen",
                message: "Cloud-Ressourcen, Server oder Datenbanken werden gelöscht"),
            .spanish: RuleText(
                title: "Eliminación de infraestructura",
                message: "Se eliminan recursos en la nube, servidores o bases de datos"),
            .italian: RuleText(
                title: "Smantellamento dell'infrastruttura",
                message: "Risorse cloud, server o database vengono eliminati"),
            .french: RuleText(
                title: "Démantèlement de l'infrastructure",
                message: "Des ressources cloud, serveurs ou bases de données sont supprimés")
        ],
        "R26": [
            .english: RuleText(
                title: "Trail erasure",
                message: "Agent transcripts, shell history or the Trailwarden index are being deleted"),
            .turkish: RuleText(
                title: "İz silme",
                message: "Ajan transkriptleri, kabuk geçmişi veya Trailwarden indeksi siliniyor"),
            .german: RuleText(
                title: "Spuren löschen",
                message: "Agent-Transkripte, Shell-Verlauf oder der Trailwarden-Index werden gelöscht"),
            .spanish: RuleText(
                title: "Borrado de rastros",
                message: "Se borran transcripciones de agentes, el historial del shell o el índice de Trailwarden"),
            .italian: RuleText(
                title: "Cancellazione delle tracce",
                message: "Vengono eliminati trascrizioni degli agenti, cronologia della shell o indice di "
                    + "Trailwarden"),
            .french: RuleText(
                title: "Effacement des traces",
                message: "Les transcriptions d'agents, l'historique du shell ou l'index Trailwarden sont supprimés")
        ],
        "R27": [
            .english: RuleText(
                title: "Secret in a command",
                message: "An API key is written in plain text on the command line; it stays in the "
                    + "transcript and the shell history"),
            .turkish: RuleText(
                title: "Komutta açık anahtar",
                message: "Bir API anahtarı komut satırına açıkça yazılmış; transkriptte ve kabuk geçmişinde kalır"),
            .german: RuleText(
                title: "Schlüssel im Befehl",
                message: "Ein API-Schlüssel steht im Klartext in der Befehlszeile; er bleibt im Transkript "
                    + "und im Shell-Verlauf"),
            .spanish: RuleText(
                title: "Clave en el comando",
                message: "Una clave de API está en texto plano en la línea de comandos; queda en la "
                    + "transcripción y en el historial del shell"),
            .italian: RuleText(
                title: "Chiave nel comando",
                message: "Una chiave API è scritta in chiaro nella riga di comando; resta nella trascrizione "
                    + "e nella cronologia della shell"),
            .french: RuleText(
                title: "Clé dans la commande",
                message: "Une clé API est écrite en clair dans la ligne de commande ; elle reste dans la "
                    + "transcription et l'historique du shell")
        ],
        "R28": [
            .english: RuleText(
                title: "Risky database or deploy command",
                message: "A table is dropped or emptied, or a deployment is removed or applied without "
                    + "review"),
            .turkish: RuleText(
                title: "Riskli veritabanı veya dağıtım komutu",
                message: "Bir tablo siliniyor veya boşaltılıyor ya da bir dağıtım onaysız kaldırılıyor veya "
                    + "uygulanıyor"),
            .german: RuleText(
                title: "Riskanter Datenbank- oder Deploy-Befehl",
                message: "Eine Tabelle wird gelöscht oder geleert, oder ein Deployment wird ohne Prüfung "
                    + "entfernt oder angewendet"),
            .spanish: RuleText(
                title: "Comando arriesgado de base de datos o despliegue",
                message: "Se elimina o vacía una tabla, o se quita o aplica un despliegue sin revisión"),
            .italian: RuleText(
                title: "Comando rischioso su database o deploy",
                message: "Una tabella viene eliminata o svuotata, oppure un deploy viene rimosso o applicato "
                    + "senza revisione"),
            .french: RuleText(
                title: "Commande risquée de base de données ou de déploiement",
                message: "Une table est supprimée ou vidée, ou un déploiement est retiré ou appliqué sans "
                    + "relecture")
        ]
    ]
}
