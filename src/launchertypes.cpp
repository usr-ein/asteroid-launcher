/*
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "launchertypes.h"

#include <QAbstractItemModel>
#include <QQmlEngine>

#include "applauncher.h"
#include "applauncherbackground.h"
#include "applistmodel.h"
#include "buttondoubleclick.h"
#include "gesturefilterarea.h"
#include "notificationsnoozer.h"

void registerLauncherTypes()
{
    const char *uri = "org.asteroid.launcher";
    qmlRegisterType<AppLauncherBackground>(uri, 1, 0, "AppLauncherBackground");
    qmlRegisterType<GestureFilterArea>(uri, 1, 0, "GestureFilterArea");
    qmlRegisterType<NotificationSnoozer>(uri, 1, 0, "NotificationSnoozer");
    qmlRegisterType<AppLauncher>(uri, 1, 0, "AppLauncher");
    qmlRegisterType<AppListModel>(uri, 1, 0, "AppListModel");
    // For AppListModel's sourceModel, set from QML.
    qmlRegisterAnonymousType<QAbstractItemModel>(uri, 1);
    qmlRegisterType<ButtonDoubleClick>(uri, 1, 0, "ButtonDoubleClick");
}
