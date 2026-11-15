// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// A checkbox the panel actually draws: the stock checkbox renders as a blank
/// grey square on this palette and is easy to read as disabled.
private struct FilterChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundStyle(isOn ? Tokens.Palette.accent : Tokens.Palette.secondary)
                Text(title)
                    .font(Tokens.Typography.text(10.5, weight: isOn ? .medium : .regular))
                    .foregroundStyle(Tokens.Palette.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Sidebar (project → session) plus the paged event stream.
struct TimelineView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: TimelineModel
    var onMute: ((RiskHit, Event) -> Void)?
    var liveSessionIDs: Set<String> = []
    @FocusState private var searchFocused: Bool

    private var selectionBinding: Binding<TimelineSelection?> {
        Binding(
            get: { model.selection },
            set: {
                if let value = $0 {
                    model.selection = value
                }
            })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            stream
                .navigationSplitViewColumnWidth(min: 380, ideal: 620, max: 1100)
        } detail: {
            if let event = model.selectedEvent {
                EventDetailView(event: event, onMute: onMute)
                    .navigationSplitViewColumnWidth(min: 340, ideal: 460, max: 720)
            } else {
                detailPlaceholder
                    .navigationSplitViewColumnWidth(min: 340, ideal: 460, max: 720)
            }
        }
        // The paper palette is light-only, so pin the appearance: a dark system
        // theme otherwise paints the title bar dark and the selected sidebar row
        // white-on-white.
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: selectionBinding) {
            Section(L(.scope)) {
                Label(L(.allSessions), systemImage: "tray.full")
                    .tag(TimelineSelection.all)
            }

            Section(L(.projects)) {
                ForEach(model.projects) { project in
                    DisclosureGroup {
                        ForEach(model.sessions(inProject: project.cwd)) { session in
                            sessionLabel(session)
                                .tag(TimelineSelection.session(session.id))
                        }
                        if model.sessions(inProject: project.cwd).isEmpty {
                            Text(L(.noSessionSelected))
                                .font(Tokens.Typography.text(10))
                                .foregroundStyle(Tokens.Palette.secondary)
                        }
                    } label: {
                        projectLabel(project)
                            .tag(TimelineSelection.project(project.cwd))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Tokens.Palette.paper)
    }

    private func projectLabel(_ project: ProjectSummary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 10))
                .foregroundStyle(Tokens.Palette.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(ProjectName.short(project.cwd))
                    .font(Tokens.Typography.text(11.5, weight: .medium))
                    .lineLimit(1)
                Text(Lf(.projectMeta, [project.sessionCount, project.eventCount]))
                    .font(Tokens.Typography.text(9))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
        }
    }

    private func sessionLabel(_ session: SessionSummary) -> some View {
        HStack(spacing: 6) {
            Text(EventFormatting.agentLabel(session.agent))
                .font(Tokens.Typography.mono(8))
                .padding(.horizontal, 4)
                .padding(.vertical, 0.5)
                .background(Tokens.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 2.5))
            Text(Sessions.shortID(session.id))
                .font(Tokens.Typography.mono(9))
                .lineLimit(1)
            Spacer(minLength: 2)
            if liveSessionIDs.contains(session.id) {
                Circle()
                    .fill(Tokens.Palette.accent)
                    .frame(width: 5, height: 5)
                    .help(L(.liveTooltip))
            }
            if session.criticalCount > 0 {
                Text("\(session.criticalCount)")
                    .font(Tokens.Typography.text(9, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accent)
            }
        }
    }

    // MARK: - Stream

    private var stream: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            filters
            Hairline()
            list
            Hairline()
            footer
        }
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .tint(Tokens.Palette.accent)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.selectionTitle)
                .font(Tokens.Typography.serif(16, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Text(Lf(.eventCount, [model.total]))
                .font(Tokens.Typography.mono(10))
                .foregroundStyle(Tokens.Palette.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var filters: some View {
        HStack(spacing: 10) {
            Picker("", selection: $model.window) {
                ForEach(TimelineWindow.allCases) { window in
                    Text(window.rawValue).tag(window)
                }
            }
            .labelsHidden()
            .frame(width: 96)
            .fixedSize()

            Picker("", selection: $model.agentFilter) {
                Text(L(.allAgents)).tag(Agent?.none)
                ForEach(Agent.allCases, id: \.self) { agent in
                    Text(EventFormatting.agentLabel(agent)).tag(Agent?.some(agent))
                }
            }
            .labelsHidden()
            .frame(width: 118)
            .fixedSize()

            FilterChip(title: L(.onlyFindings), isOn: $model.findingsOnly)
                .layoutPriority(1)
            FilterChip(title: L(.rawStream), isOn: $model.showRawEvents)
                .layoutPriority(1)
                .help(L(.showCountersHint))

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Tokens.Palette.secondary)
                TextField("Ara", text: $model.search)
                    .textFieldStyle(.plain)
                    .font(Tokens.Typography.text(11))
                    .focused($searchFocused)
                    .frame(minWidth: 90, idealWidth: 140, maxWidth: 170)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Tokens.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background {
            // ⌘F focuses the search field, the way every other list does.
            Button("Ara") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.events) { event in
                    EventRowView(event: event, selected: model.selectedEventID == event.id)
                        .onTapGesture { model.selectedEventID = event.id }
                        .onAppear {
                            if event.id == model.events.last?.id {
                                model.loadMore()
                            }
                        }
                    Hairline()
                }
                if model.events.isEmpty {
                    emptyState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The content column otherwise paints the window's default white over the
        // paper background, which is what made the list look like a different
        // surface than the detail beside it.
        .background(Tokens.Palette.paper)
    }

    private var detailPlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(.pickEvent))
                .font(Tokens.Typography.serif(14))
            Text(L(.pickEventHint))
                .font(Tokens.Typography.text(11))
                .foregroundStyle(Tokens.Palette.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.Palette.paper)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(.noEventsInRange))
                .font(Tokens.Typography.serif(14))
            Text(L(.noEventsHint))
                .font(Tokens.Typography.text(11))
                .foregroundStyle(Tokens.Palette.secondary)
        }
        .padding(24)
    }

    private var footer: some View {
        HStack {
            if let error = model.errorMessage {
                Text(error)
                    .font(Tokens.Typography.text(10))
                    .foregroundStyle(Tokens.Palette.accent)
                    .lineLimit(1)
            } else {
                Text(model.events.isEmpty
                    ? "0 olay"
                    : Lf(.eventsRatio, [model.events.count, model.total]))
                    .font(Tokens.Typography.mono(9.5))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            Spacer()
            if model.events.count < model.total {
                Button(L(.loadMore)) { model.loadMore() }
                    .buttonStyle(.plain)
                    .font(Tokens.Typography.text(10.5, weight: .medium))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
