#include "applauncher.h"

#include <QFile>

AppLauncher::AppLauncher(QObject *parent) : QObject(parent)
{
}

bool AppLauncher::launchApp(const QString &appName)
{
    return QProcess::startDetached(appName);
}

bool AppLauncher::launchDesktopFile(const QString &desktopFile) {
    QString appName = desktopFile;
    if (appName.endsWith(".desktop")) {
        appName.chop(strlen(".desktop"));
    }
    return launchApp(appName);
}

QString AppLauncher::commandLine(qint64 pid) const
{
    if (pid <= 0)
        return QString();
    QFile file(QStringLiteral("/proc/%1/cmdline").arg(pid));
    if (!file.open(QIODevice::ReadOnly))
        return QString();
    QByteArray arguments = file.readAll();
    while (arguments.endsWith('\0'))
        arguments.chop(1);
    arguments.replace('\0', ' ');
    return QString::fromLocal8Bit(arguments);
}
