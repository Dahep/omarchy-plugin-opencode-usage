import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.dahep.opencode-usage"
  ipcTarget: "io.github.dahep.opencode-usage"

  property double nowMs: Date.now()
  property string expandedProviderId: ""
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool alarming: service.go ? Model.behindPace(
    Model.normalizeWindow(service.go.weekly, "weekly", nowMs), nowMs) : false
  readonly property string barText: {
    if (!service.providers.length) return "OpenCode · —"
    var goWeekly = service.go ? Model.normalizeWindow(service.go.weekly, "weekly", nowMs) : null
    if (goWeekly) return "OpenCode · " + Model.percent(goWeekly.percent)
    return "OpenCode · " + Model.dollars(Model.weekCost(service.providers)) + "/wk"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    nowMs = Date.now()
    service.refresh()
  }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    if (!service.lastUpdated || (Date.now() - service.lastUpdated.getTime()) > service.refreshIntervalSec * 1000) root.refresh()
    Qt.callLater(function() { catcher.forceActiveFocus() })
  }

  Service {
    id: service
    settings: root.settings
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    fixedWidth: vertical ? -1 : content.implicitWidth + Style.space(16)
    tooltipText: "OpenCode provider usage · click for details"
    active: root.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        visible: !(bar ? bar.vertical : false)
        anchors.verticalCenter: parent.verticalCenter
        text: root.barText
        color: root.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(650))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(text) { if (text === "r" || text === "R") root.refresh() }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: body.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scroll.contentItem
          property: "interactive"
          value: body.implicitHeight > scroll.height
        }

        Column {
          id: body
          width: scroll.availableWidth
          spacing: Style.space(10)

          Text {
            width: parent.width
            text: "Updated " + (service.lastUpdated ? Qt.formatTime(service.lastUpdated, "HH:mm:ss") : "never") + " · " + (service.refreshing ? "Refreshing…" : "R to refresh") + " · click a provider for per-model usage"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelHero {
            width: parent.width
            title: "OpenCode Usage"
            meta: service.providers.length + " provider" + (service.providers.length === 1 ? "" : "s") + " · " + Model.tokenCount(Model.weekTotal(service.providers)) + " tokens this week"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: service.lastError !== ""
            width: parent.width
            text: service.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: service.refreshing && !service.providers.length
            width: parent.width
            text: "Loading usage…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            text: "PROVIDERS (7 DAYS)"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: service.providers

            delegate: ProviderCard {
              width: body.width
            }
          }

          PanelSectionHeader {
            text: "RECENT USAGE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: service.recentDays

              delegate: Column {
                required property var modelData
                width: (body.width - Style.space(24)) / 7

                Item {
                  width: parent.width
                  height: Style.space(28)

                  Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(10)
                    height: parent.height * Model.dayTokens(modelData) / Math.max(1, Model.recentPeak(service.recentDays))
                    color: root.foreground
                  }
                }

                Text {
                  width: parent.width
                  text: Model.dayLabel(modelData.date)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignHCenter
                }
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
            visible: !!service.go
          }

          GoSection {
            width: body.width
            visible: !!service.go
          }
        }
      }
    }
  }

  component ProviderCard: Column {
    id: providerCard
    required property var modelData
    readonly property var provider: modelData || {}
    readonly property bool expanded: root.expandedProviderId === provider.pid
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: headerCol.implicitHeight

      MouseArea {
        id: headerClick
        anchors.fill: parent
        cursorShape: provider.modelList && provider.modelList.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.expandedProviderId = providerCard.expanded ? "" : provider.pid
      }

      Column {
        id: headerCol
        width: parent.width
        spacing: Style.space(4)

        RowLayout {
          width: parent.width

          Text {
            text: (providerCard.expanded ? "▾ " : "▸ ") + Model.label(provider.pid)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Item { Layout.fillWidth: true }

          Text {
            text: provider.hasKey ? "" : "local data"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        RowLayout {
          width: parent.width

          Text {
            Layout.fillWidth: true
            text: "7d " + Model.tokenCount(Model.providerTokens(provider, true)) + " tokens · " + Model.dollars(Model.providerCost(provider, true))
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            text: "30d " + Model.tokenCount(Model.providerTokens(provider, false)) + " · " + Model.dollars(Model.providerCost(provider, false))
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(5)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

          Rectangle {
            width: parent.width * Model.providerWeekShare(provider, service.providers)
            height: parent.height
            radius: parent.radius
            color: root.foreground

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
          }
        }
      }
    }

    Column {
      id: breakdown
      visible: providerCard.expanded
      width: parent.width
      spacing: Style.space(4)

      Row {
        width: parent.width
        visible: provider.modelList && provider.modelList.length > 0

        Text {
          width: parent.width - Style.space(7 * 44)
          elide: Text.ElideRight
          text: "model"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Repeater {
          model: Model.datesOf(service.recentDays)

          Text {
            width: Style.space(44)
            text: Model.dayLabel(modelData)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            horizontalAlignment: Text.AlignRight
          }
        }
      }

      Repeater {
        model: provider.modelList

        delegate: Row {
          width: breakdown.width
          required property var modelData
          readonly property var series: Model.alignedSeries(modelData.daily, Model.datesOf(service.recentDays))

          Text {
            width: parent.width - Style.space(7 * 44)
            text: (modelData.modelName || "?") + " · " + Model.tokenCount(modelData.tokensWeek)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Repeater {
            model: series

            Text {
              width: Style.space(44)
              text: numberValue > 0 ? Model.tokenCount(numberValue) : "·"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
              readonly property double numberValue: modelData
            }
          }
        }
      }

      Text {
        visible: !(provider.modelList && provider.modelList.length > 0)
        width: parent.width
        text: "No usage in the last 7 days"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component GoSection: Column {
    id: goSection
    spacing: Style.space(6)

    readonly property var windows: [
      { key: "rolling", label: "5h", dollars: 12 },
      { key: "weekly", label: "Weekly", dollars: 30 },
      { key: "monthly", label: "Monthly", dollars: 60 }
    ]

    Text {
      width: parent.width
      text: "OpenCode Go limits"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Repeater {
      model: goSection.windows

      delegate: Column {
        id: windowRow
        required property var modelData
        width: goSection.width
        spacing: Style.space(2)
        readonly property var w: Model.normalizeWindow(service.go ? service.go[modelData.key] : null, modelData.key, root.nowMs)

        RowLayout {
          width: parent.width

          Text {
            Layout.preferredWidth: Style.space(58)
            text: modelData.label
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item { Layout.fillWidth: true }

          Text {
            Layout.fillWidth: true
            text: windowRow.w
              ? Model.percent(windowRow.w.percent) + " · $" + (windowRow.w.limitDollars || modelData.dollars)
              : (service.go && service.go.status && service.go.status !== "ok" ? service.go.status : "—")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(5)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

          Rectangle {
            width: parent.width * (windowRow.w ? windowRow.w.percent : 0)
            height: parent.height
            radius: parent.radius
            color: modelData.key === "weekly" && Model.behindPace(windowRow.w, root.nowMs) ? root.urgent : root.foreground

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 60 } }
          }
        }

        Text {
          visible: !!windowRow.w
          width: parent.width
          text: windowRow.w ? "resets " + Model.countdown(windowRow.w.resetMs, root.nowMs) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
