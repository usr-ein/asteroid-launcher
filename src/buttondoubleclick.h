/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * A double-click and a hold of a hardware button, read from the kernel's input devices.
 */

#ifndef BUTTONDOUBLECLICK_H
#define BUTTONDOUBLECLICK_H

#include <QObject>
#include <QQmlParserStatus>
#include <QStringList>
#include <QTimer>
#include <QVector>

class QSocketNotifier;

/*
 * Emits doubleClicked() when a button is pressed twice within `interval`
 * milliseconds, and singleClicked() for a press that stays alone and is let
 * go before `longInterval`: at the later of `interval` after the press and
 * the release, with no second press. A double-click emits no singleClicked().
 *
 * The hold (Sonic Screwdriver's docs/prd/voice_notes.md § 8.2), which reads
 * the releases too:
 * - holdStarted(pressedAt): any press that isn't the second press of a
 *   double-click, at once, with the event's time on the boot-time clock, in
 *   ms.
 * - holdConfirmed(): the button is still down `longInterval` after the press,
 *   counted from the event's own time, so that a press that woke the watch
 *   and reached us late is timed from when it was pressed.
 * - holdEnded(releasedAt, confirmed): its release, by the event's time. With
 *   `confirmed` false it was a click. A hold that holdConfirmed() reported
 *   never ends in a singleClicked() or a doubleClicked(), and the second
 *   press of a double-click never starts one.
 * - captured (bool): while true, a press emits capturedPressed(pressedAt) at
 *   once, by the event's time, and nothing else: no hold, no click, no
 *   double-click, and it pairs with nothing. Its release means nothing. A
 *   confirmed hold's release still ends it with holdEnded(t, true).
 * A hold that ends without its release, because the device went away or
 * another press came with the release lost, ends at that moment, and a hold
 * that was never confirmed is no click then.
 *
 * It reads the input devices themselves, not Qt's key events: lipstick hides
 * its window while the display is off, and Qt then delivers no key event at
 * all. It only reads and never grabs a device, so the button's single press
 * keeps doing what it did, for the launcher, mce and the apps alike.
 *
 * - keyCode: the button's Linux key code (linux/input-event-codes.h);
 *   KEY_MENU by default, the watch's bottom button.
 * - interval: the longest time from the first press to the second, by the
 *   kernel's times of the events on the boot-time clock, so that presses
 *   that wake the watch, and reach the launcher late, still count as they
 *   were pressed, and time in suspend counts too.
 * - longInterval: how long a button is held for a hold, from the press.
 * - devices: the event devices to read. Empty, the default: each
 *   /dev/input/event* that can send the key. Any other file is read as is,
 *   for the tests.
 *
 * The age of an event, the boot-time clock now less its time, counts only
 * when it is plausible: not in the future, and under a second. Anything else
 * is not the boot-time clock, and the event counts from when it arrives.
 */
class ButtonDoubleClick : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(int keyCode READ keyCode WRITE setKeyCode NOTIFY keyCodeChanged)
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)
    Q_PROPERTY(int longInterval READ longInterval WRITE setLongInterval NOTIFY longIntervalChanged)
    Q_PROPERTY(bool captured READ captured WRITE setCaptured NOTIFY capturedChanged)
    Q_PROPERTY(QStringList devices READ devices WRITE setDevices NOTIFY devicesChanged)
    Q_PROPERTY(QStringList openDevices READ openDevices NOTIFY openDevicesChanged)

public:
    explicit ButtonDoubleClick(QObject *parent = nullptr);
    ~ButtonDoubleClick() override;

    int keyCode() const;
    void setKeyCode(int keyCode);
    int interval() const;
    void setInterval(int interval);
    int longInterval() const;
    void setLongInterval(int longInterval);
    bool captured() const;
    void setCaptured(bool captured);
    QStringList devices() const;
    void setDevices(const QStringList &devices);
    // The devices that it reads now.
    QStringList openDevices() const;

    void classBegin() override;
    void componentComplete() override;

signals:
    void keyCodeChanged();
    void intervalChanged();
    void longIntervalChanged();
    void capturedChanged();
    void devicesChanged();
    void openDevicesChanged();
    void doubleClicked();
    void singleClicked();
    void holdStarted(qint64 pressedAt);
    void holdConfirmed();
    void holdEnded(qint64 releasedAt, bool confirmed);
    void capturedPressed(qint64 pressedAt);

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
    void pressed(qint64 msec, int fd);
    void released(qint64 msec);
    // The hold ends with the release at `stamp`. A press and its release read
    // together after a stall still make a hold, if they were that far apart.
    void endHold(qint64 stamp);
    // The hold ends without a release: nothing is a click then.
    void abortHold();
    // The boot-time clock now, in ms.
    static qint64 bootMs();
    // The event's time on the boot-time clock, or now when that isn't one.
    static qint64 reference(qint64 stamp);

    int m_keyCode;
    int m_interval = 400;
    int m_longInterval = 500;
    QStringList m_devices;
    QVector<Device> m_open;
    qint64 m_lastPress = -1;
    // Runs from a click's end: a second press that arrives in time pairs
    // with it; otherwise the press stood alone.
    QTimer m_single;
    // Runs from a press to its hold's confirmation, if the button is still down.
    QTimer m_hold;
    bool m_captured = false;
    bool m_holding = false;
    bool m_confirmed = false;
    int m_holdFd = -1;
    qint64 m_pressRef = 0;
    bool m_complete = false;
    bool m_reopenScheduled = false;
};

#endif // BUTTONDOUBLECLICK_H
