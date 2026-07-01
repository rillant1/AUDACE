// Module de chiffrement et d'anonymisation locale.
// Génère un identifiant d'appareil anonyme et stable, impossible à relier
// nominativement au citoyen, en combinant un UUID d'installation aléatoire avec
// un sel cryptographique local de 256 bits, puis en appliquant SHA-256.
//
// NOTE : le document de référence parle de masquer l'"IMEI/UUID". La lecture
// de l'IMEI est restreinte par Android (permission privilégiée) et serait contraire
// à l'objectif d'anonymisation. On utilise donc un UUID généré une seule fois à
// l'installation, jamais transmis en clair — seule son empreinte SHA-256 l'est.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

// Interface abstraite pour le stockage persistant du couple (UUID, sel).
// Permet d'injecter une implémentation en mémoire dans les tests unitaires
// sans dépendre du système de fichiers de la plateforme.
abstract class SaltStore {
  Future<String?> readInstallationId();       // Lit l'UUID d'installation
  Future<void>    writeInstallationId(String id); // Persiste l'UUID d'installation
  Future<String?> readSalt();                 // Lit le sel cryptographique
  Future<void>    writeSalt(String salt);     // Persiste le sel cryptographique
}

// Implémentation de production — persiste dans des fichiers cachés du répertoire
// applicatif (jamais exposé à d'autres apps, jamais synchronisé dans le cloud).
class FileSaltStore implements SaltStore {
  // Retourne un handle vers le fichier caché (préfixé par un point)
  Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    // Les fichiers commencent par "." pour être cachés sur Linux/Mac
    return File('${dir.path}/.netprobe_$name');
  }

  @override
  Future<String?> readInstallationId() => _read('install_id'); // Fichier : .netprobe_install_id

  @override
  Future<void> writeInstallationId(String id) => _write('install_id', id);

  @override
  Future<String?> readSalt() => _read('salt'); // Fichier : .netprobe_salt

  @override
  Future<void> writeSalt(String salt) => _write('salt', salt);

  // Lecture sécurisée : retourne null si le fichier n'existe pas ou est vide
  Future<String?> _read(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return null;
      final content = (await f.readAsString()).trim();
      return content.isEmpty ? null : content; // Fichier vide = pas de donnée
    } catch (_) {
      return null;
    }
  }

  // Écriture avec flush immédiat (force la persistance sur disque)
  Future<void> _write(String name, String value) async {
    final f = await _file(name);
    await f.writeAsString(value, flush: true);
  }
}

// Implémentation en mémoire — utilisée uniquement dans les tests unitaires.
// Les valeurs sont perdues à la fin du test (pas de persistance).
class InMemorySaltStore implements SaltStore {
  String? _installationId;
  String? _salt;

  @override
  Future<String?> readInstallationId() async => _installationId;

  @override
  Future<void> writeInstallationId(String id) async => _installationId = id;

  @override
  Future<String?> readSalt() async => _salt;

  @override
  Future<void> writeSalt(String salt) async => _salt = salt;
}

class SecurityCryptoEngine {
  // Singleton de production — utilise FileSaltStore par défaut
  static final SecurityCryptoEngine _instance =
      SecurityCryptoEngine._internal(FileSaltStore());
  factory SecurityCryptoEngine() => _instance;

  // Constructeur de test — permet d'injecter un SaltStore en mémoire
  SecurityCryptoEngine.test(SaltStore store) : _store = store;

  SecurityCryptoEngine._internal(this._store);

  final SaltStore _store;

  // Cache en mémoire de l'identifiant anonyme — évite de relire les fichiers
  // à chaque collecte (l'identifiant est stable pendant toute la session)
  String? _cachedAnonymousId;

  // Retourne l'identifiant anonyme stable de cet appareil.
  // Calculé une seule fois à l'installation puis mis en cache mémoire.
  // L'identifiant est un SHA-256 de (UUID_installation + sel_256bits).
  Future<String> getAnonymousDeviceId() async {
    // Retourne le cache si disponible
    if (_cachedAnonymousId != null) return _cachedAnonymousId!;

    // Récupère ou génère l'UUID d'installation (stable après le premier lancement)
    var installationId = await _store.readInstallationId();
    if (installationId == null) {
      installationId = const Uuid().v4(); // UUID aléatoire version 4
      await _store.writeInstallationId(installationId);
    }

    // Récupère ou génère le sel cryptographique (256 bits = 32 octets en hex)
    var salt = await _store.readSalt();
    if (salt == null) {
      salt = _generateSalt();
      await _store.writeSalt(salt);
    }

    // Calcule et met en cache le SHA-256 de "UUID:sel"
    _cachedAnonymousId = hashDeviceAnonymously(installationId, salt);
    return _cachedAnonymousId!;
  }

  // Applique le hachage SHA-256 sur la concaténation "deviceIdentifier:salt".
  // Méthode pure et exposée publiquement pour la testabilité du déterminisme.
  // Le même couple (id, sel) produit toujours le même hash.
  String hashDeviceAnonymously(String deviceIdentifier, String salt) {
    final bytes = utf8.encode('$deviceIdentifier:$salt'); // Encodage UTF-8
    return sha256.convert(bytes).toString();              // Hash hex 64 caractères
  }

  // Génère un sel cryptographique de 32 octets (256 bits) encodé en hexadécimal.
  // Utilise Random.secure() (CSPRNG) pour garantir l'imprévisibilité.
  String _generateSalt() {
    final random = Random.secure();
    // 32 octets aléatoires → représentation hexadécimale sur 64 caractères
    final values = List<int>.generate(32, (_) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
