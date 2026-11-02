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
#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMessage>
#include <QTimer>
#include <QDateTime>
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

// ioslink's FindPhone interface on the test bus, as Sonic Screwdriver's
// bridge PROTOCOL.md § 6.10 defines it and the quick panel's Find phone
// button reads it (src/qml/quickpanel/FindPhone.qml): what's exported.
class FindPhoneObject : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sonicscrewdriver.ioslink.FindPhone")
    Q_PROPERTY(bool Ringing READ ringing SCRIPTABLE true)
    Q_PROPERTY(bool Available READ available SCRIPTABLE true)
    Q_PROPERTY(QString Problem READ problem SCRIPTABLE true)
    Q_PROPERTY(qlonglong ProblemAt READ problemAt SCRIPTABLE true)

public:
    bool ringing() const { return m_ringing; }
    bool available() const { return m_available; }
    QString problem() const { return m_problem; }
    qlonglong problemAt() const { return m_problemAt; }

    bool m_ringing = false;
    bool m_available = false;
    QString m_problem;
    qlonglong m_problemAt = 0;
    // How the call in progress ends, as the stand-in decides when it's
    // called: an error, or no reply at all, for the caller's NoReply.
    QString m_error;
    QString m_errorMessage;
    bool m_hang = false;

signals:
    void ringCalled();
    void stopCalled();

public slots:
    Q_SCRIPTABLE void Ring()
    {
        emit ringCalled();
        reply();
    }
    Q_SCRIPTABLE void Stop()
    {
        emit stopCalled();
        reply();
    }

private:
    void reply()
    {
        if (m_hang)
            setDelayedReply(true);
        else if (!m_error.isEmpty())
            sendErrorReply(m_error, m_errorMessage);
        m_error.clear();
        m_hang = false;
    }
};

// The stand-in for ioslink that a scene drives, as `ioslink`: it puts the
// FindPhone interface on the test bus, or takes it off, and answers Ring()
// and Stop() as PROTOCOL.md § 6.10 says ioslink does. It has a connection of
// its own, as ioslink is a process of its own: the launcher's calls go
// through the bus, not QtDBus's shortcut for a service of the caller's own,
// and its signals and replies come in the order it sends them. Ringing turns at once,
// before the call returns; a tap that doesn't take puts it back 300 ms later,
// with Problem set before ProblemAt. Without a session, Problem and then
// NotConnected.
class IoslinkStandIn : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available WRITE setAvailable)
    Q_PROPERTY(bool ringing READ ringing WRITE setRinging)
    // How a ring ends: "ring", it rings; "denied" (CODE_DENIED);
    // "unavailable" (CODE_UNAVAILABLE); "timeout", no answer in time;
    // "notconnected", the session gone just before the tap; "failed",
    // org.freedesktop.DBus.Error.Failed, ioslink busy; or "hang", an ioslink
    // that never replies, for the bus's NoReply.
    Q_PROPERTY(QString answer MEMBER m_answer)
    // How a stop ends: "stop", it stops; or "timeout", it doesn't take.
    Q_PROPERTY(QString stopAnswer MEMBER m_stopAnswer)
    Q_PROPERTY(int rings MEMBER m_rings)
    Q_PROPERTY(int stops MEMBER m_stops)

public:
    IoslinkStandIn()
    {
        connect(&m_object, &FindPhoneObject::ringCalled, this, [this] {
            ++m_rings;
            if (!available() || m_answer == QLatin1String("notconnected")) {
                notConnected();
            } else if (m_answer == QLatin1String("failed")) {
                setProblem(QStringLiteral("Phone didn't answer"));
                m_object.m_error = QStringLiteral("org.freedesktop.DBus.Error.Failed");
                m_object.m_errorMessage = QStringLiteral("ioslink is busy: the tap waited 20 s");
            } else if (m_answer == QLatin1String("hang")) {
                m_object.m_hang = true;
            } else {
                const QString problem = m_answer == QLatin1String("denied") ? QStringLiteral("Allow alarms in Sonic")
                    : m_answer == QLatin1String("unavailable") ? QStringLiteral("Unlock your iPhone first")
                    : m_answer == QLatin1String("timeout") ? QStringLiteral("Phone didn't answer")
                    : QString();
                tap(true, problem);
            }
        });
        connect(&m_object, &FindPhoneObject::stopCalled, this, [this] {
            ++m_stops;
            if (!available())
                notConnected();
            else
                tap(false, m_stopAnswer == QLatin1String("timeout") ? QStringLiteral("Phone didn't answer") : QString());
        });
    }

    bool available() const { return m_object.m_available; }
    void setAvailable(bool available)
    {
        m_object.m_available = available;
        changed(QStringLiteral("Available"), available);
    }
    bool ringing() const { return m_object.m_ringing; }
    void setRinging(bool ringing)
    {
        m_object.m_ringing = ringing;
        changed(QStringLiteral("Ringing"), ringing);
    }
    // A tap: Ringing at once, and back as it was, with the problem, if it
    // doesn't take.
    void tap(bool ring, const QString &problem)
    {
        const bool before = ringing();
        setRinging(ring);
        if (!problem.isEmpty()) {
            QTimer::singleShot(300, this, [this, before, problem] {
                setRinging(before);
                setProblem(problem);
            });
        }
    }
    void notConnected()
    {
        setProblem(QStringLiteral("Phone not connected"));
        m_object.m_error = QStringLiteral("org.sonicscrewdriver.ioslink.FindPhone.NotConnected");
        m_object.m_errorMessage = QStringLiteral("Phone not connected");
    }
    void setProblem(const QString &problem)
    {
        m_object.m_problem = problem;
        changed(QStringLiteral("Problem"), problem);
        m_object.m_problemAt = QDateTime::currentSecsSinceEpoch();
        changed(QStringLiteral("ProblemAt"), m_object.m_problemAt);
    }

    Q_INVOKABLE bool start()
    {
        return m_bus.registerObject(path, &m_object,
                                    QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportScriptableProperties)
            && m_bus.registerService(service);
    }

    Q_INVOKABLE void stop()
    {
        m_bus.unregisterService(service);
        m_bus.unregisterObject(path);
    }

private:
    void changed(const QString &name, const QVariant &value)
    {
        QDBusMessage signal = QDBusMessage::createSignal(path, QStringLiteral("org.freedesktop.DBus.Properties"),
                                                         QStringLiteral("PropertiesChanged"));
        signal << QStringLiteral("org.sonicscrewdriver.ioslink.FindPhone") << QVariantMap{{name, value}} << QStringList();
        m_bus.send(signal);
    }

    const QString service = QStringLiteral("org.sonicscrewdriver.ioslink");
    const QString path = QStringLiteral("/org/sonicscrewdriver/ioslink");
    QDBusConnection m_bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("ioslink"));
    FindPhoneObject m_object;
    QString m_answer = QStringLiteral("ring");
    QString m_stopAnswer = QStringLiteral("stop");
    int m_rings = 0;
    int m_stops = 0;
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
    IoslinkStandIn ioslink;
    QQuickView view;
    view.rootContext()->setContextProperty(QStringLiteral("test"), &tools);
    view.rootContext()->setContextProperty(QStringLiteral("ioslink"), &ioslink);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.resize(454, 454);
    view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (view.status() != QQuickView::Ready)
        return 1;
    view.show();
    return app.exec();
}

#include "harness.moc"
