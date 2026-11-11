/*
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "buttondoubleclick.h"

#include <QDir>
#include <QFile>
#include <QSocketNotifier>
#include <QTimer>

#include <cerrno>
#include <ctime>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {

constexpr int bitsPerLong = 8 * sizeof(unsigned long);

bool testBit(const unsigned long *bits, int bit)
{
    return bits[bit / bitsPerLong] & (1UL << (bit % bitsPerLong));
}

} // namespace

ButtonDoubleClick::ButtonDoubleClick(QObject *parent)
    : QObject(parent)
    , m_keyCode(KEY_MENU)
{
    m_single.setSingleShot(true);
    // m_lastPress stays: a second press that arrives late, after a wake, but
    // was pressed in time still makes a double-click.
    connect(&m_single, &QTimer::timeout, this, &ButtonDoubleClick::singleClicked);

    m_hold.setSingleShot(true);
    // To the millisecond: a note starts at the press, and the tick at its
    // confirmation says "speak".
    m_hold.setTimerType(Qt::PreciseTimer);
    connect(&m_hold, &QTimer::timeout, this, [this] {
        if (!m_holding || m_confirmed)
            return;
        m_confirmed = true;
        // A hold never pairs with the next press.
        m_lastPress = -1;
        emit holdConfirmed();
    });
}

ButtonDoubleClick::~ButtonDoubleClick()
{
    closeAll();
}

int ButtonDoubleClick::keyCode() const
{
    return m_keyCode;
}

void ButtonDoubleClick::setKeyCode(int keyCode)
{
    if (keyCode == m_keyCode)
        return;
    m_keyCode = keyCode;
    emit keyCodeChanged();
    if (m_complete)
        reopen();
}

int ButtonDoubleClick::interval() const
{
    return m_interval;
}

void ButtonDoubleClick::setInterval(int interval)
{
    if (interval == m_interval)
        return;
    m_interval = interval;
    emit intervalChanged();
}

int ButtonDoubleClick::longInterval() const
{
    return m_longInterval;
}

void ButtonDoubleClick::setLongInterval(int longInterval)
{
    if (longInterval == m_longInterval)
        return;
    m_longInterval = longInterval;
    emit longIntervalChanged();
}

bool ButtonDoubleClick::captured() const
{
    return m_captured;
}

void ButtonDoubleClick::setCaptured(bool captured)
{
    if (captured == m_captured)
        return;
    m_captured = captured;
    emit capturedChanged();
}

QStringList ButtonDoubleClick::devices() const
{
    return m_devices;
}

void ButtonDoubleClick::setDevices(const QStringList &devices)
{
    if (devices == m_devices)
        return;
    m_devices = devices;
    emit devicesChanged();
    if (m_complete)
        reopen();
}

QStringList ButtonDoubleClick::openDevices() const
{
    QStringList paths;
    for (const Device &device : m_open)
        paths << device.path;
    return paths;
}

void ButtonDoubleClick::classBegin()
{
}

void ButtonDoubleClick::componentComplete()
{
    m_complete = true;
    reopen();
}

void ButtonDoubleClick::closeAll()
{
    for (const Device &device : qAsConst(m_open)) {
        delete device.notifier;
        ::close(device.fd);
    }
    m_open.clear();
}

void ButtonDoubleClick::reopen()
{
    m_reopenScheduled = false;
    const QStringList before = openDevices();
    // A hold has no release to wait for from devices that are closed.
    abortHold();
    closeAll();
    m_lastPress = -1;

    QStringList paths = m_devices;
    if (paths.isEmpty()) {
        const QDir input(QStringLiteral("/dev/input"));
        const QStringList names = input.entryList({QStringLiteral("event*")}, QDir::System, QDir::Name);
        for (const QString &name : names)
            paths << input.filePath(name);
    }

    for (const QString &path : qAsConst(paths)) {
        const int fd = ::open(QFile::encodeName(path).constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0)
            continue;
        struct stat info;
        if (::fstat(fd, &info) == 0 && S_ISCHR(info.st_mode)) {
            if (!canSendKey(fd)) {
                ::close(fd);
                continue;
            }
            // The events' times on the boot-time clock: a change of the time
            // of day leaves it alone, and it counts the time in suspend. The
            // button wakes the watch, which can suspend again between two
            // presses: on the monotonic clock, which stops then, presses
            // seconds apart could look like a double-click.
            int clock = CLOCK_BOOTTIME;
            ::ioctl(fd, EVIOCSCLOCKID, &clock);
        }
        auto *notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
        connect(notifier, &QSocketNotifier::activated, this, [this, fd] { readFrom(fd); });
        m_open.append({path, fd, notifier});
    }

    if (openDevices() != before)
        emit openDevicesChanged();
}

bool ButtonDoubleClick::canSendKey(int fd) const
{
    if (m_keyCode < 0 || m_keyCode > KEY_MAX)
        return false;
    unsigned long types[EV_MAX / bitsPerLong + 1] = {};
    unsigned long keys[KEY_MAX / bitsPerLong + 1] = {};
    if (::ioctl(fd, EVIOCGBIT(0, sizeof(types)), types) < 0 || !testBit(types, EV_KEY))
        return false;
    if (::ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keys)), keys) < 0)
        return false;
    return testBit(keys, m_keyCode);
}

void ButtonDoubleClick::readFrom(int fd)
{
    struct input_event events[32];
    for (;;) {
        const ssize_t n = ::read(fd, events, sizeof(events));
        if (n > 0) {
            const size_t count = size_t(n) / sizeof(struct input_event);
            for (size_t i = 0; i < count; ++i) {
                const struct input_event &event = events[i];
                if (event.type != EV_KEY || event.code != m_keyCode)
                    continue;
                const qint64 msec = qint64(event.input_event_sec) * 1000 + qint64(event.input_event_usec) / 1000;
                // 1 is a press and 0 a release; 2, a repeat, doesn't count.
                if (event.value == 1)
                    pressed(msec, fd);
                else if (event.value == 0)
                    released(msec);
            }
            continue;
        }
        if (n < 0 && errno == EINTR)
            continue;
        if (n < 0 && errno == EAGAIN)
            return;
        break;
    }

    // The end of the file, or a device that went away: stop reading it, and
    // look for the devices again in a while. A hold that it began won't be
    // released.
    if (m_holding && m_holdFd == fd)
        abortHold();
    for (const Device &device : qAsConst(m_open)) {
        if (device.fd == fd)
            device.notifier->setEnabled(false);
    }
    if (!m_reopenScheduled) {
        m_reopenScheduled = true;
        QTimer::singleShot(2000, this, &ButtonDoubleClick::reopen);
    }
}

void ButtonDoubleClick::pressed(qint64 msec, int fd)
{
    // The release of the press before never came: it ended here.
    if (m_holding)
        endHold(msec);

    if (m_captured) {
        // The press has this one meaning: it pairs with nothing, starts no
        // hold, and its release finds no hold to end.
        m_lastPress = -1;
        emit capturedPressed(msec);
        return;
    }

    if (m_lastPress >= 0 && msec >= m_lastPress && msec - m_lastPress <= m_interval) {
        // The second press of a double-click: it starts no hold, and its
        // release means nothing.
        m_lastPress = -1;
        m_single.stop();
        emit doubleClicked();
        return;
    }
    if (m_single.isActive()) {
        // The press before stood alone: this one came too late to pair.
        m_single.stop();
        emit singleClicked();
    }
    m_lastPress = msec;
    m_holding = true;
    m_confirmed = false;
    m_holdFd = fd;
    m_pressRef = reference(msec);
    emit holdStarted(msec);
    // The timer starts after the signal, for what is left of the wait by
    // then: a slow handler is part of it.
    if (m_holding && !m_confirmed)
        m_hold.start(int(qMax<qint64>(0, m_pressRef + m_longInterval - bootMs())));
}

void ButtonDoubleClick::released(qint64 msec)
{
    // The release of a double-click's second press, or of a press that this
    // reader never saw: no hold, nothing to end.
    if (m_holding)
        endHold(msec);
}

void ButtonDoubleClick::endHold(qint64 stamp)
{
    m_hold.stop();
    const qint64 releaseRef = reference(stamp);
    if (!m_confirmed && releaseRef - m_pressRef >= m_longInterval) {
        // The press and its release were read together, after a stall: the
        // button was held long enough all the same.
        m_confirmed = true;
        m_lastPress = -1;
        emit holdConfirmed();
    }
    const bool confirmed = m_confirmed;
    const qint64 pressRef = m_pressRef;
    m_holding = false;
    m_holdFd = -1;
    emit holdEnded(stamp, confirmed);
    if (confirmed)
        return;
    // A click, alone for now: it counts at the later of the press plus the
    // interval and the release, unless a second press comes first.
    const qint64 wait = qMax(pressRef + m_interval, releaseRef) - bootMs();
    if (wait > 0)
        m_single.start(int(wait));
    else
        emit singleClicked();
}

void ButtonDoubleClick::abortHold()
{
    if (!m_holding)
        return;
    m_hold.stop();
    m_holding = false;
    m_holdFd = -1;
    m_lastPress = -1;
    emit holdEnded(bootMs(), m_confirmed);
}

qint64 ButtonDoubleClick::bootMs()
{
    struct timespec now;
    if (::clock_gettime(CLOCK_BOOTTIME, &now) != 0 && ::clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        return 0;
    return qint64(now.tv_sec) * 1000 + qint64(now.tv_nsec) / 1000000;
}

qint64 ButtonDoubleClick::reference(qint64 stamp)
{
    // A press that woke the watch reaches us some tenths of a second late; a
    // stamp that isn't on the boot-time clock is years off.
    constexpr qint64 maxAge = 1000;
    const qint64 now = bootMs();
    const qint64 age = now - stamp;
    return age >= 0 && age <= maxAge ? stamp : now;
}
