/*
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "applistmodel.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QQmlEngine>
#include <QStandardPaths>

#include <MDesktopEntry>

namespace {

const QString desktopSuffix = QStringLiteral(".desktop");

QString desktopFileId(const QString &filePath)
{
    QString id = QFileInfo(filePath).fileName();
    if (id.endsWith(desktopSuffix))
        id.chop(desktopSuffix.size());
    return id;
}

int objectRoleOf(const QAbstractItemModel *model)
{
    if (model) {
        const QHash<int, QByteArray> roles = model->roleNames();
        for (auto it = roles.constBegin(); it != roles.constEnd(); ++it) {
            if (it.value() == "object")
                return it.key();
        }
    }
    return -1;
}

// The directory itself, or while it doesn't exist, its closest parent that
// does: watching that notices the directory's creation.
QString watchablePath(const QString &directory)
{
    QString path = directory;
    while (!QFileInfo(path).isDir()) {
        const QString parent = QFileInfo(path).path();
        if (parent == path)
            return QString();
        path = parent;
    }
    return path;
}

} // namespace

bool AppListModel::Override::operator==(const Override &other) const
{
    return directory == other.directory && hides == other.hides;
}

AppListModel::AppListModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    m_overrideDirectories
        << QDir::cleanPath(QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation))
        << QStringLiteral("/usr/local/share/applications");
    m_collator.setCaseSensitivity(Qt::CaseInsensitive);
    m_collator.setNumericMode(true);

    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { updateOverrides(false); });
    connect(this, &QAbstractItemModel::rowsInserted, this, &AppListModel::checkItemCount);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &AppListModel::checkItemCount);
    connect(this, &QAbstractItemModel::modelReset, this, &AppListModel::checkItemCount);
    connect(this, &QAbstractItemModel::layoutChanged, this, &AppListModel::checkItemCount);

    updateOverrides(false);
}

void AppListModel::setSourceModel(QAbstractItemModel *model)
{
    // Known before the base class first filters the new model's rows.
    m_objectRole = objectRoleOf(model);
    QSortFilterProxyModel::setSourceModel(model);
    if (sortColumn() != 0)
        sort(0);
    else
        invalidate();
    checkItemCount();
}

QHash<int, QByteArray> AppListModel::roleNames() const
{
    QHash<int, QByteArray> roles = QSortFilterProxyModel::roleNames();
    roles.insert(LogoRole, QByteArrayLiteral("logo"));
    return roles;
}

QVariant AppListModel::data(const QModelIndex &index, int role) const
{
    if (role != LogoRole)
        return QSortFilterProxyModel::data(index, role);
    const QObject *item = sourceItem(mapToSource(index).row());
    return item ? logoUrl(item->property("filePath").toString()) : QString();
}

QString AppListModel::logoUrl(const QString &filePath)
{
    const QString id = desktopFileId(filePath);
    if (id.isEmpty() || !QFile::exists(QStringLiteral(":/sonic/icons/") + id + QStringLiteral(".svg")))
        return QString();
    return QStringLiteral("qrc:/sonic/icons/") + id + QStringLiteral(".svg");
}

QStringList AppListModel::order() const
{
    return m_order;
}

void AppListModel::setOrder(const QStringList &order)
{
    if (order == m_order)
        return;
    m_order = order;
    invalidate();
    emit orderChanged();
}

QStringList AppListModel::overrideDirectories() const
{
    return m_overrideDirectories;
}

void AppListModel::setOverrideDirectories(const QStringList &directories)
{
    QStringList cleaned;
    for (const QString &directory : directories)
        cleaned << QDir::cleanPath(directory);
    if (cleaned == m_overrideDirectories)
        return;
    m_overrideDirectories = cleaned;
    updateOverrides(true);
    emit overrideDirectoriesChanged();
}

int AppListModel::itemCount() const
{
    return rowCount();
}

QStringList AppListModel::hiddenApps() const
{
    QStringList ids;
    for (auto it = m_overrides.constBegin(); it != m_overrides.constEnd(); ++it) {
        if (it->hides)
            ids << desktopFileId(it.key());
    }
    ids.sort();
    return ids;
}

QObject *AppListModel::get(int row) const
{
    if (row < 0 || row >= rowCount())
        return nullptr;
    QObject *item = sourceItem(mapToSource(index(row, 0)).row());
    // lipstick's model owns its items; QML must never collect one.
    if (item)
        QQmlEngine::setObjectOwnership(item, QQmlEngine::CppOwnership);
    return item;
}

bool AppListModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    Q_UNUSED(sourceParent)
    const QObject *item = sourceItem(sourceRow);
    if (!item)
        return true;
    const QFileInfo file(item->property("filePath").toString());
    const auto found = m_overrides.constFind(file.fileName());
    if (found == m_overrides.constEnd() || !found->hides)
        return true;
    // An override hides the apps of the directories after its own only.
    return found->directory >= directoryIndex(file.absolutePath());
}

bool AppListModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    const QObject *a = sourceItem(left.row());
    const QObject *b = sourceItem(right.row());
    if (!a || !b)
        return a && !b;

    const QString pathA = a->property("filePath").toString();
    const QString pathB = b->property("filePath").toString();
    int rankA = m_order.indexOf(desktopFileId(pathA));
    int rankB = m_order.indexOf(desktopFileId(pathB));
    if (rankA < 0)
        rankA = m_order.size();
    if (rankB < 0)
        rankB = m_order.size();
    if (rankA != rankB)
        return rankA < rankB;

    const int byTitle = m_collator.compare(a->property("title").toString(), b->property("title").toString());
    if (byTitle != 0)
        return byTitle < 0;
    return pathA < pathB;
}

void AppListModel::checkItemCount()
{
    const int count = rowCount();
    if (count != m_itemCount) {
        m_itemCount = count;
        emit itemCountChanged();
    }
}

void AppListModel::updateOverrides(bool directoriesChanged)
{
    // Watch first, then read, so that nothing written in between is missed.
    QStringList paths;
    for (const QString &directory : qAsConst(m_overrideDirectories)) {
        const QString path = watchablePath(directory);
        if (!path.isEmpty() && !paths.contains(path))
            paths << path;
    }
    const QStringList watched = m_watcher.directories();
    for (const QString &path : watched) {
        if (!paths.contains(path))
            m_watcher.removePath(path);
    }
    for (const QString &path : qAsConst(paths)) {
        if (!watched.contains(path))
            m_watcher.addPath(path);
    }

    QHash<QString, Override> overrides;
    for (int i = 0; i < m_overrideDirectories.size(); ++i) {
        const QDir directory(m_overrideDirectories.at(i));
        const QFileInfoList files = directory.entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
        for (const QFileInfo &file : files) {
            // A directory earlier in precedence decides.
            if (overrides.contains(file.fileName()))
                continue;
            const MDesktopEntry entry(file.absoluteFilePath());
            overrides.insert(file.fileName(), Override{i, entry.noDisplay() || entry.hidden()});
        }
    }

    if (overrides == m_overrides && !directoriesChanged)
        return;
    const QStringList hiddenBefore = hiddenApps();
    m_overrides = overrides;
    invalidateFilter();
    if (hiddenApps() != hiddenBefore)
        emit hiddenAppsChanged();
}

QObject *AppListModel::sourceItem(int sourceRow) const
{
    const QAbstractItemModel *model = sourceModel();
    if (!model || m_objectRole < 0 || sourceRow < 0)
        return nullptr;
    return model->data(model->index(sourceRow, 0), m_objectRole).value<QObject *>();
}

int AppListModel::directoryIndex(const QString &directory) const
{
    const int index = m_overrideDirectories.indexOf(QDir::cleanPath(directory));
    return index < 0 ? m_overrideDirectories.size() : index;
}
