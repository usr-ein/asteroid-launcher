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
#include <QFile>
#include <QFont>
#include <QHash>
#include <QGuiApplication>
#include <QImage>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QTranslator>
#include <QVariantMap>

#include <cstdio>
#include <fcntl.h>
#include <linux/input.h>
#include <unistd.h>

#include <launchermodel.h>

#include "launchertypes.h"

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

    // Writes input events, as the kernel's evdev does, to a file such as a
    // FIFO that ButtonDoubleClick reads: each [msec, type, code, value],
    // msec the event's time. The file stays open between calls, so that a
    // FIFO's reader never sees its end.
    Q_INVOKABLE bool inputEvents(const QString &path, const QVariantList &events)
    {
        int fd = m_inputs.value(path, -1);
        if (fd < 0) {
            fd = ::open(QFile::encodeName(path).constData(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
            if (fd < 0)
                return false;
            m_inputs.insert(path, fd);
        }
        for (const QVariant &value : events) {
            const QVariantList fields = value.toList();
            if (fields.size() != 4)
                return false;
            struct input_event event = {};
            const qint64 msec = fields.at(0).toLongLong();
            event.input_event_sec = msec / 1000;
            event.input_event_usec = (msec % 1000) * 1000;
            event.type = fields.at(1).toInt();
            event.code = fields.at(2).toInt();
            event.value = fields.at(3).toInt();
            if (::write(fd, &event, sizeof(event)) != sizeof(event))
                return false;
        }
        return true;
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

private:
    QHash<QString, int> m_inputs;
};

// --load: compiles QML files as lipstick's HomeApplication does, the
// compositor's first, in an engine that has only what the launcher has at
// that point: its own types, registered as main() registers them, and the
// QML modules on the import path, with the watch's own lipstick plugin. A
// module that isn't there, or a type it lacks, fails it.
static int loadOnly(const QStringList &urls)
{
    // SONIC_LOAD_BEFORE_REGISTERING: the order that crashed the watch, to
    // check that the check catches it.
    if (qEnvironmentVariableIsEmpty("SONIC_LOAD_BEFORE_REGISTERING"))
        registerLauncherTypes();
    QQmlEngine engine;
    int failed = 0;
    for (const QString &url : urls) {
        QQmlComponent component(&engine, QUrl(url));
        if (component.isError()) {
            std::printf("FAIL %s doesn't load:\n", qPrintable(url));
            for (const QQmlError &error : component.errors())
                std::printf("     %s\n", qPrintable(error.toString()));
            ++failed;
        } else {
            std::printf("ok   %s loads\n", qPrintable(url));
        }
    }
    std::printf(failed == 0 ? "passed\n" : "%d file(s) failed\n", failed);
    return failed == 0 ? 0 : 1;
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    const QStringList args = app.arguments();
    if (args.size() >= 3 && args.at(1) == QLatin1String("--load"))
        return loadOnly(args.mid(2));
    if (argc != 2) {
        std::fprintf(stderr, "usage: %s <scene.qml> | --load <url>...\n", argv[0]);
        return 64;
    }
    // As the launcher's main.cpp and LauncherLocaleManager, with the
    // translations that test.sh compiles.
    QGuiApplication::setFont(QFont(QStringLiteral("Noto Sans")));
    QTranslator translator;
    if (translator.load(QLocale(), QStringLiteral("asteroid-launcher"), QStringLiteral("."),
                        QStringLiteral("/out/translations"), QStringLiteral(".qm")))
        app.installTranslator(&translator);
    registerLauncherTypes();
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
