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
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QTranslator>
#include <QVariantMap>

#include <cmath>
#include <cstdio>
#include <ctime>
#include <functional>
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

    // The boot-time clock now, in ms: the clock that the kernel stamps input
    // events with, and that ButtonDoubleClick counts their age on.
    Q_INVOKABLE qint64 bootMs() const
    {
        struct timespec now;
        ::clock_gettime(CLOCK_BOOTTIME, &now);
        return qint64(now.tv_sec) * 1000 + qint64(now.tv_nsec) / 1000000;
    }

    // The CPU time that this process has used so far, in ms.
    Q_INVOKABLE double cpuMs() const
    {
        struct timespec used;
        ::clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &used);
        return double(used.tv_sec) * 1000 + double(used.tv_nsec) / 1000000;
    }

    // The pixels of a screenshot farther than `radius` from (cx, cy) that
    // aren't black, with some channel above `threshold` (0 to 255): {"count":
    // how many, "x", "y" and "value": the first, "value" its brightest
    // channel}, or {"count": -1} when the file can't be read.
    Q_INVOKABLE QVariantMap outside(const QString &file, double cx, double cy, double radius, int threshold)
    {
        const QImage image(file);
        if (image.isNull())
            return {{QStringLiteral("count"), -1}};
        int count = 0, firstX = -1, firstY = -1, firstValue = 0;
        for (int y = 0; y < image.height(); ++y) {
            for (int x = 0; x < image.width(); ++x) {
                const double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
                if (dx * dx + dy * dy <= radius * radius)
                    continue;
                const QColor got = image.pixelColor(x, y);
                const int value = qMax(got.red(), qMax(got.green(), got.blue()));
                if (value <= threshold)
                    continue;
                if (count++ == 0) {
                    firstX = x;
                    firstY = y;
                    firstValue = value;
                }
            }
        }
        return {{QStringLiteral("count"), count}, {QStringLiteral("x"), firstX},
                {QStringLiteral("y"), firstY}, {QStringLiteral("value"), firstValue}};
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


// mce's signal interface, as the stand-in sends it: the touch lock's mode, and
// whether a blanking pause is allowed (mce's tklock.c and display.c). It is
// introspectable, as mce's is, which Nemo.DBus needs to connect a signal.
class MceSignals : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "com.nokia.mce.signal")

signals:
    Q_SCRIPTABLE void tklock_mode_ind(const QString &mode);
    Q_SCRIPTABLE void display_blanking_pause_allowed_ind(bool allowed);
    Q_SCRIPTABLE void display_status_ind(const QString &status);
};

// mce's request interface on the system bus, which is the test bus here, as
// the launcher's VoiceNoteHold calls it: the CPU keepalive, the display's
// wake, the touch lock and the blanking pause. It records each call, with its
// time, and plays mce's own rules for the display (mce 1.109's tklock.c and
// display.c, the watch's build):
// - the display: "off", "powering" (on its way, after req_display_state_on)
//   or "on", which it reaches powerUpMs after the request;
// - the touch lock: unlocking is denied unless the display is on or on its way
//   ("tkunlock denied due to display=OFF"), locking always allowed, and the
//   mode signalled after every request, a denied one too;
// - a blanking pause is allowed only with the display on and the touch lock
//   off; a pause asked otherwise is ignored, and one held is dropped as soon as
//   it isn't allowed. A pause lasts pauseMs;
// - the display blanks lockBlankMs after it came on while the touch lock is
//   locked ("blank from lockscreen"), blankMs while it is unlocked, and never
//   while a pause is held; when it blanks, the touch lock locks. Either at 0,
//   as they start, never: a scene sets them where it tests them.
class MceObject : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "com.nokia.mce.request")

public:
    MceObject()
    {
        m_power.setSingleShot(true);
        m_blank.setSingleShot(true);
        connect(&m_power, &QTimer::timeout, this, [this] {
            if (m_display == QLatin1String("powering"))
                setDisplay(QStringLiteral("on"), QStringLiteral("the display is on"));
        });
        connect(&m_blank, &QTimer::timeout, this, [this] { blanked(); });
    }

    QStringList m_calls;
    QVariantList m_times;
    int m_period = 60;
    // What mce did, in order: "display on", "unlock denied: display off",
    // "unlocked", "locked", "pause held", "pause ignored", "pause dropped",
    // "blanked: locked" or "blanked: unlocked".
    QStringList m_events;
    QVariantList m_eventTimes;
    // The calls, each "mce <call>", and the events, in the order they came.
    QStringList m_log;
    QString m_display = QStringLiteral("on");
    QString m_tklock = QStringLiteral("locked");
    bool m_allowed = false;
    qint64 m_pauseUntil = 0;
    int m_powerUpMs = 300;
    int m_lockBlankMs = 0;
    int m_blankMs = 0;
    int m_pauseMs = 60000;
    MceSignals m_signals;
    // Tells the scene the display's state, as lipstick's displayOn and
    // displayOff do.
    std::function<void(bool)> m_displayChanged;

    // The state a scene starts from, with no signal: the display and the touch
    // lock as they are, no pause, and the blank timer from now.
    void reset(const QString &display, const QString &tklock)
    {
        m_power.stop();
        m_display = display;
        m_tklock = tklock;
        m_pauseUntil = 0;
        m_allowed = m_display == QLatin1String("on") && m_tklock == QLatin1String("unlocked");
        m_shownOn = now();
        rethink();
    }

    // What the display does: the blank timer, from the last time it came on or
    // the pause's end.
    void rethink()
    {
        m_blank.stop();
        if (m_display != QLatin1String("on"))
            return;
        const qint64 t = now();
        if (m_pauseUntil > t) {
            m_blank.start(int(m_pauseUntil - t));
            return;
        }
        const qint64 from = qMax(m_shownOn, m_pauseEnded);
        const int timeout = m_tklock == QLatin1String("locked") ? m_lockBlankMs : m_blankMs;
        if (timeout > 0)
            m_blank.start(int(qMax<qint64>(0, from + timeout - t)));
    }

public slots:
    Q_SCRIPTABLE int req_cpu_keepalive_period(const QString &session)
    {
        record(QStringLiteral("req_cpu_keepalive_period %1").arg(session));
        return m_period;
    }
    Q_SCRIPTABLE bool req_cpu_keepalive_start(const QString &session)
    {
        record(QStringLiteral("req_cpu_keepalive_start %1").arg(session));
        return true;
    }
    Q_SCRIPTABLE bool req_cpu_keepalive_stop(const QString &session)
    {
        record(QStringLiteral("req_cpu_keepalive_stop %1").arg(session));
        return true;
    }
    Q_SCRIPTABLE void req_display_state_on()
    {
        record(QStringLiteral("req_display_state_on"));
        if (m_display == QLatin1String("off")) {
            m_display = QStringLiteral("powering");
            m_power.start(m_powerUpMs);
            evaluate();
        } else if (m_display == QLatin1String("on")) {
            m_shownOn = now();
            rethink();
        }
    }
    Q_SCRIPTABLE void req_tklock_mode_change(const QString &mode)
    {
        record(QStringLiteral("req_tklock_mode_change %1").arg(mode));
        if (mode == QLatin1String("unlocked")) {
            if (m_display == QLatin1String("off")) {
                event(QStringLiteral("unlock denied: display off"));
            } else if (m_tklock != QLatin1String("unlocked")) {
                m_tklock = QStringLiteral("unlocked");
                event(QStringLiteral("unlocked"));
            }
        } else if (mode.startsWith(QLatin1String("locked"))) {
            if (m_tklock != QLatin1String("locked")) {
                m_tklock = QStringLiteral("locked");
                event(QStringLiteral("locked"));
            }
        }
        evaluate();
        rethink();
        // After every request, as mce's ui notify does, a moment later.
        QTimer::singleShot(0, this, [this] { emit m_signals.tklock_mode_ind(m_tklock); });
    }
    Q_SCRIPTABLE QString get_tklock_mode()
    {
        record(QStringLiteral("get_tklock_mode"));
        return m_tklock;
    }
    Q_SCRIPTABLE bool get_display_blanking_pause_allowed()
    {
        record(QStringLiteral("get_display_blanking_pause_allowed"));
        return m_allowed;
    }
    Q_SCRIPTABLE void req_display_blanking_pause()
    {
        record(QStringLiteral("req_display_blanking_pause"));
        if (!m_allowed) {
            event(QStringLiteral("pause ignored"));
            return;
        }
        m_pauseUntil = now() + m_pauseMs;
        event(QStringLiteral("pause held"));
        rethink();
    }
    Q_SCRIPTABLE void req_display_cancel_blanking_pause()
    {
        record(QStringLiteral("req_display_cancel_blanking_pause"));
        if (m_pauseUntil > 0) {
            m_pauseUntil = 0;
            m_pauseEnded = now();
            rethink();
        }
    }

private:
    static qint64 now() { return QDateTime::currentMSecsSinceEpoch(); }

    void record(const QString &call)
    {
        m_calls << call;
        m_times << double(now());
        m_log << QStringLiteral("mce ") + call;
    }

    void event(const QString &what)
    {
        m_events << what;
        m_eventTimes << double(now());
        m_log << what;
    }

    // Whether a pause is allowed, signalled when it changes; a pause held is
    // dropped when it stops being allowed.
    void evaluate()
    {
        const bool allowed = m_display == QLatin1String("on") && m_tklock == QLatin1String("unlocked");
        if (allowed == m_allowed)
            return;
        m_allowed = allowed;
        if (!allowed && m_pauseUntil > 0) {
            m_pauseUntil = 0;
            m_pauseEnded = now();
            event(QStringLiteral("pause dropped"));
        }
        emit m_signals.display_blanking_pause_allowed_ind(allowed);
    }

    void setDisplay(const QString &state, const QString &what)
    {
        m_display = state;
        event(what);
        const bool on = state == QLatin1String("on");
        if (on)
            m_shownOn = now();
        emit m_signals.display_status_ind(on ? QStringLiteral("on") : QStringLiteral("off"));
        if (m_displayChanged)
            m_displayChanged(on);
        evaluate();
        rethink();
    }

    // The blank timer's end: a pause that lapsed, or the display off, and the
    // touch lock locked with it.
    void blanked()
    {
        if (m_display != QLatin1String("on"))
            return;
        if (m_pauseUntil > 0) {
            if (m_pauseUntil > now()) {
                rethink();
                return;
            }
            m_pauseUntil = 0;
            m_pauseEnded = now();
            event(QStringLiteral("pause lapsed"));
            rethink();
            return;
        }
        const QString was = m_tklock;
        m_tklock = QStringLiteral("locked");
        setDisplay(QStringLiteral("off"), QStringLiteral("blanked: %1").arg(was));
        emit m_signals.tklock_mode_ind(m_tklock);
    }

    QTimer m_power;
    QTimer m_blank;
    qint64 m_shownOn = 0;
    qint64 m_pauseEnded = 0;
};

// The stand-in for mce that a scene drives, as `mce`.
class MceStandIn : public QObject
{
    Q_OBJECT
    // Every call so far, as "method argument", and the time of each, in ms
    // since the epoch.
    Q_PROPERTY(QStringList calls READ calls)
    Q_PROPERTY(QVariantList times READ times)
    // What mce did with them, and when (MceObject's events), and both in the
    // order they came: "mce <call>" and the events.
    Q_PROPERTY(QStringList events READ events)
    Q_PROPERTY(QVariantList eventTimes READ eventTimes)
    Q_PROPERTY(QStringList log READ log)
    // What req_cpu_keepalive_period answers, in seconds.
    Q_PROPERTY(int period READ period WRITE setPeriod)
    // The display ("off", "powering", "on"), the touch lock ("locked",
    // "unlocked"), whether a pause is allowed, and whether one is held.
    Q_PROPERTY(QString display READ display)
    Q_PROPERTY(QString tklock READ tklock)
    Q_PROPERTY(bool allowed READ allowed)
    Q_PROPERTY(bool paused READ paused)
    // mce's times, in ms: the display's power up, the blank from the
    // lockscreen, the usual blank, and a pause's length.
    Q_PROPERTY(int powerUpMs READ powerUpMs WRITE setPowerUpMs)
    Q_PROPERTY(int lockBlankMs READ lockBlankMs WRITE setLockBlankMs)
    Q_PROPERTY(int blankMs READ blankMs WRITE setBlankMs)
    Q_PROPERTY(int pauseMs READ pauseMs WRITE setPauseMs)

public:
    MceStandIn()
    {
        m_object.m_displayChanged = [this](bool on) { emit displayChanged(on); };
    }

    QStringList calls() const { return m_object.m_calls; }
    QVariantList times() const { return m_object.m_times; }
    QStringList events() const { return m_object.m_events; }
    QVariantList eventTimes() const { return m_object.m_eventTimes; }
    QStringList log() const { return m_object.m_log; }
    int period() const { return m_object.m_period; }
    void setPeriod(int period) { m_object.m_period = period; }
    QString display() const { return m_object.m_display; }
    QString tklock() const { return m_object.m_tklock; }
    bool allowed() const { return m_object.m_allowed; }
    bool paused() const { return m_object.m_pauseUntil > QDateTime::currentMSecsSinceEpoch(); }
    int powerUpMs() const { return m_object.m_powerUpMs; }
    void setPowerUpMs(int ms) { m_object.m_powerUpMs = ms; }
    int lockBlankMs() const { return m_object.m_lockBlankMs; }
    void setLockBlankMs(int ms) { m_object.m_lockBlankMs = ms; m_object.rethink(); }
    int blankMs() const { return m_object.m_blankMs; }
    void setBlankMs(int ms) { m_object.m_blankMs = ms; m_object.rethink(); }
    int pauseMs() const { return m_object.m_pauseMs; }
    void setPauseMs(int ms) { m_object.m_pauseMs = ms; }

    Q_INVOKABLE bool start()
    {
        return m_bus.registerObject(path, &m_object, QDBusConnection::ExportScriptableSlots)
            && m_bus.registerObject(signalPath, &m_object.m_signals, QDBusConnection::ExportScriptableSignals)
            && m_bus.registerService(service);
    }
    Q_INVOKABLE void stop()
    {
        m_bus.unregisterService(service);
        m_bus.unregisterObject(signalPath);
        m_bus.unregisterObject(path);
    }
    Q_INVOKABLE void clear()
    {
        m_object.m_calls.clear();
        m_object.m_times.clear();
        m_object.m_events.clear();
        m_object.m_eventTimes.clear();
        m_object.m_log.clear();
    }
    // Where a scene starts: the display ("on" or "off") and the touch lock
    // ("locked" or "unlocked"), with no pause, and no signal.
    Q_INVOKABLE void reset(const QString &display, const QString &tklock) { m_object.reset(display, tklock); }

signals:
    // The display came on or went off, as lipstick tells the compositor.
    void displayChanged(bool on);

private:
    const QString service = QStringLiteral("com.nokia.mce");
    const QString path = QStringLiteral("/com/nokia/mce/request");
    const QString signalPath = QStringLiteral("/com/nokia/mce/signal");
    QDBusConnection m_bus = QDBusConnection::connectToBus(QDBusConnection::SystemBus, QStringLiteral("mce"));
    MceObject m_object;
};

// ioslink's VoiceNotes interface on the test bus, as Sonic Screwdriver's
// bridge PROTOCOL.md § 6.14.4 defines it and the launcher's recording screen
// and button read it: what's exported. It behaves as ioslink does, with the
// answers a test chooses.
class VoiceNotesObject : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sonicscrewdriver.ioslink.VoiceNotes")
    Q_PROPERTY(QString State READ state SCRIPTABLE true)

public:
    QString state() const { return m_state; }

    QString m_state = QStringLiteral("{\"onWatch\":0,\"cacheBytes\":0,\"capBytes\":0,\"connected\":false}");
    // How an Arm ends: "id", a note; "refused", "" with State's reason;
    // "busy", the Busy error; "hang", no answer at all.
    QString m_answer = QStringLiteral("id");
    QString m_refusal = QStringLiteral("storage");
    int m_armDelay = 0;
    // How a Stop ends: "auto", saved or too short by the length; or "saved",
    // "dropped", "limit", "tooShort" or "failed", as chosen.
    QString m_outcome = QStringLiteral("auto");
    int m_stopDelay = 80;
    bool m_connected = true;
    int m_onWatch = 1;
    QVariantList m_drops;
    QStringList m_calls;
    QVariantList m_times;
    // The errors it answered with, each "Busy" or "NotFound <id>".
    QStringList m_errors;

    QString m_id;
    // The note that ended last: a call for it, which a release crossing the
    // note's own end makes, is no error and does nothing (PROTOCOL.md § 6.14.4).
    QString m_ended;
    bool m_active = false;
    qlonglong m_pressedAt = 0;
    qlonglong m_startedAt = 0;
    int m_serial = 0;
    QJsonObject m_last;

    // Sends State's change, as ioslink's PropertiesChanged does.
    std::function<void(const QString &)> m_changed;

    void publish(const QString &phase)
    {
        QJsonObject state;
        if (m_active) {
            state.insert(QStringLiteral("recording"),
                         QJsonObject{{QStringLiteral("id"), m_id}, {QStringLiteral("startedAt"), double(m_startedAt)},
                                     {QStringLiteral("phase"), phase}});
        }
        if (!m_last.isEmpty())
            state.insert(QStringLiteral("last"), m_last);
        state.insert(QStringLiteral("onWatch"), m_onWatch);
        state.insert(QStringLiteral("cacheBytes"), 0);
        state.insert(QStringLiteral("capBytes"), 0);
        state.insert(QStringLiteral("connected"), m_connected);
        m_state = QString::fromUtf8(QJsonDocument(state).toJson(QJsonDocument::Compact));
        if (m_changed)
            m_changed(m_state);
    }

    // A note's end: State's `last`, and no `recording`.
    void finish(const QString &id, qlonglong durationMs, const QString &outcome, const QString &reason = QString())
    {
        m_active = false;
        m_ended = id;
        QJsonArray dropped;
        for (const QVariant &drop : qAsConst(m_drops))
            dropped.append(QJsonObject::fromVariantMap(drop.toMap()));
        m_last = QJsonObject{{QStringLiteral("id"), id}, {QStringLiteral("outcome"), outcome},
                             {QStringLiteral("durationMs"), double(durationMs)}, {QStringLiteral("dropped"), dropped},
                             {QStringLiteral("reason"), reason}};
        publish(QString());
    }

    // ioslink's own stop, at 10:00, while the button is still held.
    void limit()
    {
        if (m_active)
            finish(m_id, 600000, QStringLiteral("limit"));
    }

signals:
    Q_SCRIPTABLE void Levels(const QString &id, uint fromMs, const QList<int> &centibels);

public slots:
    Q_SCRIPTABLE QString Arm(qlonglong pressedAt)
    {
        record(QStringLiteral("Arm %1").arg(pressedAt));
        if (m_answer == QLatin1String("busy")) {
            m_errors << QStringLiteral("Busy");
            sendErrorReply(QStringLiteral("org.sonicscrewdriver.ioslink.VoiceNotes.Error.Busy"),
                           QStringLiteral("a note is already recording"));
            return QString();
        }
        if (m_answer == QLatin1String("hang")) {
            setDelayedReply(true);
            return QString();
        }
        QString id;
        if (m_answer == QLatin1String("refused")) {
            m_last = QJsonObject{{QStringLiteral("id"), QString()}, {QStringLiteral("outcome"), QStringLiteral("failed")},
                                 {QStringLiteral("durationMs"), 0}, {QStringLiteral("dropped"), QJsonArray()},
                                 {QStringLiteral("reason"), m_refusal}};
            m_active = false;
            publish(QString());
        } else {
            id = QStringLiteral("NOTE-%1").arg(++m_serial);
            m_id = id;
            m_active = true;
            m_pressedAt = pressedAt;
            // The press' boot-time stamp, on the wall clock.
            const qlonglong age = qBound<qlonglong>(0, bootMs() - pressedAt, 5000);
            m_startedAt = QDateTime::currentMSecsSinceEpoch() - age;
            publish(QStringLiteral("armed"));
        }
        if (m_armDelay > 0) {
            setDelayedReply(true);
            const QDBusMessage request = message();
            QDBusConnection bus = connection();
            QTimer::singleShot(m_armDelay, this, [request, bus, id]() mutable {
                bus.send(request.createReply(id));
            });
            return QString();
        }
        return id;
    }

    Q_SCRIPTABLE void Keep(const QString &id)
    {
        record(QStringLiteral("Keep %1").arg(id));
        if (!known(id))
            return;
        publish(QStringLiteral("recording"));
    }

    Q_SCRIPTABLE void Stop(const QString &id, qlonglong releasedAt)
    {
        record(QStringLiteral("Stop %1 %2").arg(id).arg(releasedAt));
        if (!known(id))
            return;
        const qlonglong duration = qMax<qlonglong>(0, releasedAt - m_pressedAt);
        publish(QStringLiteral("saving"));
        QTimer::singleShot(m_stopDelay, this, [this, id, duration] {
            if (!m_active || m_id != id)
                return;
            QString outcome = m_outcome;
            if (outcome == QLatin1String("auto"))
                outcome = duration < 1000 ? QStringLiteral("tooShort") : QStringLiteral("saved");
            finish(id, duration, outcome, outcome == QLatin1String("failed") ? QStringLiteral("storage") : QString());
        });
    }

    Q_SCRIPTABLE void Cancel(const QString &id)
    {
        record(QStringLiteral("Cancel %1").arg(id));
        if (!known(id))
            return;
        m_active = false;
        m_ended = id;
        publish(QString());
    }

private:
    static qint64 bootMs()
    {
        struct timespec now;
        ::clock_gettime(CLOCK_BOOTTIME, &now);
        return qint64(now.tv_sec) * 1000 + qint64(now.tv_nsec) / 1000000;
    }

    void record(const QString &call)
    {
        m_calls << call;
        m_times << double(QDateTime::currentMSecsSinceEpoch());
    }

    // Whether a call's note records. A call for the note that ended last is
    // no error and does nothing; NotFound is for an id that no note had.
    bool known(const QString &id)
    {
        if (m_active && id == m_id)
            return true;
        if (!id.isEmpty() && id == m_ended)
            return false;
        m_errors << QStringLiteral("NotFound %1").arg(id);
        sendErrorReply(QStringLiteral("org.sonicscrewdriver.ioslink.VoiceNotes.Error.NotFound"),
                       QStringLiteral("no note %1").arg(id));
        return false;
    }
};

// The stand-in for ioslink's VoiceNotes that a scene drives, as `voicenotes`.
// It has a connection of its own, as ioslink is a process of its own, and is
// the service org.sonicscrewdriver.ioslink on the test bus once it starts: a
// scene starts either this or `ioslink`, the FindPhone one, not both.
class VoiceNotesStandIn : public QObject
{
    Q_OBJECT
    // How an Arm ends: "id", "refused", "busy" or "hang"; for "refused", why:
    // "storage" or "microphone"; and how long its answer takes, in ms.
    Q_PROPERTY(QString answer READ answer WRITE setAnswer)
    Q_PROPERTY(QString refusal READ refusal WRITE setRefusal)
    Q_PROPERTY(int armDelay READ armDelay WRITE setArmDelay)
    // How a Stop ends, after stopDelay ms of "saving": "auto", "saved",
    // "dropped", "limit", "tooShort" or "failed".
    Q_PROPERTY(QString outcome READ outcome WRITE setOutcome)
    Q_PROPERTY(int stopDelay READ stopDelay WRITE setStopDelay)
    // What State says besides: whether the iPhone is connected, how many
    // notes wait on the watch, and the notes dropped, each {startedAt,
    // durationMs}.
    Q_PROPERTY(bool connectedState READ connectedState WRITE setConnectedState)
    Q_PROPERTY(int onWatch READ onWatch WRITE setOnWatch)
    Q_PROPERTY(QVariantList drops READ drops WRITE setDrops)
    // Every call so far, as "Method argument...", and the time of each.
    Q_PROPERTY(QStringList calls READ calls)
    Q_PROPERTY(QVariantList times READ times)
    // The errors it answered with: "Busy", or "NotFound <id>".
    Q_PROPERTY(QStringList errors READ errors)
    // The id of the note that records, or "".
    Q_PROPERTY(QString recording READ recording)
    Q_PROPERTY(QString state READ state)

public:
    VoiceNotesStandIn()
    {
        m_object.m_changed = [this](const QString &json) { changed(QStringLiteral("State"), json); };
    }

    QString answer() const { return m_object.m_answer; }
    void setAnswer(const QString &answer) { m_object.m_answer = answer; }
    QString refusal() const { return m_object.m_refusal; }
    void setRefusal(const QString &refusal) { m_object.m_refusal = refusal; }
    int armDelay() const { return m_object.m_armDelay; }
    void setArmDelay(int ms) { m_object.m_armDelay = ms; }
    QString outcome() const { return m_object.m_outcome; }
    void setOutcome(const QString &outcome) { m_object.m_outcome = outcome; }
    int stopDelay() const { return m_object.m_stopDelay; }
    void setStopDelay(int ms) { m_object.m_stopDelay = ms; }
    bool connectedState() const { return m_object.m_connected; }
    void setConnectedState(bool connected) { m_object.m_connected = connected; }
    int onWatch() const { return m_object.m_onWatch; }
    void setOnWatch(int count) { m_object.m_onWatch = count; }
    QVariantList drops() const { return m_object.m_drops; }
    void setDrops(const QVariantList &drops) { m_object.m_drops = drops; }
    QStringList calls() const { return m_object.m_calls; }
    QVariantList times() const { return m_object.m_times; }
    QStringList errors() const { return m_object.m_errors; }
    QString recording() const { return m_object.m_active ? m_object.m_id : QString(); }
    QString state() const { return m_object.m_state; }

    Q_INVOKABLE bool start()
    {
        return m_bus.registerObject(path, &m_object,
                                    QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportScriptableProperties
                                        | QDBusConnection::ExportScriptableSignals)
            && m_bus.registerService(service);
    }

    // ioslink goes away.
    Q_INVOKABLE void stop()
    {
        m_bus.unregisterService(service);
        m_bus.unregisterObject(path);
    }

    Q_INVOKABLE void clear()
    {
        m_object.m_calls.clear();
        m_object.m_times.clear();
        m_object.m_errors.clear();
    }

    // Sets State as it stands and tells it, for a scene that draws one.
    Q_INVOKABLE void setState(const QString &json)
    {
        m_object.m_state = json;
        changed(QStringLiteral("State"), json);
    }

    // The levels that ioslink signals: centibels, the RMS of 50 ms each from
    // fromMs after the press.
    Q_INVOKABLE void levels(const QString &id, uint fromMs, const QVariantList &centibels)
    {
        QList<int> values;
        for (const QVariant &value : centibels)
            values << value.toInt();
        emit m_object.Levels(id, fromMs, values);
    }

    // ioslink stops the note itself, at 10:00, with the button still held.
    Q_INVOKABLE void limit() { m_object.limit(); }

private:
    void changed(const QString &name, const QVariant &value)
    {
        QDBusMessage signal = QDBusMessage::createSignal(path, QStringLiteral("org.freedesktop.DBus.Properties"),
                                                         QStringLiteral("PropertiesChanged"));
        signal << QStringLiteral("org.sonicscrewdriver.ioslink.VoiceNotes") << QVariantMap{{name, value}} << QStringList();
        m_bus.send(signal);
    }

    const QString service = QStringLiteral("org.sonicscrewdriver.ioslink");
    const QString path = QStringLiteral("/org/sonicscrewdriver/ioslink");
    QDBusConnection m_bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("voicenotes"));
    VoiceNotesObject m_object;
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
    MceStandIn mce;
    VoiceNotesStandIn voicenotes;
    QQuickView view;
    view.rootContext()->setContextProperty(QStringLiteral("test"), &tools);
    view.rootContext()->setContextProperty(QStringLiteral("ioslink"), &ioslink);
    view.rootContext()->setContextProperty(QStringLiteral("mce"), &mce);
    view.rootContext()->setContextProperty(QStringLiteral("voicenotes"), &voicenotes);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.resize(454, 454);
    view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (view.status() != QQuickView::Ready)
        return 1;
    view.show();
    return app.exec();
}

#include "harness.moc"
