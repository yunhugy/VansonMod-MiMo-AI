#include "LocalizationCore.hpp"

LocalizationCore &LocalizationCore::getInstance() {
  static LocalizationCore instance;
  return instance;
}

LocalizationCore::LocalizationCore() : _userLang("Auto") {
  initLanguages();
}

void LocalizationCore::initLanguages() {
  
}

std::string LocalizationCore::getEffectiveLanguage() const {
  if (_userLang == "en") return "en";
  if (_userLang == "zh-Hans" || _userLang == "zh" || _userLang == "cn") return "cn";
  if (_userLang == "zh-Hant" || _userLang == "tw") return "tw";
  if (_userLang == "ja") return "ja";
  if (_userLang == "ko") return "ko";
  if (_userLang == "vi") return "vi";
  if (_userLang == "th") return "th";
  if (_userLang == "ru") return "ru";
  if (_userLang == "es") return "es";
  if (_userLang == "pt") return "pt";
  if (_userLang == "fr") return "fr";
  if (_userLang == "de") return "de";
  if (_userLang == "ar") return "ar";
  return "en";
}

std::string LocalizationCore::get(const std::string &key) {
  std::string lang = getEffectiveLanguage();
  
  auto langIt = _allStrings.find(lang);
  if (langIt != _allStrings.end()) {
    auto keyIt = langIt->second.find(key);
    if (keyIt != langIt->second.end() && !keyIt->second.empty()) {
      return keyIt->second;
    }
  }
  
  if (lang != "en") {
    langIt = _allStrings.find("en");
    if (langIt != _allStrings.end()) {
      auto keyIt = langIt->second.find(key);
      if (keyIt != langIt->second.end() && !keyIt->second.empty()) {
        return keyIt->second;
      }
    }
  }
  
  return key;
}

void LocalizationCore::setLanguage(const std::string &lang) {
  _userLang = lang;
}

std::string LocalizationCore::getCurrentLanguage() const {
  return _userLang;
}

bool LocalizationCore::isChinese() const {
  std::string eff = getEffectiveLanguage();
  return (eff == "cn" || eff == "tw");
}

void LocalizationCore::registerTranslations(const std::string &langCode,
                                            const std::map<std::string, std::string> &translations) {
  _allStrings[langCode] = translations;
}
