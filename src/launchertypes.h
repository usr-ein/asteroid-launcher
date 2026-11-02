/*
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef LAUNCHERTYPES_H
#define LAUNCHERTYPES_H

/*
 * Registers the launcher's QML types, org.asteroid.launcher 1.0. main()
 * calls it first, before anything loads QML: lipstick's HomeApplication
 * compiles compositor.qml as soon as setCompositorPath() is called, and a
 * type registered after that is missing from it. The off-the-watch tests
 * (sonic/test/) register the types with it too.
 */
void registerLauncherTypes();

#endif // LAUNCHERTYPES_H
