/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * A double-click of a hardware button, read from the kernel's input devices.
 */

#ifndef BUTTONDOUBLECLICK_H
#define BUTTONDOUBLECLICK_H

#include <QObject>
#include <QQmlParserStatus>
#include <QStringList>
#include <QVector>

class QSocketNotifier;

/*
 * Emits doubleClicked() when a button is pressed twice within `interval`
 * milliseconds.
 *
 * It reads the input devices themselves, not Qt's key events: lipstick hides
 * its window while the display is off, and Qt then delivers no key event at
 * all. It only reads and never grabs a device, so the button's single press
 * keeps doing what it did, for the launcher, mce and the apps alike.
 *
 * - keyCode: the button's Linux key code (linux/input-event-codes.h).
 * - interval: the longest time from the first press to the second, by the
 *   kernel's times of the events, so that presses that wake the watch, and
 *   reach the launcher late, still count as they were pressed.
 * - devices: the event devices to read. Empty, the default: each
 *   /dev/input/event* that can send the key. Any other file is read as is,
 *   for the tests.
 */
class ButtonDoubleClick : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(int keyCode READ keyCode WRITE setKeyCode NOTIFY keyCodeChanged)
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)
    Q_PROPERTY(QStringList devices READ devices WRITE setDevices NOTIFY devicesChanged)
    Q_PROPERTY(QStringList openDevices READ openDevices NOTIFY openDevicesChanged)

public:
    explicit ButtonDoubleClick(QObject *parent = nullptr);
    ~ButtonDoubleClick() override;

    int keyCode() const;
    void setKeyCode(int keyCode);
    int interval() const;
    void setInterval(int interval);
    QStringList devices() const;
    void setDevices(const QStringList &devices);
    // The devices that it reads now.
    QStringList openDevices() const;

    void classBegin() override;
    void componentComplete() override;

signals:
    void keyCodeChanged();
    void intervalChanged();
    void devicesChanged();
    void openDevicesChanged();
    void doubleClicked();

private:
    struct Device {
        QString path;
        int fd;
        QSocketNotifier *notifier;
    };

    void reopen();
    void closeAll();
    bool canSendKey(int fd) const;
    void readFrom(int fd);
    void pressed(qint64 msec);

    int m_keyCode;
    int m_interval = 400;
    QStringList m_devices;
    QVector<Device> m_open;
    qint64 m_lastPress = -1;
    bool m_complete = false;
    bool m_reopenScheduled = false;
};

#endif // BUTTONDOUBLECLICK_H
