/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The calendar of sonic/test/test.sh's today scene: four notebooks, coloured
 * as an iPhone's calendars are (the colour that the iPhone sync sets on each
 * notebook), with invented events for today, in mkcal's database under $HOME.
 * It runs in the test's container only, where HOME is a throwaway one.
 *
 *   seed-calendar busy|quiet|empty
 *
 * Each run replaces the notebooks and their events, so that an open Today
 * screen has to follow. The days are the approved mockup's sample days.
 */

#include <QCoreApplication>
#include <QDate>
#include <QTextStream>
#include <QTimeZone>

#include <KCalendarCore/Event>

#include <extendedcalendar.h>
#include <extendedstorage.h>
#include <notebook.h>

namespace {

struct Calendar {
    const char *uid;
    const char *name;
    const char *colour;
};

const Calendar calendars[] = {
    {"sonic-test-work", "Work", "#0A84FF"},
    {"sonic-test-home", "Home", "#FF9F0A"},
    {"sonic-test-sport", "Sport", "#30D158"},
    {"sonic-test-friends", "Friends", "#BF5AF2"},
};

// An event of today: all day when start is empty.
struct Sample {
    const char *day;
    int calendar;
    const char *title;
    const char *start;
    const char *end;
};

const Sample samples[] = {
    {"busy", 1, "Pack for the trip", "", ""},
    {"busy", 0, "Release week", "", ""},
    {"busy", 3, "Friends in town", "", ""},
    {"busy", 2, "Morning run along the river", "07:45", "08:30"},
    {"busy", 0, "Stand-up", "09:30", "09:45"},
    {"busy", 3, "Brunch with friends at the café on the corner of the square", "10:30", "12:00"},
    {"busy", 1, "Call the landlord about the boiler", "11:00", "11:20"},
    {"busy", 1, "Groceries", "13:00", "13:45"},
    {"busy", 0, "Review the watch check-in data and plan the next sensor phase with the team", "14:30", "16:00"},
    {"busy", 2, "Climbing at the bouldering gym", "17:30", "19:00"},
    {"busy", 3, "Dinner at home", "19:30", "21:30"},
    {"busy", 0, "Plan the week", "21:30", "22:00"},
    {"quiet", 1, "Bins out", "", ""},
    {"quiet", 2, "Long walk in the park", "10:00", "11:30"},
    {"quiet", 3, "Video call with family", "18:00", "18:45"},
};

int fail(const QString &message)
{
    QTextStream(stderr) << "seed-calendar: " << message << "\n";
    return 1;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    const QStringList args = app.arguments();
    const QString day = args.value(1);
    if (args.size() != 2 || (day != "busy" && day != "quiet" && day != "empty")) {
        QTextStream(stderr) << "usage: seed-calendar busy|quiet|empty\n";
        return 64;
    }

    const QTimeZone zone = QTimeZone::systemTimeZone();
    mKCal::ExtendedCalendar::Ptr calendar(new mKCal::ExtendedCalendar(zone));
    mKCal::ExtendedStorage::Ptr storage = mKCal::ExtendedCalendar::defaultStorage(calendar);
    if (!storage->open())
        return fail("can't open the calendar database");

    for (const Calendar &c : calendars) {
        mKCal::Notebook::Ptr notebook = storage->notebook(c.uid);
        if (!notebook)
            continue;
        if (!storage->loadNotebookIncidences(c.uid))
            return fail(QStringLiteral("can't load notebook %1").arg(c.uid));
        for (const KCalendarCore::Incidence::Ptr &incidence : calendar->incidences(c.uid))
            calendar->deleteIncidence(incidence);
        if (!storage->save(mKCal::ExtendedStorage::PurgeDeleted) || !storage->deleteNotebook(notebook))
            return fail(QStringLiteral("can't delete notebook %1").arg(c.uid));
    }

    for (const Calendar &c : calendars) {
        mKCal::Notebook::Ptr notebook(new mKCal::Notebook(c.uid, c.name, QString(), c.colour,
            false /* shared */, false /* master */, false /* synchronized */, false /* read-only */,
            true /* visible */, QStringLiteral("sonic-test"), QString(), 0));
        if (!storage->addNotebook(notebook))
            return fail(QStringLiteral("can't create notebook %1").arg(c.uid));
    }

    const QDate today = QDate::currentDate();
    int events = 0;
    for (const Sample &sample : samples) {
        if (day != sample.day)
            continue;
        KCalendarCore::Event::Ptr event(new KCalendarCore::Event);
        event->setSummary(QString::fromUtf8(sample.title));
        if (!*sample.start) {
            event->setDtStart(QDateTime(today, QTime(0, 0), zone));
            event->setDtEnd(QDateTime(today, QTime(0, 0), zone));
            event->setAllDay(true);
        } else {
            event->setDtStart(QDateTime(today, QTime::fromString(sample.start, "hh:mm"), zone));
            event->setDtEnd(QDateTime(today, QTime::fromString(sample.end, "hh:mm"), zone));
        }
        if (!calendar->addEvent(event, calendars[sample.calendar].uid))
            return fail(QStringLiteral("can't add \"%1\"").arg(sample.title));
        ++events;
    }
    if (!storage->save())
        return fail("can't save the events");
    storage->close();
    QTextStream(stdout) << "seed-calendar: " << day << ", " << events << " events\n";
    return 0;
}
