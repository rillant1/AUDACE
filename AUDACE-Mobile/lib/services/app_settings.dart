// Paramètres globaux de l'application — singleton accessible partout.
// Actuellement : gère uniquement le code langue (fr/en) avec persistance SharedPreferences.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Singleton des paramètres applicatifs
class AppSettings {
  // Instance unique partagée dans toute l'application
  static final AppSettings _instance = AppSettings._();
  // Constructeur factory — renvoie toujours la même instance
  factory AppSettings() => _instance;
  // Constructeur privé — empêche l'instanciation directe
  AppSettings._();

  // Clé de stockage SharedPreferences pour la langue choisie
  static const _langKey = 'language_code';

  // ValueNotifier permet aux widgets de s'abonner aux changements de langue
  // et de se reconstruire automatiquement sans setState global
  final ValueNotifier<String> languageCode = ValueNotifier('fr');

  // Charge la langue sauvegardée depuis SharedPreferences au démarrage
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Si aucune langue n'a été enregistrée, "fr" est la valeur par défaut
    languageCode.value = prefs.getString(_langKey) ?? 'fr';
  }

  // Sauvegarde la nouvelle langue et notifie tous les écouteurs immédiatement
  Future<void> setLanguage(String code) async {
    // Mise à jour du ValueNotifier → tous les ValueListenableBuilder se reconstruisent
    languageCode.value = code;
    // Persistance pour que le choix survive au redémarrage de l'app
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, code);
  }
}
