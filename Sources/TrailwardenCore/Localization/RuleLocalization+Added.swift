// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Words for the rules added after the first release (R11 onward).
extension RuleLocalization {
    static let addedEntries: [String: [AppLanguage: RuleText]] = [
        "R11": [
            .english: RuleText(
                title: "Environment file access",
                message: "An environment file can hold API keys or passwords",
                consequence: "Reads a file that may hold API keys"),
            .turkish: RuleText(
                title: "Ortam dosyası erişimi",
                message: "Ortam dosyası API anahtarı veya parola içerebilir",
                consequence: "API anahtarı içerebilen bir dosyayı okur"),
            .german: RuleText(
                title: "Zugriff auf Umgebungsdatei",
                message: "Eine Umgebungsdatei kann API-Schlüssel oder Passwörter enthalten",
                consequence: "Liest eine Datei mit möglichen API-Schlüsseln"),
            .spanish: RuleText(
                title: "Acceso a archivo de entorno",
                message: "Un archivo de entorno puede contener claves de API o contraseñas",
                consequence: "Lee un archivo con posibles claves de API"),
            .italian: RuleText(
                title: "Accesso a file di ambiente",
                message: "Un file di ambiente può contenere chiavi API o password",
                consequence: "Legge un file con possibili chiavi API"),
            .french: RuleText(
                title: "Accès au fichier d'environnement",
                message: "Un fichier d'environnement peut contenir des clés API ou des mots de passe",
                consequence: "Lit un fichier pouvant contenir des clés API")
        ],
        "R12": [
            .english: RuleText(
                title: "Password read from the keychain",
                message: "A password or key in the macOS Keychain is being read out",
                consequence: "Reads a saved password out of your Keychain"),
            .turkish: RuleText(
                title: "Anahtarlıktan parola okuma",
                message: "macOS Anahtarlığı'ndaki bir parola veya anahtar açığa okunuyor",
                consequence: "Anahtarlığınızdaki kayıtlı bir parolayı okur"),
            .german: RuleText(
                title: "Passwort aus dem Schlüsselbund lesen",
                message: "Ein Passwort oder Schlüssel im macOS-Schlüsselbund wird ausgelesen",
                consequence: "Liest ein gespeichertes Passwort aus dem Schlüsselbund"),
            .spanish: RuleText(
                title: "Lectura de contraseña del llavero",
                message: "Se lee una contraseña o clave del Llavero de macOS",
                consequence: "Lee una contraseña guardada del Llavero"),
            .italian: RuleText(
                title: "Lettura di password dal portachiavi",
                message: "Una password o chiave nel Portachiavi di macOS viene letta",
                consequence: "Legge una password salvata dal Portachiavi"),
            .french: RuleText(
                title: "Lecture d'un mot de passe du trousseau",
                message: "Un mot de passe ou une clé du Trousseau macOS est lu en clair",
                consequence: "Lit un mot de passe enregistré dans le Trousseau")
        ],
        "R13": [
            .english: RuleText(
                title: "Persistence",
                message: "A job is being installed that will run on its own after the session ends (launchd "
                    + "or cron)",
                consequence: "Installs a job that keeps running after the session"),
            .turkish: RuleText(
                title: "Kalıcılık kurulumu",
                message: "Oturum kapansa da kendiliğinden çalışacak bir iş kuruluyor (launchd veya cron)",
                consequence: "Oturumdan sonra çalışmaya devam eden bir görev kurar"),
            .german: RuleText(
                title: "Dauerhafte Installation",
                message: "Ein Job wird eingerichtet, der nach Sitzungsende von selbst weiterläuft (launchd "
                    + "oder cron)",
                consequence: "Installiert einen Job, der nach der Sitzung weiterläuft"),
            .spanish: RuleText(
                title: "Instalación de persistencia",
                message: "Se instala una tarea que seguirá ejecutándose sola al cerrar la sesión (launchd o cron)",
                consequence: "Instala una tarea que sigue tras la sesión"),
            .italian: RuleText(
                title: "Installazione di persistenza",
                message: "Viene installato un job che continuerà a girare da solo dopo la sessione (launchd o cron)",
                consequence: "Installa un'attività che continua dopo la sessione"),
            .french: RuleText(
                title: "Installation de persistance",
                message: "Une tâche est installée et continuera de tourner seule après la session (launchd ou cron)",
                consequence: "Installe une tâche qui continue après la session")
        ],
        "R14": [
            .english: RuleText(
                title: "Shell startup file change",
                message: "A startup file that runs in every new terminal is being changed",
                consequence: "Changes what runs in every new terminal"),
            .turkish: RuleText(
                title: "Kabuk başlangıç dosyası değişikliği",
                message: "Her yeni terminalde çalışacak bir başlangıç dosyası değiştiriliyor",
                consequence: "Her yeni terminalde çalışanı değiştirir"),
            .german: RuleText(
                title: "Änderung der Shell-Startdatei",
                message: "Eine Startdatei, die in jedem neuen Terminal läuft, wird geändert",
                consequence: "Ändert, was in jedem neuen Terminal läuft"),
            .spanish: RuleText(
                title: "Cambio en archivo de inicio del shell",
                message: "Se modifica un archivo de inicio que se ejecuta en cada terminal nueva",
                consequence: "Cambia lo que se ejecuta en cada terminal nuevo"),
            .italian: RuleText(
                title: "Modifica del file di avvio della shell",
                message: "Viene modificato un file di avvio eseguito in ogni nuovo terminale",
                consequence: "Cambia ciò che parte in ogni nuovo terminale"),
            .french: RuleText(
                title: "Modification du fichier de démarrage du shell",
                message: "Un fichier de démarrage exécuté dans chaque nouveau terminal est modifié",
                consequence: "Change ce qui s'exécute dans chaque nouveau terminal")
        ],
        "R15": [
            .english: RuleText(
                title: "Agent settings change",
                message: "An agent's permissions, hooks or MCP servers are being changed",
                consequence: "Changes what an agent is allowed to do"),
            .turkish: RuleText(
                title: "Ajan ayarı değişikliği",
                message: "Bir ajanın izinleri, kancaları veya MCP sunucuları değiştiriliyor",
                consequence: "Bir ajanın neye izinli olduğunu değiştirir"),
            .german: RuleText(
                title: "Änderung der Agent-Einstellungen",
                message: "Berechtigungen, Hooks oder MCP-Server eines Agenten werden geändert",
                consequence: "Ändert, was ein Agent tun darf"),
            .spanish: RuleText(
                title: "Cambio de ajustes del agente",
                message: "Se modifican los permisos, hooks o servidores MCP de un agente",
                consequence: "Cambia lo que un agente puede hacer"),
            .italian: RuleText(
                title: "Modifica delle impostazioni dell'agente",
                message: "Vengono modificati permessi, hook o server MCP di un agente",
                consequence: "Cambia ciò che un agente può fare"),
            .french: RuleText(
                title: "Modification des réglages de l'agent",
                message: "Les permissions, hooks ou serveurs MCP d'un agent sont modifiés",
                consequence: "Change ce qu'un agent a le droit de faire")
        ],
        "R16": [
            .english: RuleText(
                title: "Approval bypass",
                message: "An agent is being started so that it runs everything without asking",
                consequence: "Lets an agent run everything without asking"),
            .turkish: RuleText(
                title: "Onay atlatma",
                message: "Bir ajan, onay sormadan her şeyi çalıştıracak şekilde başlatılıyor",
                consequence: "Bir ajanın her şeyi sormadan çalıştırmasına izin verir"),
            .german: RuleText(
                title: "Umgehen der Freigabe",
                message: "Ein Agent wird so gestartet, dass er alles ohne Rückfrage ausführt",
                consequence: "Lässt einen Agenten alles ohne Nachfrage ausführen"),
            .spanish: RuleText(
                title: "Omisión de aprobación",
                message: "Se inicia un agente para que ejecute todo sin preguntar",
                consequence: "Deja que un agente ejecute todo sin preguntar"),
            .italian: RuleText(
                title: "Aggiramento dell'approvazione",
                message: "Un agente viene avviato in modo da eseguire tutto senza chiedere",
                consequence: "Lascia che un agente esegua tutto senza chiedere"),
            .french: RuleText(
                title: "Contournement de l'approbation",
                message: "Un agent est lancé pour tout exécuter sans demander",
                consequence: "Laisse un agent tout exécuter sans demander")
        ],
        "R17": [
            .english: RuleText(
                title: "Git hook bypass",
                message: "Pre-commit or pre-push checks (lint, tests, secret scan) are switched off",
                consequence: "Skips the checks that run before a commit"),
            .turkish: RuleText(
                title: "Git kancası atlatma",
                message: "Commit veya push öncesi kontroller (lint, test, sır taraması) devre dışı",
                consequence: "Commit öncesi kontrolleri atlar"),
            .german: RuleText(
                title: "Umgehen von Git-Hooks",
                message: "Prüfungen vor Commit oder Push (Lint, Tests, Secret-Scan) werden abgeschaltet",
                consequence: "Überspringt die Prüfungen vor einem Commit"),
            .spanish: RuleText(
                title: "Omisión de hooks de git",
                message: "Se desactivan las comprobaciones previas al commit o push (lint, tests, escaneo de "
                    + "secretos)",
                consequence: "Se salta las comprobaciones previas al commit"),
            .italian: RuleText(
                title: "Aggiramento degli hook git",
                message: "I controlli prima di commit o push (lint, test, scansione dei segreti) vengono "
                    + "disattivati",
                consequence: "Salta i controlli prima di un commit"),
            .french: RuleText(
                title: "Contournement des hooks git",
                message: "Les contrôles avant commit ou push (lint, tests, analyse de secrets) sont désactivés",
                consequence: "Saute les contrôles avant un commit")
        ],
        "R18": [
            .english: RuleText(
                title: "GitHub deletion",
                message: "A repository, release or secret is being deleted on GitHub",
                consequence: "Deletes a repository, release or secret on GitHub"),
            .turkish: RuleText(
                title: "GitHub kaynağı silme",
                message: "Bir depo, sürüm veya gizli değer GitHub'dan siliniyor",
                consequence: "GitHub'daki bir depoyu, sürümü veya sırrı siler"),
            .german: RuleText(
                title: "GitHub-Ressource löschen",
                message: "Ein Repository, Release oder Secret wird auf GitHub gelöscht",
                consequence: "Löscht ein Repository, Release oder Secret auf GitHub"),
            .spanish: RuleText(
                title: "Borrado de recurso en GitHub",
                message: "Se borra un repositorio, una release o un secreto en GitHub",
                consequence: "Borra un repositorio, versión o secreto en GitHub"),
            .italian: RuleText(
                title: "Eliminazione di risorsa GitHub",
                message: "Un repository, una release o un segreto viene eliminato su GitHub",
                consequence: "Elimina un repository, release o segreto su GitHub"),
            .french: RuleText(
                title: "Suppression d'une ressource GitHub",
                message: "Un dépôt, une release ou un secret est supprimé sur GitHub",
                consequence: "Supprime un dépôt, une version ou un secret sur GitHub")
        ],
        "R19": [
            .english: RuleText(
                title: "Package or release publish",
                message: "Something is being published to a public package registry or release",
                consequence: "Publishes your code or package for everyone"),
            .turkish: RuleText(
                title: "Paket veya sürüm yayınlama",
                message: "Herkese açık bir pakete veya sürüme yayın yapılıyor",
                consequence: "Kodunuzu veya paketinizi herkese yayınlar"),
            .german: RuleText(
                title: "Paket oder Release veröffentlichen",
                message: "Etwas wird in einer öffentlichen Paketquelle oder als Release veröffentlicht",
                consequence: "Veröffentlicht Ihren Code oder Ihr Paket für alle"),
            .spanish: RuleText(
                title: "Publicación de paquete o versión",
                message: "Se publica algo en un registro de paquetes o en una release públicos",
                consequence: "Publica tu código o paquete para todos"),
            .italian: RuleText(
                title: "Pubblicazione di pacchetto o release",
                message: "Qualcosa viene pubblicato in un registro di pacchetti o in una release pubblici",
                consequence: "Pubblica il tuo codice o pacchetto per tutti"),
            .french: RuleText(
                title: "Publication d'un paquet ou d'une version",
                message: "Quelque chose est publié dans un registre de paquets ou une release publics",
                consequence: "Publie votre code ou paquet pour tout le monde")
        ],
        "R20": [
            .english: RuleText(
                title: "CI pipeline change",
                message: "A CI definition that runs on a server with secrets is being changed",
                consequence: "Changes automation that runs with your secrets"),
            .turkish: RuleText(
                title: "CI hattı değişikliği",
                message: "Sunucuda gizli değerlerle çalışan CI tanımı değiştiriliyor",
                consequence: "Gizli anahtarlarınızla çalışan otomasyonu değiştirir"),
            .german: RuleText(
                title: "Änderung der CI-Pipeline",
                message: "Eine CI-Definition, die auf einem Server mit Secrets läuft, wird geändert",
                consequence: "Ändert Automatisierung, die mit Ihren Secrets läuft"),
            .spanish: RuleText(
                title: "Cambio en el pipeline de CI",
                message: "Se modifica una definición de CI que se ejecuta en un servidor con secretos",
                consequence: "Cambia la automatización que usa tus secretos"),
            .italian: RuleText(
                title: "Modifica della pipeline CI",
                message: "Viene modificata una definizione CI eseguita su un server con segreti",
                consequence: "Cambia l'automazione che usa i tuoi segreti"),
            .french: RuleText(
                title: "Modification du pipeline CI",
                message: "Une définition CI exécutée sur un serveur avec des secrets est modifiée",
                consequence: "Modifie l'automatisation qui utilise vos secrets")
        ],
        "R21": [
            .english: RuleText(
                title: "macOS protection disabled",
                message: "A protection such as Gatekeeper, SIP, quarantine or the firewall is being switched off",
                consequence: "Switches off a Mac security protection"),
            .turkish: RuleText(
                title: "macOS korumasını kapatma",
                message: "Gatekeeper, SIP, karantina veya güvenlik duvarı gibi bir koruma kapatılıyor",
                consequence: "Mac'in bir güvenlik korumasını kapatır"),
            .german: RuleText(
                title: "macOS-Schutz deaktivieren",
                message: "Ein Schutz wie Gatekeeper, SIP, Quarantäne oder die Firewall wird abgeschaltet",
                consequence: "Schaltet einen Sicherheitsschutz des Mac ab"),
            .spanish: RuleText(
                title: "Desactivar protección de macOS",
                message: "Se desactiva una protección como Gatekeeper, SIP, cuarentena o el cortafuegos",
                consequence: "Desactiva una protección de seguridad del Mac"),
            .italian: RuleText(
                title: "Disattivazione di una protezione macOS",
                message: "Viene disattivata una protezione come Gatekeeper, SIP, quarantena o firewall",
                consequence: "Disattiva una protezione di sicurezza del Mac"),
            .french: RuleText(
                title: "Désactivation d'une protection macOS",
                message: "Une protection comme Gatekeeper, SIP, la quarantaine ou le pare-feu est désactivée",
                consequence: "Désactive une protection de sécurité du Mac")
        ],
        "R22": [
            .english: RuleText(
                title: "Remote shell",
                message: "A shell is being wired to a network connection; the machine could be driven from outside",
                consequence: "Lets someone else control this Mac remotely"),
            .turkish: RuleText(
                title: "Uzak kabuk",
                message: "Kabuk bir ağ bağlantısına bağlanıyor; makine dışarıdan yönetilebilir",
                consequence: "Başkasının bu Mac'i uzaktan yönetmesine izin verir"),
            .german: RuleText(
                title: "Remote-Shell",
                message: "Eine Shell wird an eine Netzwerkverbindung gekoppelt; der Rechner ließe sich von "
                    + "außen steuern",
                consequence: "Lässt andere diesen Mac aus der Ferne steuern"),
            .spanish: RuleText(
                title: "Shell remoto",
                message: "Se conecta un shell a una conexión de red; la máquina podría controlarse desde fuera",
                consequence: "Deja que otros controlen este Mac a distancia"),
            .italian: RuleText(
                title: "Shell remota",
                message: "Una shell viene collegata a una connessione di rete; la macchina potrebbe essere "
                    + "controllata dall'esterno",
                consequence: "Permette ad altri di controllare questo Mac da remoto"),
            .french: RuleText(
                title: "Shell distant",
                message: "Un shell est relié à une connexion réseau ; la machine pourrait être pilotée de "
                    + "l'extérieur",
                consequence: "Permet à d'autres de contrôler ce Mac à distance")
        ],
        "R23": [
            .english: RuleText(
                title: "Disk erase",
                message: "A disk or partition is being erased or overwritten",
                consequence: "Erases a whole disk or partition"),
            .turkish: RuleText(
                title: "Disk silme",
                message: "Bir disk veya bölüm siliniyor ya da üzerine yazılıyor",
                consequence: "Bir diski veya bölümü tamamen siler"),
            .german: RuleText(
                title: "Datenträger löschen",
                message: "Ein Datenträger oder eine Partition wird gelöscht oder überschrieben",
                consequence: "Löscht eine ganze Festplatte oder Partition"),
            .spanish: RuleText(
                title: "Borrado de disco",
                message: "Se borra o sobrescribe un disco o una partición",
                consequence: "Borra un disco o partición entera"),
            .italian: RuleText(
                title: "Cancellazione del disco",
                message: "Un disco o una partizione viene cancellato o sovrascritto",
                consequence: "Cancella un intero disco o una partizione"),
            .french: RuleText(
                title: "Effacement de disque",
                message: "Un disque ou une partition est effacé ou écrasé",
                consequence: "Efface un disque ou une partition entière")
        ],
        "R24": [
            .english: RuleText(
                title: "Destructive database command",
                message: "A database or schema is dropped, a DELETE without WHERE takes every row, or Redis "
                    + "is flushed",
                consequence: "Deletes a database or all its rows"),
            .turkish: RuleText(
                title: "Yıkıcı veritabanı komutu",
                message: "Veritabanı veya şema siliniyor, koşulsuz DELETE tüm satırları götürüyor ya da "
                    + "Redis boşaltılıyor",
                consequence: "Bir veritabanını veya tüm satırlarını siler"),
            .german: RuleText(
                title: "Destruktiver Datenbankbefehl",
                message: "Datenbank oder Schema werden gelöscht, ein DELETE ohne WHERE entfernt alle Zeilen "
                    + "oder Redis wird geleert",
                consequence: "Löscht eine Datenbank oder alle ihre Zeilen"),
            .spanish: RuleText(
                title: "Comando destructivo de base de datos",
                message: "Se elimina una base de datos o un esquema, un DELETE sin WHERE se lleva todas las "
                    + "filas o se vacía Redis",
                consequence: "Borra una base de datos o todas sus filas"),
            .italian: RuleText(
                title: "Comando distruttivo sul database",
                message: "Un database o uno schema viene eliminato, un DELETE senza WHERE rimuove tutte le "
                    + "righe o Redis viene svuotato",
                consequence: "Elimina un database o tutte le sue righe"),
            .french: RuleText(
                title: "Commande destructive de base de données",
                message: "Une base ou un schéma est supprimé, un DELETE sans WHERE emporte toutes les lignes "
                    + "ou Redis est vidé",
                consequence: "Supprime une base de données ou toutes ses lignes")
        ],
        "R25": [
            .english: RuleText(
                title: "Infrastructure teardown",
                message: "Cloud resources, servers or databases are being deleted",
                consequence: "Deletes servers or cloud resources"),
            .turkish: RuleText(
                title: "Altyapı silme",
                message: "Bulut kaynakları, sunucular veya veritabanları siliniyor",
                consequence: "Sunucuları veya bulut kaynaklarını siler"),
            .german: RuleText(
                title: "Infrastruktur abbauen",
                message: "Cloud-Ressourcen, Server oder Datenbanken werden gelöscht",
                consequence: "Löscht Server oder Cloud-Ressourcen"),
            .spanish: RuleText(
                title: "Eliminación de infraestructura",
                message: "Se eliminan recursos en la nube, servidores o bases de datos",
                consequence: "Borra servidores o recursos en la nube"),
            .italian: RuleText(
                title: "Smantellamento dell'infrastruttura",
                message: "Risorse cloud, server o database vengono eliminati",
                consequence: "Elimina server o risorse cloud"),
            .french: RuleText(
                title: "Démantèlement de l'infrastructure",
                message: "Des ressources cloud, serveurs ou bases de données sont supprimés",
                consequence: "Supprime des serveurs ou ressources cloud")
        ],
        "R26": [
            .english: RuleText(
                title: "Trail erasure",
                message: "Agent transcripts, shell history or the Trailwarden index are being deleted",
                consequence: "Erases the record of what agents did"),
            .turkish: RuleText(
                title: "İz silme",
                message: "Ajan transkriptleri, kabuk geçmişi veya Trailwarden indeksi siliniyor",
                consequence: "Ajanların yaptıklarının kaydını siler"),
            .german: RuleText(
                title: "Spuren löschen",
                message: "Agent-Transkripte, Shell-Verlauf oder der Trailwarden-Index werden gelöscht",
                consequence: "Löscht die Aufzeichnung der Agenten-Aktionen"),
            .spanish: RuleText(
                title: "Borrado de rastros",
                message: "Se borran transcripciones de agentes, el historial del shell o el índice de Trailwarden",
                consequence: "Borra el registro de lo que hicieron los agentes"),
            .italian: RuleText(
                title: "Cancellazione delle tracce",
                message: "Vengono eliminati trascrizioni degli agenti, cronologia della shell o indice di "
                    + "Trailwarden",
                consequence: "Cancella la traccia di ciò che hanno fatto gli agenti"),
            .french: RuleText(
                title: "Effacement des traces",
                message: "Les transcriptions d'agents, l'historique du shell ou l'index Trailwarden sont supprimés",
                consequence: "Efface la trace de ce que les agents ont fait")
        ],
        "R27": [
            .english: RuleText(
                title: "Secret in a command",
                message: "An API key is written in plain text on the command line; it stays in the "
                    + "transcript and the shell history",
                consequence: "Leaves a secret key in your command history"),
            .turkish: RuleText(
                title: "Komutta açık anahtar",
                message: "Bir API anahtarı komut satırına açıkça yazılmış; transkriptte ve kabuk geçmişinde kalır",
                consequence: "Gizli bir anahtarı komut geçmişinizde bırakır"),
            .german: RuleText(
                title: "Schlüssel im Befehl",
                message: "Ein API-Schlüssel steht im Klartext in der Befehlszeile; er bleibt im Transkript "
                    + "und im Shell-Verlauf",
                consequence: "Hinterlässt einen geheimen Schlüssel im Verlauf"),
            .spanish: RuleText(
                title: "Clave en el comando",
                message: "Una clave de API está en texto plano en la línea de comandos; queda en la "
                    + "transcripción y en el historial del shell",
                consequence: "Deja una clave secreta en tu historial"),
            .italian: RuleText(
                title: "Chiave nel comando",
                message: "Una chiave API è scritta in chiaro nella riga di comando; resta nella trascrizione "
                    + "e nella cronologia della shell",
                consequence: "Lascia una chiave segreta nella cronologia"),
            .french: RuleText(
                title: "Clé dans la commande",
                message: "Une clé API est écrite en clair dans la ligne de commande ; elle reste dans la "
                    + "transcription et l'historique du shell",
                consequence: "Laisse une clé secrète dans votre historique")
        ],
        "R28": [
            .english: RuleText(
                title: "Risky database or deploy command",
                message: "A table is dropped or emptied, or a deployment is removed or applied without "
                    + "review",
                consequence: "Empties a table or removes a live deployment"),
            .turkish: RuleText(
                title: "Riskli veritabanı veya dağıtım komutu",
                message: "Bir tablo siliniyor veya boşaltılıyor ya da bir dağıtım onaysız kaldırılıyor veya "
                    + "uygulanıyor",
                consequence: "Bir tabloyu boşaltır veya canlı dağıtımı kaldırır"),
            .german: RuleText(
                title: "Riskanter Datenbank- oder Deploy-Befehl",
                message: "Eine Tabelle wird gelöscht oder geleert, oder ein Deployment wird ohne Prüfung "
                    + "entfernt oder angewendet",
                consequence: "Leert eine Tabelle oder entfernt ein Live-Deployment"),
            .spanish: RuleText(
                title: "Comando arriesgado de base de datos o despliegue",
                message: "Se elimina o vacía una tabla, o se quita o aplica un despliegue sin revisión",
                consequence: "Vacía una tabla o quita un despliegue en vivo"),
            .italian: RuleText(
                title: "Comando rischioso su database o deploy",
                message: "Una tabella viene eliminata o svuotata, oppure un deploy viene rimosso o applicato "
                    + "senza revisione",
                consequence: "Svuota una tabella o rimuove un deploy attivo"),
            .french: RuleText(
                title: "Commande risquée de base de données ou de déploiement",
                message: "Une table est supprimée ou vidée, ou un déploiement est retiré ou appliqué sans "
                    + "relecture",
                consequence: "Vide une table ou retire un déploiement en production")
        ],
        "R29": [
            .english: RuleText(
                title: "Secret in an agent settings file",
                message: "A token or password is saved in plain text in an agent's settings file",
                consequence: "Leaves a secret readable in a settings file"),
            .turkish: RuleText(
                title: "Ajan ayar dosyasında gizli bilgi",
                message: "Bir ajanın ayar dosyasında jeton veya parola düz metin olarak kayıtlı",
                consequence: "Ayar dosyasında okunabilir bir sır bırakır"),
            .german: RuleText(
                title: "Geheimnis in einer Agent-Einstellungsdatei",
                message: "Ein Token oder Passwort steht im Klartext in der Einstellungsdatei eines Agenten",
                consequence: "Lässt ein Geheimnis lesbar in einer Einstellungsdatei"),
            .spanish: RuleText(
                title: "Secreto en un archivo de ajustes del agente",
                message: "Un token o contraseña está guardado en texto plano en el archivo de ajustes de un agente",
                consequence: "Deja un secreto legible en un archivo de ajustes"),
            .italian: RuleText(
                title: "Segreto in un file di impostazioni dell'agente",
                message: "Un token o una password è salvato in chiaro nel file di impostazioni di un agente",
                consequence: "Lascia un segreto leggibile in un file di impostazioni"),
            .french: RuleText(
                title: "Secret dans un fichier de réglages d'agent",
                message: "Un jeton ou un mot de passe est enregistré en clair dans le fichier de réglages d'un agent",
                consequence: "Laisse un secret lisible dans un fichier de réglages")
        ]
    ]
}
