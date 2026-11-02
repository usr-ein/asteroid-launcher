#ifndef APPLAUNCHER_H
#define APPLAUNCHER_H

#include <QObject>
#include <QProcess>

class AppLauncher : public QObject
{
    Q_OBJECT
public:
    explicit AppLauncher(QObject *parent = nullptr);

    Q_INVOKABLE bool launchApp(const QString &appName);

    Q_INVOKABLE bool launchDesktopFile(const QString &desktopFile);

    // A process's command line, from /proc/<pid>/cmdline, its arguments
    // separated by spaces; "" when there's no such process.
    Q_INVOKABLE QString commandLine(qint64 pid) const;
};

#endif // APPLAUNCHER_H
