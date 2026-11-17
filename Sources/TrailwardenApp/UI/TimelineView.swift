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
        // NavigationSplitView brought its own toolbar and safe-area handling, and
        // inside this window it kept drawing over the top of the content: first the
        // selection header, then — once the header moved out — the filter row.
        // HSplitView lays the three columns out and nothing else, so the window's
        // own row keeps the space it reserves.
        HSplitView {
            sidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            stream
                .frame(minWidth: 400, idealWidth: 620)
            Group {
                if let event = model.selectedEvent {
                    EventDetailView(
                        event: event,
                        onMute: onMute,
                        databaseURL: model.databaseURL,
                        onOpen: { other in
                            model.selection = .session(other.sessionId)
                            model.selectedEventID = other.id
                        })
                } else {
                    detailPlaceholder
                }
            }
            .frame(minWidth: 340, idealWidth: 460, maxWidth: 720)
        }
        .background(Tokens.Palette.paper)
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
            // No header of its own: the split view's toolbar sits right here and
            // painted over it. The selection title lives in the window's top row.
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

    private var filters: some View {
        // The search field moved to the window row, where there was empty space and
        // room to breathe; four controls fit in this column at its minimum width.
        HStack(spacing: 10) {
            rangePicker
            agentPicker
            toggles
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var rangePicker: some View {
        Picker("", selection: $model.window) {
            ForEach(TimelineWindow.allCases) { window in
                Text(window.shortLabel).tag(window)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var agentPicker: some View {
        Picker("", selection: $model.agentFilter) {
            Text(L(.allAgents)).tag(Agent?.none)
            ForEach(Agent.allCases, id: \.self) { agent in
                Text(EventFormatting.agentLabel(agent)).tag(Agent?.some(agent))
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var toggles: some View {
        HStack(spacing: 10) {
            FilterChip(title: L(.onlyFindings), isOn: $model.findingsOnly)
            FilterChip(title: L(.rawStream), isOn: $model.showRawEvents)
                .help(L(.showCountersHint))
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
        VStack(alignment: .leading, spacing: 8) {
            Text(L(.noEventsInRange))
                .font(Tokens.Typography.serif(14))
            Text(L(.noEventsHint))
                .font(Tokens.Typography.text(11))
                .foregroundStyle(Tokens.Palette.secondary)
            // A filter combination that matches nothing should not be a dead end.
            // Findings-only plus one session is the easy way to get here.
            Button(L(.clearFilters)) {
                model.findingsOnly = false
                model.agentFilter = nil
                model.search = ""
                model.selection = .all
                model.window = .month
            }
            .buttonStyle(.plain)
            .font(Tokens.Typography.text(11, weight: .medium))
            .foregroundStyle(Tokens.Palette.accent)
            .padding(.top, 2)
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
