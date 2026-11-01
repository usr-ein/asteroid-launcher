/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The app list's model: lipstick's LauncherModel, in a fixed order and
 * without the apps that an override hides.
 */

#ifndef APPLISTMODEL_H
#define APPLISTMODEL_H

#include <QCollator>
#include <QFileSystemWatcher>
#include <QHash>
#include <QSortFilterProxyModel>
#include <QStringList>

/*
 * Every app list style reads `launcherModel`, which MainScreen makes an
 * AppListModel over lipstick's own LauncherModel (sourceModel). It offers the
 * same things the styles use: the "object" role, get(row) and itemCount.
 *
 * Order: the apps named in `order`, by desktop file ID (the file name without
 * ".desktop"), in that order; then every other app, by title.
 *
 * Hiding: lipstick lists each .desktop file of /usr/share/applications and
 * ~/.local/share/applications on its own, so an XDG override, a file of the
 * same name with NoDisplay=true, doesn't hide the stock entry there. This
 * model hides an app when a .desktop file of the same name in one of
 * `overrideDirectories` says NoDisplay=true or Hidden=true. The directories
 * come first to last in XDG precedence, and an override only hides apps from
 * directories after it: by default ~/.local/share/applications, then
 * /usr/local/share/applications, before /usr/share/applications. Only hiding
 * is honoured: a visible override changes nothing. The directories are
 * watched, so an app goes or comes back as soon as its override is written or
 * deleted, including when a directory appears later.
 *
 * Logos: the "logo" role is the URL of the app's own logo, compiled in from
 * sonic/icons/<desktop file ID>.svg, or "" for an app without one.
 */
class AppListModel : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(QStringList order READ order WRITE setOrder NOTIFY orderChanged)
    Q_PROPERTY(QStringList overrideDirectories READ overrideDirectories WRITE setOverrideDirectories NOTIFY overrideDirectoriesChanged)
    Q_PROPERTY(int itemCount READ itemCount NOTIFY itemCountChanged)
    Q_PROPERTY(QStringList hiddenApps READ hiddenApps NOTIFY hiddenAppsChanged)

public:
    enum Roles {
        LogoRole = Qt::UserRole + 64
    };

    explicit AppListModel(QObject *parent = nullptr);

    QStringList order() const;
    void setOrder(const QStringList &order);

    QStringList overrideDirectories() const;
    void setOverrideDirectories(const QStringList &directories);

    int itemCount() const;

    // The desktop file IDs that an override hides, whether or not lipstick
    // lists them, sorted.
    QStringList hiddenApps() const;

    // The LauncherItem at a row of this model, as LauncherModel's get().
    Q_INVOKABLE QObject *get(int row) const;

    void setSourceModel(QAbstractItemModel *model) override;
    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

    // The URL of an app's compiled-in logo, from its .desktop file's path,
    // or "" when it has none.
    static QString logoUrl(const QString &filePath);

signals:
    void orderChanged();
    void overrideDirectoriesChanged();
    void itemCountChanged();
    void hiddenAppsChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

private slots:
    void checkItemCount();

private:
    struct Override {
        int directory;  // its index in m_overrideDirectories
        bool hides;
        bool operator==(const Override &other) const;
    };

    void updateOverrides(bool directoriesChanged);
    QObject *sourceItem(int sourceRow) const;
    int directoryIndex(const QString &directory) const;

    QStringList m_order;
    QStringList m_overrideDirectories;
    // The highest-precedence override of each file name.
    QHash<QString, Override> m_overrides;
    QFileSystemWatcher m_watcher;
    QCollator m_collator;
    int m_objectRole = -1;
    int m_itemCount = 0;
};

#endif // APPLISTMODEL_H
