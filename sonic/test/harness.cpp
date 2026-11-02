/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The launcher's QML off the watch, for sonic/test/test.sh: a 454 × 454 view,
 * the watch's screen, that loads one scene (sonic/test/<scene>.qml). A scene
 * stands in for MainScreen around the fork's own QML, which is compiled in
 * from src/resources-qml.qrc as in the launcher, with the fork's C++ types and
 * lipstick's real LauncherModel. `test` gives the scene a shell, a log and
 * the exit status.
 */

#include <QColor>
#include <QFont>
#include <QGuiApplication>
#include <QImage>
#include <QProcess>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QVariantMap>

#include <cstdio>

#include <launchermodel.h>

#include "applauncher.h"
#include "applauncherbackground.h"
#include "applistmodel.h"

class TestTools : public QObject
{
    Q_OBJECT

public:
    // Runs a shell command: {"status": its exit status, "output": stdout and stderr}.
    Q_INVOKABLE QVariantMap sh(const QString &command)
    {
        QProcess process;
        process.setProcessChannelMode(QProcess::MergedChannels);
        process.start(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), command});
        process.waitForFinished(120000);
        const int status = process.exitStatus() == QProcess::NormalExit ? process.exitCode() : -1;
        return {{QStringLiteral("status"), status},
                {QStringLiteral("output"), QString::fromUtf8(process.readAll())}};
    }

    // The share of a screenshot's pixels, in a rectangle, within `tolerance`
    // of a colour on each of red, green and blue: 0 to 1, or -1 when the file
    // can't be read.
    Q_INVOKABLE double share(const QString &file, int x, int y, int width, int height,
                             const QString &colour, int tolerance)
    {
        const QImage image(file);
        if (image.isNull())
            return -1;
        const QColor want(colour);
        const QRect area = QRect(x, y, width, height).intersected(image.rect());
        int matching = 0;
        for (int py = area.top(); py <= area.bottom(); ++py) {
            for (int px = area.left(); px <= area.right(); ++px) {
                const QColor got = image.pixelColor(px, py);
                if (qAbs(got.red() - want.red()) <= tolerance && qAbs(got.green() - want.green()) <= tolerance
                        && qAbs(got.blue() - want.blue()) <= tolerance)
                    ++matching;
            }
        }
        return area.isEmpty() ? 0 : double(matching) / (area.width() * area.height());
    }

    Q_INVOKABLE void log(const QString &line)
    {
        std::printf("%s\n", qPrintable(line));
        std::fflush(stdout);
    }

    Q_INVOKABLE void exit(int status)
    {
        QCoreApplication::exit(status);
    }
};

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc != 2) {
        std::fprintf(stderr, "usage: %s <scene.qml>\n", argv[0]);
        return 64;
    }
    // As the launcher's main.cpp.
    QGuiApplication::setFont(QFont(QStringLiteral("Noto Sans")));
    qmlRegisterType<AppLauncherBackground>("org.asteroid.launcher", 1, 0, "AppLauncherBackground");
    qmlRegisterType<AppLauncher>("org.asteroid.launcher", 1, 0, "AppLauncher");
    qmlRegisterType<AppListModel>("org.asteroid.launcher", 1, 0, "AppListModel");
    qmlRegisterAnonymousType<QAbstractItemModel>("org.asteroid.launcher", 1);
    // lipstick's QML plugin isn't in the SDK; its library is the watch's own.
    qmlRegisterType<LauncherModel>("org.nemomobile.lipstick", 0, 1, "LauncherModel");

    TestTools tools;
    QQuickView view;
    view.rootContext()->setContextProperty(QStringLiteral("test"), &tools);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.resize(454, 454);
    view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (view.status() != QQuickView::Ready)
        return 1;
    view.show();
    return app.exec();
}

#include "harness.moc"
