#pragma once

#include <string>
#include <vector>

class BackupCore {
public:
    static BackupCore& getInstance();

    BackupCore(const BackupCore&) = delete;
    BackupCore& operator=(const BackupCore&) = delete;

    std::string getBackupFolder();

    std::string backupApp(const std::string& bundleID, const std::string& srcDataPath);

    bool restoreApp(const std::string& bundleID, const std::string& backupPath, const std::string& targetDataPath);

    std::vector<std::string> getBackups(const std::string& bundleID);

    void deleteBackup(const std::string& path);

    void fixPermissions(const std::string& path);

private:
    BackupCore() = default;
    ~BackupCore() = default;
};
