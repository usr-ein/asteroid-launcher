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
    , m_keyCode(KEY_VOLUMEDOWN)
{
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
            // The events' times on the monotonic clock, which a change of
            // the time of day leaves alone.
            int clock = CLOCK_MONOTONIC;
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
                // 1 is a press; 0 a release and 2 a repeat, which don't count.
                if (event.type == EV_KEY && event.code == m_keyCode && event.value == 1)
                    pressed(qint64(event.input_event_sec) * 1000 + qint64(event.input_event_usec) / 1000);
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
    // look for the devices again in a while.
    for (const Device &device : qAsConst(m_open)) {
        if (device.fd == fd)
            device.notifier->setEnabled(false);
    }
    if (!m_reopenScheduled) {
        m_reopenScheduled = true;
        QTimer::singleShot(2000, this, &ButtonDoubleClick::reopen);
    }
}

void ButtonDoubleClick::pressed(qint64 msec)
{
    if (m_lastPress >= 0 && msec >= m_lastPress && msec - m_lastPress <= m_interval) {
        m_lastPress = -1;
        emit doubleClicked();
    } else {
        m_lastPress = msec;
    }
}
