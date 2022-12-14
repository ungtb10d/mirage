// Copyright Mirage authors & contributors <https://github.com/mirukana/mirage>
// SPDX-License-Identifier: LGPL-3.0-or-later

import QtQuick 2.12
import QtQuick.Layouts 1.12
import Qt.labs.qmlmodels 1.0
import ".."
import "../Base"

HListView {
    id: roomList

    property string filter: ""

    property bool keepListCentered: true

    readonly property bool currentShouldBeAccount:
        window.uiState.page === "Pages/AccountSettings/AccountSettings.qml" ||
        window.uiState.page === "Pages/AddChat/AddChat.qml"

    readonly property bool currentShouldBeRoom:
        window.uiState.page === "Pages/Chat/Chat.qml"

    readonly property string wantedUserId: (
        window.uiState.pageProperties.userRoomId ||
        [window.uiState.pageProperties.userId, ""]
    )[0] || ""

    readonly property string wantedRoomId: (
        window.uiState.pageProperties.userRoomId ||
        ["", window.uiState.pageProperties.roomId]
    )[1] || ""

    readonly property var accountIndice: {
        const accounts = {}

        for (let i = 0; i < model.count; i++) {
            if (model.get(i).type === "Account")
                accounts[model.get(i).id] = i
        }

        return accounts
    }

    function goToAccount(userId) {
        currentIndex = accountIndice[userId]
        showItemLimiter.restart()
    }

    function goToAccountNumber(num) {
        currentIndex = Object.entries(accountIndice)[num][1]
        showItemLimiter.restart()
    }

    function showItemAtIndex(index=currentIndex, fromClick=false) {
        if (index === -1) index = 0
        index = Math.min(index, model.count - 1)

        const item = model.get(index)

        item.type === "Account" ?
        pageLoader.show(
            "Pages/AccountSettings/AccountSettings.qml", { "userId": item.id },
        ) :
        pageLoader.showRoom(item.for_account, item.id)

        if (fromClick && ! window.settings.RoomList.click_centers)
            keepListCentered = false

        currentIndex = index

        if (fromClick && ! window.settings.RoomList.click_centers)
            keepListCentered = true
    }

    function showById(roomId, accountId=null) {
        // If only a room ID is passed, first account with this room is used
        if (accountId === null) {
            const roomIndex = model.findIndex(roomId)

            roomIndex === null ?
            console.warn("No account with such room ID:", roomId) :
            showItemAtIndex(roomIndex)

            return
        }

        if (! (accountId in accountIndice)) {
            console.warn("No such account:", accountId)
            return
        }

        pageLoader.showRoom(accountId, roomId)
        startCorrectItemSearch()
    }

    function showAccountRoomAtIndex(index) {
        const item = model.get(currentIndex === -1 ?  0 : currentIndex)

        const currentUserId =
            item.type === "Account" ? item.id : item.for_account

        showItemAtIndex(accountIndice[currentUserId] + 1 + index)
    }

    function cycleUnreadRooms(forward=true, highlights=false) {
        const prop      = highlights ? "highlights": "unreads"
        const localProp = highlights ? "highlights":  "local_unreads"
        const start     = currentIndex === -1 ? 0:   currentIndex
        let index       = start

        while (true) {
            index += forward ? 1 : -1

            if (index < 0) index = model.count - 1
            if (index > model.count - 1) index = 0

            if (index === start && highlights)
                return cycleUnreadRooms(forward, false)
            else if (index === start)
                return false

            const item = model.get(index)

            if (item.type === "Room" && (item[prop] || item[localProp])) {
                currentIndex = index
                return true
            }
        }
    }

    // Find latest highlight or unread. If oldest=true, find oldest instead.
    function latestUnreadRoom(oldest=false, highlights=false) {
        const prop      = highlights ? "highlights": "unreads"
        const localProp = highlights ? "highlights":  "local_unreads"

        // When highlights=true, we don't actually find the latest highlight,
        // but instead, the latest unread among all the highlighted rooms.

        let max = null
        let maxEvent = null

        for (let i = 0; i < model.count; i++) {
            const item = model.get(i)

            if (
                item.type === "Room" &&
                (item[prop] || item[localProp]) &&
                (max === null || item.last_event_date < maxEvent === oldest)
            ) {
                max = i
                maxEvent = item.last_event_date
            }
        }

        if (max === null) return false // No unreads found

        currentIndex = max
        return true
    }

    function startCorrectItemSearch() {
        correctTimer.start()
    }

    function setCorrectCurrentItem() {
        if (! currentShouldBeRoom && ! currentShouldBeAccount) {
            currentIndex = -1
            return null
        }

        for (let i = 0; i < model.count; i++) {
            const item = model.get(i)

            if ((
                currentShouldBeRoom &&
                item.type === "Room" &&
                item.id === wantedRoomId &&
                item.for_account === wantedUserId
            ) || (
                currentShouldBeAccount &&
                item.type === "Account" &&
                item.id === wantedUserId
            )) {
                currentIndex = i
                return true
            }
        }

        return false
    }

    highlightRangeMode:
        keepListCentered ? ListView.ApplyRange : ListView.NoHighlightRange

    model: ModelStore.get("all_rooms")

    delegate: DelegateChooser {
        role: "type"

        DelegateChoice {
            roleValue: "Account"
            AccountDelegate {
                width: roomList.width
                leftPadding: theme.spacing
                rightPadding: 0  // the right buttons have padding

                filterActive: Boolean(filter)
                enableKeybinds: Boolean(
                    roomList.model.get(currentIndex) && (
                        roomList.model.get(currentIndex).for_account ||
                        roomList.model.get(currentIndex).id
                    ) === model.id
                )

                totalMessageIndicator.visible: false

                onLeftClicked: showItemAtIndex(model.index, true)
                onCollapsedChanged:
                    if (wantedUserId === model.id) startCorrectItemSearch()

                onWentToAccountPage: roomList.currentIndex = model.index
            }
        }

        DelegateChoice {
            roleValue: "Room"
            RoomDelegate {
                width: roomList.width
                onLeftClicked: showItemAtIndex(model.index, true)
            }
        }
    }

    onFilterChanged: {
        py.callCoro("set_string_filter", ["all_rooms", filter], () => {
            if (filter) {
                currentIndex = 1  // highlight the first matching room
                return
            }

            const item = model.get(currentIndex)

            if (
                ! filter &&
                item && (
                    currentIndex === 1 || // required, related to the if above
                    (
                        currentShouldBeAccount &&
                        wantedUserId !== item.id
                    ) || (
                        currentShouldBeRoom && (
                            wantedUserId !== item.for_account ||
                            wantedRoomId !== item.id
                        )
                     )
                )
            )
                startCorrectItemSearch()
        })
    }

    Connections {
        target: pageLoader
        onPreviousShown: (componentUrl, properties)  => {
            if (setCorrectCurrentItem() === false) startCorrectItemSearch()
        }
    }

    Timer {
        // On startup, the account/room takes an unknown amount of time to
        // arrive in the model, try to find it until then.
        id: correctTimer
        interval: 200
        running: currentIndex === -1
        repeat: true
        triggeredOnStart: true
        onTriggered: setCorrectCurrentItem()
        onRunningChanged: if (running && currentIndex !== -1) currentIndex = -1
    }

    Timer {
        id: showItemLimiter
        interval: 100
        onTriggered: showItemAtIndex()
    }

    HShortcut {
        sequences: window.settings.Keys.Rooms.previous
        onActivated: { decrementCurrentIndex(); showItemLimiter.restart() }
    }

    HShortcut {
        sequences: window.settings.Keys.Rooms.next
        onActivated: { incrementCurrentIndex(); showItemLimiter.restart() }
    }

    HShortcut {
        sequences: window.settings.Keys.Rooms.previous_unread
        onActivated: { cycleUnreadRooms(false) && showItemLimiter.restart() }
    }

    HShortcut {
        sequences: window.settings.Keys.Rooms.next_unread
        onActivated: { cycleUnreadRooms(true) && showItemLimiter.restart() }
    }

    HShortcut {
        sequences: window.settings.Keys.Rooms.previous_highlight
        onActivated: cycleUnreadRooms(false, true) && showItemLimiter.restart()
    }

    HShortcut {
        sequences: window.settings.Keys.Rooms.next_highlight
        onActivated: cycleUnreadRooms(true, true) && showItemLimiter.restart()
    }

    HShortcut {
        sequences: window.settings.Keys.Rooms.latest_unread
        onActivated: latestUnreadRoom(false) && showItemLimiter.restart()
    }

    HShortcut {
        sequences: window.settings.Keys.Rooms.oldest_unread
        onActivated: latestUnreadRoom(true) && showItemLimiter.restart()
    }

    HShortcut {
        sequences: window.settings.Keys.Rooms.latest_highlight
        onActivated: latestUnreadRoom(false, true) && showItemLimiter.restart()
    }

    HShortcut {
        sequences: window.settings.Keys.Rooms.oldest_highlight
        onActivated: latestUnreadRoom(true, true) && showItemLimiter.restart()
    }

    Instantiator {
        model: Object.keys(window.settings.Keys.Accounts.AtIndex)
        delegate: Loader {
            sourceComponent: HShortcut {
                sequences: window.settings.Keys.Accounts.AtIndex[modelData]
                onActivated: goToAccountNumber(parseInt(modelData, 10) - 1)
            }
        }
    }

    Instantiator {
        model: Object.keys(window.settings.Keys.Rooms.AtIndex)
        delegate: Loader {
            sourceComponent: HShortcut {
                sequences: window.settings.Keys.Rooms.AtIndex[modelData]
                onActivated: showAccountRoomAtIndex(parseInt(modelData, 10) - 1)
            }
        }
    }

    Instantiator {
        model: Object.keys(window.settings.Keys.Rooms.Direct)
        delegate: Loader {
            sourceComponent: HShortcut {
                sequences: window.settings.Keys.Rooms.Direct[modelData]
                onActivated: showById(...modelData.split(/\s+/).reverse())
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        z: -100
        color: theme.mainPane.listView.background
    }
}
