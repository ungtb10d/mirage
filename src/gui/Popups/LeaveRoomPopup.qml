// Copyright Mirage authors & contributors <https://github.com/mirukana/mirage>
// SPDX-License-Identifier: LGPL-3.0-or-later

import QtQuick 2.12
import QtQuick.Layouts 1.12
import "../Base"
import "../Base/Buttons"

HFlickableColumnPopup {
    id: popup

    property string userId: ""
    property string roomId: ""
    property string roomName: ""
    property string inviterId: ""
    property bool left: false
    property var doneCallback: null

    function ignoreInviter() {
        if (! inviterId) return
        py.callClientCoro(userId, "ignore_user", [inviterId, true])
    }

    function leave() {
        leaveButton.loading = true
        py.callClientCoro(userId, "room_leave", [roomId], doneCallback)
        if (ignoreInviterCheck.checked) popup.ignoreInviter()
        popup.close()
    }

    function forget() {
        leaveButton.loading = true

        py.callClientCoro(userId, "room_forget", [roomId], () => {
            if (window.uiState.page === "Pages/Chat/Chat.qml" &&
                window.uiState.pageProperties.userRoomId[0] === userId &&
                window.uiState.pageProperties.userRoomId[1] === roomId)
            {
                window.mainUI.pageLoader.showPrevious() ||
                window.mainUI.pageLoader.show("Pages/Default.qml")
            }

            Qt.callLater(popup.destroy)
        })

        if (ignoreInviterCheck.checked) popup.ignoreInviter()
    }

    page.footer: AutoDirectionLayout {
        ApplyButton {
            id: leaveButton
            icon.name: popup.left ? "room-forget" : "room-leave"
            text:
                popup.left ? qsTr("Forget") :
                popup.inviterId ? qsTr("Decline") :
                qsTr("Leave")

            onClicked:
                forgetCheck.checked || popup.left ?
                popup.forget() :
                popup.leave()
        }

        CancelButton {
            onClicked: popup.close()
        }
    }

    onOpened: leaveButton.forceActiveFocus()
    onClosed: if (doneCallback) doneCallback()

    SummaryLabel {
        readonly property string roomText:
            utils.htmlColorize(popup.roomName, theme.colors.accentText)

        textFormat: Text.StyledText
        text:
            popup.left ? qsTr("Forget the history for %1?").arg(roomText) :
            popup.inviterId ? qsTr("Decline invite to %1?").arg(roomText) :
            qsTr("Leave %1?").arg(roomText)
    }

    DetailsLabel {
        text:
            popup.left ?
            forgetCheck.subtitle.text :
            qsTr(
                "If this room is private, you will not be able to rejoin it " +
                "without a new invite."
            )
    }

    HCheckBox {
        id: ignoreInviterCheck
        visible: Boolean(popup.inviterId)
        mainText.textFormat: HLabel.StyledText

        // We purposely display inviter's user ID instead of display name here.
        // Someone could take the name of one of our contact, which would
        // not be disambiguated and lead to confusion.
        text: qsTr("Ignore sender %1").arg(
            utils.coloredNameHtml("", popup.inviterId),
        )
        subtitle.text: qsTr("Automatically hide their invites and messages")

        Layout.fillWidth: true
    }

    HCheckBox {
        id: forgetCheck
        visible: ! popup.left
        text: qsTr("Forget this room's history")
        subtitle.text: qsTr(
            "Access to previously received messages will be lost.\n" +
            "If all members forget a room, servers will erase it."
        )

        Layout.fillWidth: true
    }

}
