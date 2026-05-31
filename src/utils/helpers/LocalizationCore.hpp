#ifndef LocalizationCore_hpp
#define LocalizationCore_hpp

#include <map>
#include <string>

class LocalizationCore {
public:
  static LocalizationCore &getInstance();

  std::string get(const std::string &key);

  void setLanguage(const std::string &lang);
  std::string getCurrentLanguage() const;

  bool isChinese() const;
  
  std::string getEffectiveLanguage() const;

  void registerTranslations(const std::string &langCode, 
                           const std::map<std::string, std::string> &translations);

private:
  LocalizationCore();
  ~LocalizationCore() = default;

  void initLanguages();

  std::map<std::string, std::map<std::string, std::string>> _allStrings;
  std::string _userLang;
};

#define REGISTER_LANGUAGE(langCode, className) \
  static struct className##Registrar { \
    className##Registrar() { \
      LocalizationCore::getInstance().registerTranslations(langCode, className::getStrings()); \
    } \
  } g_##className##Registrar;

#endif /* LocalizationCore_hpp */
